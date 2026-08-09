import Foundation
import SwiftData
import TendCore

typealias ReminderCurrentBucketFactsProvider = (
  _ habit: Habit,
  _ instant: Date,
  _ timeZone: TimeZone
) throws -> ReminderCurrentBucketFacts

enum ReminderCoordinatorOperation: Equatable {
  case readAuthorizationStatus
  case fetchHabits
  case projectHabit(UUID)
  case readPendingRequests
  case removePendingRequest(String)
  case addOrReplace(String)
}

struct ReminderCoordinatorFailure {
  let operation: ReminderCoordinatorOperation
  let underlyingError: any Error
}

struct ReminderCoordinatorDiagnostic: Error {
  let failures: [ReminderCoordinatorFailure]
}

@MainActor
final class ReminderCoordinator {
  private let context: ModelContext
  private let notificationCenter: any ReminderNotificationCenterClient
  private let planner: ReminderPlanner
  private let now: () -> Date
  private let timeZone: TimeZone
  private let requestLimit: Int
  private let currentBucketFacts: ReminderCurrentBucketFactsProvider

  private var refreshTask: Task<Void, Never>?
  private var needsFollowUpRefresh = false

  private(set) var diagnosticError: ReminderCoordinatorDiagnostic?

  init(
    context: ModelContext,
    notificationCenter: any ReminderNotificationCenterClient,
    now: @escaping () -> Date = Date.init,
    calendar: Calendar = .autoupdatingCurrent,
    timeZone: TimeZone = .autoupdatingCurrent,
    locale: Locale = .autoupdatingCurrent,
    requestLimit: Int = 64,
    currentBucketFacts: ReminderCurrentBucketFactsProvider? = nil
  ) {
    self.context = context
    self.notificationCenter = notificationCenter
    planner = ReminderPlanner(
      calendar: calendar,
      timeZone: timeZone,
      locale: locale
    )
    self.now = now
    self.timeZone = timeZone
    self.requestLimit = requestLimit
    if let currentBucketFacts {
      self.currentBucketFacts = currentBucketFacts
    } else {
      let computation = HabitTodayComputation(context: context)
      self.currentBucketFacts = { habit, instant, timeZone in
        let snapshot = try computation.snapshot(
          for: habit,
          at: instant,
          timeZone: timeZone
        )
        return ReminderCurrentBucketFacts(
          periodKey: snapshot.periodKey,
          progress: snapshot.progress,
          target: snapshot.target,
          unit: snapshot.unit,
          isMet: snapshot.isMet
        )
      }
    }
  }

  convenience init(
    context: ModelContext,
    now: @escaping () -> Date = Date.init,
    calendar: Calendar = .autoupdatingCurrent,
    timeZone: TimeZone = .autoupdatingCurrent,
    locale: Locale = .autoupdatingCurrent,
    requestLimit: Int = 64
  ) {
    self.init(
      context: context,
      notificationCenter: LiveReminderNotificationCenter(),
      now: now,
      calendar: calendar,
      timeZone: timeZone,
      locale: locale,
      requestLimit: requestLimit
    )
  }

  func refresh() async {
    if let refreshTask {
      needsFollowUpRefresh = true
      await refreshTask.value
      return
    }

    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await runRefreshLoop()
    }
    refreshTask = task
    await task.value
  }

  private func runRefreshLoop() async {
    repeat {
      needsFollowUpRefresh = false
      await performRefresh()
    } while needsFollowUpRefresh
    refreshTask = nil
  }

  private func performRefresh() async {
    var failures: [ReminderCoordinatorFailure] = []
    let status: ReminderAuthorizationStatus
    do {
      status = try await notificationCenter.authorizationStatus()
    } catch {
      failures.append(
        ReminderCoordinatorFailure(
          operation: .readAuthorizationStatus,
          underlyingError: error
        ))
      diagnosticError = ReminderCoordinatorDiagnostic(failures: failures)
      return
    }

    let pendingRequests: [ReminderPendingRequest]?
    do {
      pendingRequests = try await notificationCenter.tendPendingRequests()
    } catch {
      pendingRequests = nil
      failures.append(
        ReminderCoordinatorFailure(
          operation: .readPendingRequests,
          underlyingError: error
        ))
    }

    switch status {
    case .denied, .notDetermined, .unavailable:
      if let pendingRequests {
        await remove(
          identifiers: pendingRequests.map(\.identifier).sorted(),
          recordingFailuresIn: &failures
        )
      }
    case .authorized:
      guard let desired = desiredOccurrences(recordingFailuresIn: &failures) else {
        diagnosticError = ReminderCoordinatorDiagnostic(failures: failures)
        return
      }
      await reconcile(
        desired: desired,
        pending: pendingRequests,
        recordingFailuresIn: &failures
      )
    }

    diagnosticError =
      failures.isEmpty
      ? nil
      : ReminderCoordinatorDiagnostic(failures: failures)
  }

  private func desiredOccurrences(
    recordingFailuresIn failures: inout [ReminderCoordinatorFailure]
  ) -> [ReminderOccurrence]? {
    let habits: [Habit]
    do {
      habits = try context.fetch(FetchDescriptor<Habit>())
    } catch {
      failures.append(
        ReminderCoordinatorFailure(
          operation: .fetchHabits,
          underlyingError: error
        ))
      return nil
    }

    let instant = now()
    var facts: [ReminderHabitFacts] = []
    facts.reserveCapacity(habits.count)
    for habit in habits {
      guard habit.isActive, habit.reminderMinuteOfDay != nil else { continue }
      do {
        let current = try currentBucketFacts(habit, instant, timeZone)
        facts.append(
          ReminderHabitFacts(
            id: habit.id,
            name: habit.name,
            cadenceRawValue: habit.cadenceRawValue,
            target: habit.target,
            unit: habit.unit,
            pinnedWeekdaysRawValue: habit.pinnedWeekdaysRawValue,
            reminderMinuteOfDay: habit.reminderMinuteOfDay,
            isActive: habit.isActive,
            currentBucket: current
          ))
      } catch {
        failures.append(
          ReminderCoordinatorFailure(
            operation: .projectHabit(habit.id),
            underlyingError: error
          ))
      }
    }

    return planner.plan(
      habits: facts,
      at: instant,
      limit: requestLimit
    )
  }

  private func reconcile(
    desired: [ReminderOccurrence],
    pending: [ReminderPendingRequest]?,
    recordingFailuresIn failures: inout [ReminderCoordinatorFailure]
  ) async {
    guard let pending else {
      await add(desired, recordingFailuresIn: &failures)
      return
    }

    var pendingByIdentifier: [String: ReminderPendingRequest] = [:]
    pendingByIdentifier.reserveCapacity(pending.count)
    for request in pending {
      pendingByIdentifier[request.identifier] = request
    }
    var desiredByIdentifier: [String: ReminderOccurrence] = [:]
    desiredByIdentifier.reserveCapacity(desired.count)
    for occurrence in desired {
      desiredByIdentifier[occurrence.identifier] = occurrence
    }

    let removals = pending.compactMap { request -> String? in
      guard let occurrence = desiredByIdentifier[request.identifier] else {
        return request.identifier
      }
      return request == ReminderPendingRequest(occurrence: occurrence)
        ? nil
        : request.identifier
    }.sorted()
    await remove(
      identifiers: removals,
      recordingFailuresIn: &failures
    )

    let additions = desired.filter { occurrence in
      pendingByIdentifier[occurrence.identifier]
        != ReminderPendingRequest(occurrence: occurrence)
    }
    await add(additions, recordingFailuresIn: &failures)
  }

  private func remove(
    identifiers: [String],
    recordingFailuresIn failures: inout [ReminderCoordinatorFailure]
  ) async {
    for identifier in identifiers {
      do {
        try await notificationCenter.removePendingRequest(
          withIdentifier: identifier
        )
      } catch {
        failures.append(
          ReminderCoordinatorFailure(
            operation: .removePendingRequest(identifier),
            underlyingError: error
          ))
      }
    }
  }

  private func add(
    _ occurrences: [ReminderOccurrence],
    recordingFailuresIn failures: inout [ReminderCoordinatorFailure]
  ) async {
    for occurrence in occurrences {
      do {
        try await notificationCenter.addOrReplace(occurrence)
      } catch {
        failures.append(
          ReminderCoordinatorFailure(
            operation: .addOrReplace(occurrence.identifier),
            underlyingError: error
          ))
      }
    }
  }
}
