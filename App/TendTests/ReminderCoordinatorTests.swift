import Foundation
import SwiftData
import TendCore
import Testing
import UserNotifications

@testable import Tend

@Suite("Reminder coordinator")
@MainActor
struct ReminderCoordinatorTests {
  @Test("authorized refresh removes stale requests and replaces only changed requests")
  func authorizedRefreshReconcilesExactRequestValues() async throws {
    let fixture = try Fixture()
    let walk = try fixture.insertHabit(
      id: 1,
      name: "Walk",
      reminderMinuteOfDay: 9 * 60
    )
    let read = try fixture.insertHabit(
      id: 2,
      name: "Read",
      reminderMinuteOfDay: 10 * 60
    )
    let desired = fixture.plan(for: [walk, read], limit: 2)
    let matching = ReminderPendingRequest(occurrence: desired[0])
    let changed = ReminderPendingRequest(
      identifier: desired[1].identifier,
      title: desired[1].title,
      body: "Old body",
      dateComponents: desired[1].dateComponents
    )
    let obsolete = ReminderPendingRequest(
      identifier: "tend.reminder.obsolete.2026-01-05",
      title: "Tend",
      body: "Obsolete",
      dateComponents: desired[0].dateComponents
    )
    let center = FakeReminderNotificationCenter(
      authorizationStatus: .authorized,
      pendingRequests: [matching, changed, obsolete]
    )
    let coordinator = fixture.makeCoordinator(center: center, limit: 2)

    await coordinator.refresh()

    #expect(center.removedIdentifiers == [changed.identifier, obsolete.identifier].sorted())
    #expect(center.addedOccurrences == [desired[1]])
    #expect(center.requestAuthorizationCallCount == 0)
    #expect(coordinator.diagnosticError == nil)
  }

  @Test("live adapter maps complete one-shot request values")
  func liveAdapterMapsCompleteRequestValues() throws {
    let fixture = try Fixture()
    let habit = try fixture.insertHabit(
      id: 1,
      name: "Walk",
      reminderMinuteOfDay: 9 * 60
    )
    let occurrence = try #require(fixture.plan(for: [habit], limit: 1).first)
    let request = LiveReminderNotificationCenter.notificationRequest(
      for: occurrence
    )

    #expect(request.identifier == occurrence.identifier)
    #expect(request.content.title == occurrence.title)
    #expect(request.content.body == occurrence.body)
    #expect(request.content.sound == .default)
    #expect(request.content.badge == nil)
    #expect(request.content.categoryIdentifier == "tend.reminder")
    #expect(request.content.userInfo["tend.reminder"] as? Bool == true)
    let trigger = try #require(
      request.trigger as? UNCalendarNotificationTrigger
    )
    #expect(!trigger.repeats)
    #expect(trigger.dateComponents == occurrence.dateComponents)
    #expect(
      LiveReminderNotificationCenter.projectPendingRequest(request)
        == ReminderPendingRequest(occurrence: occurrence)
    )
    let wrongSoundContent = try #require(
      request.content.mutableCopy() as? UNMutableNotificationContent
    )
    wrongSoundContent.sound = .defaultCritical
    let wrongSoundRequest = UNNotificationRequest(
      identifier: request.identifier,
      content: wrongSoundContent,
      trigger: trigger
    )
    #expect(
      LiveReminderNotificationCenter.projectPendingRequest(wrongSoundRequest)
        != ReminderPendingRequest(occurrence: occurrence)
    )
  }

  @Test("live pending projection retains malformed Tend requests for removal")
  func liveProjectionRetainsMalformedOwnedRequests() throws {
    let content = UNMutableNotificationContent()
    let owned = UNNotificationRequest(
      identifier: "tend.reminder.malformed",
      content: content,
      trigger: nil
    )
    let foreign = UNNotificationRequest(
      identifier: "other.malformed",
      content: content,
      trigger: nil
    )

    let projected = try #require(
      LiveReminderNotificationCenter.projectPendingRequest(owned)
    )
    #expect(projected.identifier == owned.identifier)
    #expect(projected.dateComponents == nil)
    #expect(LiveReminderNotificationCenter.projectPendingRequest(foreign) == nil)
  }

  @Test("live settings map provisional delivery and disabled surfaces")
  func liveAuthorizationProjectionRepresentsDeliverability() {
    #expect(
      LiveReminderNotificationCenter.projectAuthorizationStatus(
        .notDetermined,
        alertSetting: .enabled,
        notificationCenterSetting: .enabled,
        lockScreenSetting: .enabled
      ) == .notDetermined
    )
    #expect(
      LiveReminderNotificationCenter.projectAuthorizationStatus(
        .denied,
        alertSetting: .enabled,
        notificationCenterSetting: .enabled,
        lockScreenSetting: .enabled
      ) == .denied
    )
    #expect(
      LiveReminderNotificationCenter.projectAuthorizationStatus(
        .authorized,
        alertSetting: .enabled,
        notificationCenterSetting: .enabled,
        lockScreenSetting: .enabled
      ) == .authorized
    )
    #expect(
      LiveReminderNotificationCenter.projectAuthorizationStatus(
        .provisional,
        alertSetting: .disabled,
        notificationCenterSetting: .enabled,
        lockScreenSetting: .disabled
      ) == .authorized
    )
    #expect(
      LiveReminderNotificationCenter.projectAuthorizationStatus(
        .authorized,
        alertSetting: .disabled,
        notificationCenterSetting: .disabled,
        lockScreenSetting: .disabled
      ) == .unavailable
    )
  }

  @Test("unavailable authorization removes Tend requests without prompting")
  func unavailableAuthorizationRemovesPendingRequests() async throws {
    for status in [
      ReminderAuthorizationStatus.denied,
      .notDetermined,
      .unavailable,
    ] {
      let fixture = try Fixture()
      let habit = try fixture.insertHabit(
        id: 1,
        name: "Walk",
        reminderMinuteOfDay: 9 * 60
      )
      let pending = ReminderPendingRequest(occurrence: fixture.plan(for: [habit], limit: 1)[0])
      let center = FakeReminderNotificationCenter(
        authorizationStatus: status,
        pendingRequests: [pending]
      )
      let coordinator = fixture.makeCoordinator(center: center, limit: 1)

      await coordinator.refresh()

      #expect(center.removedIdentifiers == [pending.identifier])
      #expect(center.addedOccurrences.isEmpty)
      #expect(center.requestAuthorizationCallCount == 0)
      #expect(coordinator.diagnosticError == nil)
    }
  }

  @Test("a fresh coordinator leaves an exact pending plan unchanged")
  func relaunchReconciliationDoesNotChurnExactRequests() async throws {
    let fixture = try Fixture()
    _ = try fixture.insertHabit(
      id: 1,
      name: "Walk",
      reminderMinuteOfDay: 9 * 60
    )
    let center = FakeReminderNotificationCenter(authorizationStatus: .authorized)

    await fixture.makeCoordinator(center: center, limit: 1).refresh()
    #expect(center.addedOccurrences.count == 1)
    center.resetRecordedMutations()

    await fixture.makeCoordinator(center: center, limit: 1).refresh()

    #expect(center.removedIdentifiers.isEmpty)
    #expect(center.addedOccurrences.isEmpty)
  }

  @Test("editing one reminder reschedules only that habit")
  func scheduleMutationDoesNotChurnUnaffectedHabits() async throws {
    let fixture = try Fixture()
    let walk = try fixture.insertHabit(
      id: 1,
      name: "Walk",
      reminderMinuteOfDay: 9 * 60
    )
    _ = try fixture.insertHabit(
      id: 2,
      name: "Read",
      reminderMinuteOfDay: 10 * 60
    )
    let center = FakeReminderNotificationCenter(authorizationStatus: .authorized)
    let coordinator = fixture.makeCoordinator(center: center, limit: 2)
    await coordinator.refresh()
    let walkIdentifier = try #require(
      center.addedOccurrences.first { $0.habitID == walk.id }
    ).identifier
    center.resetRecordedMutations()

    walk.reminderMinuteOfDay = 11 * 60
    try fixture.context.save()
    await coordinator.refresh()

    #expect(center.removedIdentifiers == [walkIdentifier])
    #expect(center.addedOccurrences.map(\.identifier) == [walkIdentifier])
  }

  @Test("current bucket completion replaces today's request with the next eligible day")
  func currentBucketCompletionSuppressesTodaysRequest() async throws {
    let fixture = try Fixture()
    let habit = try HabitManagementOperations(context: fixture.context).create(
      fields: HabitEditableFields(
        name: "Walk",
        target: 1,
        reminderTime: ReminderTime(rawValue: 9 * 60)
      ),
      cadence: .daily,
      at: fixture.now,
      timeZone: fixture.timeZone
    )
    let center = FakeReminderNotificationCenter(authorizationStatus: .authorized)
    let coordinator = fixture.makeCoordinator(center: center, limit: 1)

    await coordinator.refresh()
    let today = try #require(center.addedOccurrences.first)
    center.resetRecordedMutations()
    try LogEntryOperations(context: fixture.context).append(
      amount: 1,
      to: habit,
      at: fixture.now,
      timeZone: fixture.timeZone
    )

    await coordinator.refresh()

    let tomorrow = try #require(center.addedOccurrences.first)
    #expect(center.removedIdentifiers == [today.identifier])
    #expect(tomorrow.habitID == habit.id)
    #expect(tomorrow.fireDate > today.fireDate)
    #expect(tomorrow.identifier != today.identifier)
  }

  @Test("removal and add failures do not block independent additions")
  func operationFailuresAreIsolatedAndRetained() async throws {
    let fixture = try Fixture()
    let first = try fixture.insertHabit(
      id: 1,
      name: "Walk",
      reminderMinuteOfDay: 9 * 60
    )
    let second = try fixture.insertHabit(
      id: 2,
      name: "Read",
      reminderMinuteOfDay: 10 * 60
    )
    let desired = fixture.plan(for: [first, second], limit: 2)
    let stale = ReminderPendingRequest(
      identifier: "tend.reminder.stale.2026-01-05",
      title: "Tend",
      body: "Stale",
      dateComponents: desired[0].dateComponents
    )
    let otherStale = ReminderPendingRequest(
      identifier: "tend.reminder.other-stale.2026-01-05",
      title: "Tend",
      body: "Other stale",
      dateComponents: desired[1].dateComponents
    )
    let center = FakeReminderNotificationCenter(
      authorizationStatus: .authorized,
      pendingRequests: [stale, otherStale]
    )
    center.failingRemoveIdentifiers = [stale.identifier]
    center.failingAddIdentifiers = [desired[0].identifier]
    let coordinator = fixture.makeCoordinator(center: center, limit: 2)

    await coordinator.refresh()

    #expect(
      center.removedIdentifiers
        == [stale.identifier, otherStale.identifier].sorted()
    )
    #expect(center.addAttemptIdentifiers == desired.map(\.identifier))
    #expect(center.pendingRequests.contains { $0.identifier == desired[1].identifier })
    #expect(!center.pendingRequests.contains { $0.identifier == otherStale.identifier })
    let operations = try #require(coordinator.diagnosticError).failures.map(\.operation)
    #expect(
      operations == [
        .removePendingRequest(stale.identifier),
        .addOrReplace(desired[0].identifier),
      ])

    center.failingRemoveIdentifiers = []
    center.failingAddIdentifiers = []
    center.resetRecordedMutations()
    await coordinator.refresh()

    #expect(coordinator.diagnosticError == nil)
    #expect(center.removedIdentifiers == [stale.identifier])
    #expect(center.addedOccurrences == [desired[0]])
    #expect(
      Set(center.pendingRequests.map(\.identifier))
        == Set(desired.map(\.identifier))
    )
  }

  @Test("one malformed habit does not block valid scheduling or stale removal")
  func habitProjectionFailuresAreIsolated() async throws {
    let fixture = try Fixture()
    let malformed = try fixture.insertHabit(
      id: 1,
      name: "Malformed",
      reminderMinuteOfDay: 9 * 60
    )
    let valid = try fixture.insertHabit(
      id: 2,
      name: "Read",
      reminderMinuteOfDay: 10 * 60
    )
    let malformedPending = ReminderPendingRequest(
      occurrence: try #require(
        fixture.plan(for: [malformed], limit: 1).first
      )
    )
    let center = FakeReminderNotificationCenter(
      authorizationStatus: .authorized,
      pendingRequests: [malformedPending]
    )
    let coordinator = fixture.makeCoordinator(
      center: center,
      limit: 2,
      currentBucketFacts: { habit, _, _ in
        guard habit.id != malformed.id else { throw TestFailure.expected }
        return fixture.currentFacts(for: habit)
      }
    )

    await coordinator.refresh()

    #expect(center.removedIdentifiers == [malformedPending.identifier])
    #expect(
      center.addedOccurrences
        == fixture.plan(for: [valid], limit: 2)
    )
    let operations = try #require(coordinator.diagnosticError)
      .failures.map(\.operation)
    #expect(operations == [.projectHabit(malformed.id)])
  }

  @Test("a pending snapshot failure still allows safe add-or-replace operations")
  func pendingSnapshotFailureStillAddsDesiredRequests() async throws {
    let fixture = try Fixture()
    let habit = try fixture.insertHabit(
      id: 1,
      name: "Walk",
      reminderMinuteOfDay: 9 * 60
    )
    let center = FakeReminderNotificationCenter(
      authorizationStatus: .authorized
    )
    center.pendingRequestsError = TestFailure.expected
    let coordinator = fixture.makeCoordinator(center: center, limit: 1)

    await coordinator.refresh()

    #expect(
      center.addedOccurrences
        == fixture.plan(for: [habit], limit: 1)
    )
    let operations = try #require(coordinator.diagnosticError)
      .failures.map(\.operation)
    #expect(operations == [.readPendingRequests])
  }

  @Test("one refresh samples one context for exact daily and weekly plans")
  func refreshSamplesOneContextForDailyAndWeeklyPlans() async throws {
    let fixture = try Fixture()
    let daily = try fixture.insertHabit(
      id: 1,
      name: "Walk",
      reminderMinuteOfDay: 9 * 60
    )
    let weekly = try fixture.insertHabit(
      id: 2,
      name: "Read",
      reminderMinuteOfDay: 10 * 60
    )
    weekly.cadenceRawValue = HabitCadence.weekly.rawValue
    weekly.pinnedWeekdaysRawValue = PinnedWeekdays.monday.rawValue
    try fixture.context.save()
    var samples: [(Date, TimeZone)] = []
    let center = FakeReminderNotificationCenter(
      authorizationStatus: .authorized
    )
    let coordinator = fixture.makeCoordinator(
      center: center,
      limit: 2,
      currentBucketFacts: { habit, instant, timeZone in
        samples.append((instant, timeZone))
        return fixture.currentFacts(for: habit)
      }
    )

    await coordinator.refresh()

    #expect(samples.count == 2)
    #expect(samples.allSatisfy { $0 == (fixture.now, fixture.timeZone) })
    #expect(
      center.addedOccurrences
        == fixture.plan(for: [daily, weekly], limit: 2)
    )
  }

  @Test("ineligible habits remove their pending requests")
  func ineligibleHabitsRemovePendingRequests() async throws {
    let fixture = try Fixture()
    let archived = try fixture.insertHabit(
      id: 1,
      name: "Archived",
      reminderMinuteOfDay: 9 * 60
    )
    let deleted = try fixture.insertHabit(
      id: 2,
      name: "Deleted",
      reminderMinuteOfDay: 10 * 60
    )
    let noPins = try fixture.insertHabit(
      id: 3,
      name: "No pins",
      reminderMinuteOfDay: 11 * 60
    )
    let noReminder = try fixture.insertHabit(
      id: 4,
      name: "No reminder",
      reminderMinuteOfDay: 12 * 60
    )
    let met = try fixture.insertHabit(
      id: 5,
      name: "Met",
      reminderMinuteOfDay: 13 * 60
    )
    let habits = [archived, deleted, noPins, noReminder, met]
    let pending = fixture.plan(for: habits, limit: habits.count)
      .map(ReminderPendingRequest.init(occurrence:))

    archived.isActive = false
    fixture.context.delete(deleted)
    noPins.cadenceRawValue = HabitCadence.weekly.rawValue
    noPins.pinnedWeekdaysRawValue = PinnedWeekdays.none.rawValue
    noReminder.reminderMinuteOfDay = nil
    try fixture.context.save()
    let center = FakeReminderNotificationCenter(
      authorizationStatus: .authorized,
      pendingRequests: pending
    )
    let coordinator = fixture.makeCoordinator(
      center: center,
      limit: habits.count,
      currentBucketFacts: { habit, _, _ in
        let facts = fixture.currentFacts(for: habit)
        guard habit.id == met.id else { return facts }
        return ReminderCurrentBucketFacts(
          periodKey: facts.periodKey,
          progress: facts.target,
          target: facts.target,
          unit: facts.unit,
          isMet: true
        )
      }
    )

    await coordinator.refresh()

    #expect(
      center.removedIdentifiers
        == pending.map(\.identifier).sorted()
    )
    #expect(!center.addedOccurrences.isEmpty)
    #expect(center.addedOccurrences.allSatisfy { $0.habitID == met.id })
    #expect(center.addedOccurrences.allSatisfy { $0.fireDate > fixture.now })
  }

  @Test("the adapter receives one bounded plan with unique identifiers")
  func adapterReceivesBoundedUniquePlan() async throws {
    let fixture = try Fixture()
    for id in 1...65 {
      _ = try fixture.insertHabit(
        id: id,
        name: "Habit \(id)",
        reminderMinuteOfDay: 9 * 60
      )
    }
    let center = FakeReminderNotificationCenter(
      authorizationStatus: .authorized
    )

    await fixture.makeCoordinator(center: center, limit: 100).refresh()

    #expect(center.addedOccurrences.count == 64)
    #expect(Set(center.addedOccurrences.map(\.identifier)).count == 64)
    #expect(center.addAttemptIdentifiers == center.addedOccurrences.map(\.identifier))
  }

  @Test("overlapping refreshes serialize into one follow-up pass")
  func overlappingRefreshesAreCoalesced() async throws {
    let fixture = try Fixture()
    _ = try fixture.insertHabit(
      id: 1,
      name: "Walk",
      reminderMinuteOfDay: 9 * 60
    )
    let center = FakeReminderNotificationCenter(authorizationStatus: .denied)
    center.pauseFirstAuthorizationRead = true
    let coordinator = fixture.makeCoordinator(center: center, limit: 1)

    let first = Task { await coordinator.refresh() }
    await center.waitUntilAuthorizationReadPauses()
    center.stubbedAuthorizationStatus = .authorized
    let entryGate = RefreshCallerGate(expectedCount: 3)
    let overlappingCallers = (0..<3).map { _ in
      Task { @MainActor in
        entryGate.enter()
        await coordinator.refresh()
      }
    }
    await entryGate.waitUntilAllEntered()
    center.resumeAuthorizationRead()
    await first.value
    for caller in overlappingCallers {
      await caller.value
    }

    #expect(center.authorizationStatusCallCount == 2)
    #expect(center.maximumConcurrentOperations == 1)
    #expect(center.addedOccurrences.count == 1)
  }
}

@MainActor
private struct Fixture {
  let context: ModelContext
  let now: Date
  let calendar: Calendar
  let timeZone: TimeZone
  let locale = Locale(identifier: "en_US_POSIX")

  init() throws {
    context = ModelContext(try TendModelContainer.inMemory())
    timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    calendar.timeZone = timeZone
    self.calendar = calendar
    now = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 8))
    )
  }

  func insertHabit(
    id: Int,
    name: String,
    reminderMinuteOfDay: Int
  ) throws -> Habit {
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(
        name: name,
        target: 1,
        reminderTime: ReminderTime(rawValue: reminderMinuteOfDay)
      ),
      cadence: .daily,
      at: now,
      timeZone: timeZone
    )
    habit.id = UUID(
      uuidString: String(format: "00000000-0000-0000-0000-%012d", id)
    )!
    try context.save()
    return habit
  }

  func makeCoordinator(
    center: FakeReminderNotificationCenter,
    limit: Int,
    currentBucketFacts: ReminderCurrentBucketFactsProvider? = nil
  ) -> ReminderCoordinator {
    ReminderCoordinator(
      context: context,
      notificationCenter: center,
      now: { now },
      calendar: calendar,
      timeZone: timeZone,
      locale: locale,
      requestLimit: limit,
      currentBucketFacts: currentBucketFacts
    )
  }

  func plan(for habits: [Habit], limit: Int) -> [ReminderOccurrence] {
    ReminderPlanner(
      calendar: calendar,
      timeZone: timeZone,
      locale: locale
    ).plan(
      habits: habits.map(facts(for:)),
      at: now,
      limit: limit
    )
  }

  private func facts(for habit: Habit) -> ReminderHabitFacts {
    ReminderHabitFacts(
      id: habit.id,
      name: habit.name,
      cadenceRawValue: habit.cadenceRawValue,
      target: habit.target,
      unit: habit.unit,
      pinnedWeekdaysRawValue: habit.pinnedWeekdaysRawValue,
      reminderMinuteOfDay: habit.reminderMinuteOfDay,
      isActive: habit.isActive,
      currentBucket: currentFacts(for: habit)
    )
  }

  func currentFacts(for habit: Habit) -> ReminderCurrentBucketFacts {
    ReminderCurrentBucketFacts(
      periodKey: habit.cadenceRawValue == HabitCadence.weekly.rawValue
        ? "week:2026-01-05"
        : "day:2026-01-05",
      progress: 0,
      target: habit.target,
      unit: habit.unit,
      isMet: false
    )
  }
}

@MainActor
private final class FakeReminderNotificationCenter: ReminderNotificationCenterClient {
  private(set) var authorizationStatusCallCount = 0
  private(set) var requestAuthorizationCallCount = 0
  private(set) var removedIdentifiers: [String] = []
  private(set) var addedOccurrences: [ReminderOccurrence] = []
  private(set) var addAttemptIdentifiers: [String] = []
  private(set) var maximumConcurrentOperations = 0

  var pendingRequests: [ReminderPendingRequest]
  var failingRemoveIdentifiers: Set<String> = []
  var pendingRequestsError: (any Error)?
  var failingAddIdentifiers: Set<String> = []
  var pauseFirstAuthorizationRead = false

  var stubbedAuthorizationStatus: ReminderAuthorizationStatus
  private var activeOperationCount = 0
  private var authorizationContinuation: CheckedContinuation<Void, Never>?

  init(
    authorizationStatus: ReminderAuthorizationStatus,
    pendingRequests: [ReminderPendingRequest] = []
  ) {
    stubbedAuthorizationStatus = authorizationStatus
    self.pendingRequests = pendingRequests
  }

  func authorizationStatus() async throws -> ReminderAuthorizationStatus {
    beginOperation()
    defer { endOperation() }
    authorizationStatusCallCount += 1
    let sampledStatus = stubbedAuthorizationStatus
    if pauseFirstAuthorizationRead, authorizationStatusCallCount == 1 {
      await withCheckedContinuation { continuation in
        authorizationContinuation = continuation
      }
    }
    return sampledStatus
  }

  func requestAuthorization() async throws -> Bool {
    requestAuthorizationCallCount += 1
    return true
  }

  func tendPendingRequests() async throws -> [ReminderPendingRequest] {
    beginOperation()
    defer { endOperation() }
    if let pendingRequestsError {
      throw pendingRequestsError
    }
    return pendingRequests
  }

  func removePendingRequest(withIdentifier identifier: String) async throws {
    beginOperation()
    defer { endOperation() }
    removedIdentifiers.append(identifier)
    if failingRemoveIdentifiers.contains(identifier) {
      throw TestFailure.expected
    }
    pendingRequests.removeAll { $0.identifier == identifier }
  }

  func addOrReplace(_ occurrence: ReminderOccurrence) async throws {
    beginOperation()
    defer { endOperation() }
    addAttemptIdentifiers.append(occurrence.identifier)
    if failingAddIdentifiers.contains(occurrence.identifier) {
      throw TestFailure.expected
    }
    addedOccurrences.append(occurrence)
    pendingRequests.removeAll { $0.identifier == occurrence.identifier }
    pendingRequests.append(ReminderPendingRequest(occurrence: occurrence))
  }

  func resetRecordedMutations() {
    removedIdentifiers = []
    addedOccurrences = []
    addAttemptIdentifiers = []
  }

  func waitUntilAuthorizationReadPauses() async {
    while authorizationContinuation == nil {
      await Task.yield()
    }
  }

  func resumeAuthorizationRead() {
    authorizationContinuation?.resume()
    authorizationContinuation = nil
  }

  private func beginOperation() {
    activeOperationCount += 1
    maximumConcurrentOperations = max(maximumConcurrentOperations, activeOperationCount)
  }

  private func endOperation() {
    activeOperationCount -= 1
  }
}

@MainActor
private final class RefreshCallerGate {
  private let expectedCount: Int
  private var enteredCount = 0
  private var allEnteredContinuation: CheckedContinuation<Void, Never>?

  init(expectedCount: Int) {
    self.expectedCount = expectedCount
  }

  func enter() {
    enteredCount += 1
    guard enteredCount == expectedCount else { return }
    allEnteredContinuation?.resume()
    allEnteredContinuation = nil
  }

  func waitUntilAllEntered() async {
    guard enteredCount < expectedCount else { return }
    await withCheckedContinuation { continuation in
      allEnteredContinuation = continuation
    }
  }
}

private enum TestFailure: Error {
  case expected
}
