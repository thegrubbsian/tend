import Foundation
import Observation
import SwiftData
import TendCore

struct TodayRefreshContext: Equatable {
  let instant: Date
  let timeZone: TimeZone
  let calendar: Calendar
  let locale: Locale
}

struct TodayHabitFacts: Equatable, Sendable {
  let snapshot: HabitTodaySnapshot
  let visualProgressFraction: Double
}

struct TodayHabitFailure: Equatable, Sendable {
  let message: String
  let retryTitle: String
}

struct TodayHabitRow: Identifiable {
  let id: PersistentIdentifier
  let habit: Habit
  let name: String
  let createdAt: Date
  let requirementText: String
  let progressText: String
  let streakText: String
  let riskText: String?
  let facts: TodayHabitFacts?
  let failure: TodayHabitFailure?
  let accessibilityLabel: String
  let accessibilityValue: String

  var isMet: Bool {
    facts?.snapshot.isMet == true
  }

  var isAvailable: Bool {
    facts != nil
  }
}

struct TodayDashboardPresentation {
  let toTendRows: [TodayHabitRow]
  let tendedRows: [TodayHabitRow]
  let metCount: Int
  let activeCount: Int
  let fractionText: String
  let showsAllTended: Bool
}

enum TodayPresentation {
  case firstLaunch
  case inactiveOnly
  case dashboard(TodayDashboardPresentation)
}

@MainActor
struct TodayOperations {
  typealias Snapshot = (
    _ habit: Habit,
    _ context: TodayRefreshContext
  ) throws -> HabitTodaySnapshot

  let snapshot: Snapshot

  init(snapshot: @escaping Snapshot) {
    self.snapshot = snapshot
  }

  static func live(context: ModelContext) -> Self {
    let computation = HabitTodayComputation(context: context)
    return Self { habit, refreshContext in
      try computation.snapshot(
        for: habit,
        at: refreshContext.instant,
        timeZone: refreshContext.timeZone
      )
    }
  }
}

@MainActor
@Observable
final class TodayModel {
  private(set) var presentation: TodayPresentation?

  @ObservationIgnored private let operations: TodayOperations
  @ObservationIgnored private var lastInputs: [PersistentIdentifier: InputFingerprint] = [:]

  init(context: ModelContext) {
    operations = .live(context: context)
  }

  init(operations: TodayOperations) {
    self.operations = operations
  }

  func refresh(
    habits: [Habit],
    context: TodayRefreshContext
  ) {
    let inputs = uniqueInputs(from: habits)
    let activeInputs = inputs.filter { $0.habit.isActive }
    let replacement: TodayPresentation
    let replacementInputs: [PersistentIdentifier: InputFingerprint]

    if inputs.isEmpty {
      replacement = .firstLaunch
      replacementInputs = [:]
    } else if activeInputs.isEmpty {
      replacement = .inactiveOnly
      replacementInputs = [:]
    } else {
      let formatter = TodayPresentationFormatter(context: context)
      var rows: [TodayHabitRow] = []
      rows.reserveCapacity(activeInputs.count)
      for input in activeInputs {
        rows.append(project(input, formatter: formatter, context: context))
      }
      replacement = .dashboard(
        dashboard(rows: rows, formatter: formatter)
      )
      replacementInputs = fingerprints(for: activeInputs)
    }

    lastInputs = replacementInputs
    presentation = replacement
  }

  func retry(
    habitID: PersistentIdentifier,
    habits: [Habit],
    context: TodayRefreshContext
  ) {
    guard case .dashboard(let current)? = presentation,
      (current.toTendRows + current.tendedRows).contains(where: {
        $0.id == habitID && $0.failure != nil
      })
    else {
      return
    }

    let inputs = uniqueInputs(from: habits)
    let activeInputs = inputs.filter { $0.habit.isActive }
    let currentInputs = fingerprints(for: activeInputs)
    guard currentInputs == lastInputs,
      let retryInput = activeInputs.first(where: { $0.id == habitID })
    else {
      refresh(habits: habits, context: context)
      return
    }

    let formatter = TodayPresentationFormatter(context: context)
    let replacement: TodayHabitRow
    do {
      let snapshot = try operations.snapshot(retryInput.habit, context)
      replacement = try formatter.availableRow(
        for: retryInput.habit,
        id: retryInput.id,
        snapshot: snapshot
      )
    } catch {
      return
    }

    var rows = current.toTendRows + current.tendedRows
    guard let replacementIndex = rows.firstIndex(where: { $0.id == habitID }) else {
      refresh(habits: habits, context: context)
      return
    }
    rows[replacementIndex] = replacement
    presentation = .dashboard(
      dashboard(rows: rows, formatter: formatter)
    )
  }

  private func project(
    _ input: Input,
    formatter: TodayPresentationFormatter,
    context: TodayRefreshContext
  ) -> TodayHabitRow {
    do {
      let snapshot = try operations.snapshot(input.habit, context)
      return try formatter.availableRow(
        for: input.habit,
        id: input.id,
        snapshot: snapshot
      )
    } catch {
      return formatter.unavailableRow(
        for: input.habit,
        id: input.id,
        error: error
      )
    }
  }

  private func dashboard(
    rows: [TodayHabitRow],
    formatter: TodayPresentationFormatter
  ) -> TodayDashboardPresentation {
    var toTendRows: [TodayHabitRow] = []
    var tendedRows: [TodayHabitRow] = []
    toTendRows.reserveCapacity(rows.count)
    tendedRows.reserveCapacity(rows.count)
    for row in rows {
      if row.isMet {
        tendedRows.append(row)
      } else {
        toTendRows.append(row)
      }
    }
    toTendRows.sort(by: formatter.isOrdered)
    tendedRows.sort(by: formatter.isOrdered)

    let metCount = tendedRows.count
    let activeCount = rows.count
    return TodayDashboardPresentation(
      toTendRows: toTendRows,
      tendedRows: tendedRows,
      metCount: metCount,
      activeCount: activeCount,
      fractionText: formatter.fraction(met: metCount, active: activeCount),
      showsAllTended: activeCount > 0 && metCount == activeCount
    )
  }

  private func uniqueInputs(from habits: [Habit]) -> [Input] {
    var seen: Set<PersistentIdentifier> = []
    var inputs: [Input] = []
    inputs.reserveCapacity(habits.count)
    for habit in habits {
      let id = habit.persistentModelID
      guard seen.insert(id).inserted else { continue }
      inputs.append(
        Input(
          id: id,
          habit: habit
        ))
    }
    return inputs
  }

  private func fingerprints(
    for inputs: [Input]
  ) -> [PersistentIdentifier: InputFingerprint] {
    Dictionary(
      uniqueKeysWithValues: inputs.map {
        ($0.id, InputFingerprint(habit: $0.habit))
      })
  }
}

extension TodayModel {
  private struct Input {
    let id: PersistentIdentifier
    let habit: Habit
  }

  private struct InputFingerprint: Equatable {
    let objectIdentifier: ObjectIdentifier
    let publicID: UUID
    let name: String
    let cadenceRawValue: String
    let target: Int
    let unit: String
    let pinnedWeekdaysRawValue: Int
    let reminderMinuteOfDay: Int?
    let isActive: Bool
    let createdAt: Date
    let bestStreak: Int
    let activityPeriods: [ActivityPeriodFingerprint]
    let buckets: [BucketFingerprint]
    let entries: [EntryFingerprint]

    init(habit: Habit) {
      objectIdentifier = ObjectIdentifier(habit)
      publicID = habit.id
      name = habit.name
      cadenceRawValue = habit.cadenceRawValue
      target = habit.target
      unit = habit.unit
      pinnedWeekdaysRawValue = habit.pinnedWeekdaysRawValue
      reminderMinuteOfDay = habit.reminderMinuteOfDay
      isActive = habit.isActive
      createdAt = habit.createdAt
      bestStreak = habit.bestStreak
      activityPeriods = (habit.activityPeriods ?? [])
        .map(ActivityPeriodFingerprint.init)
        .sorted { $0.id < $1.id }
      buckets = (habit.buckets ?? [])
        .map(BucketFingerprint.init)
        .sorted { $0.id < $1.id }
      entries = (habit.entries ?? [])
        .map(EntryFingerprint.init)
        .sorted { $0.id < $1.id }
    }
  }

  private struct ActivityPeriodFingerprint: Equatable {
    let id: PersistentIdentifier
    let publicID: UUID
    let startedAt: Date
    let endedAt: Date?
    let habitID: PersistentIdentifier?

    init(_ period: HabitActivityPeriod) {
      id = period.persistentModelID
      publicID = period.id
      startedAt = period.startedAt
      endedAt = period.endedAt
      habitID = period.habit?.persistentModelID
    }
  }

  private struct BucketFingerprint: Equatable {
    let id: PersistentIdentifier
    let publicID: UUID
    let periodKey: String
    let startAt: Date
    let endAt: Date
    let cadenceRawValue: String
    let isExempt: Bool
    let finalizedAt: Date?
    let verdictRawValue: String?
    let targetSnapshot: Int?
    let unitSnapshot: String?
    let habitID: PersistentIdentifier?
    let entryIDs: [PersistentIdentifier]

    init(_ bucket: HabitBucket) {
      id = bucket.persistentModelID
      publicID = bucket.id
      periodKey = bucket.periodKey
      startAt = bucket.startAt
      endAt = bucket.endAt
      cadenceRawValue = bucket.cadenceRawValue
      isExempt = bucket.isExempt
      finalizedAt = bucket.finalizedAt
      verdictRawValue = bucket.verdictRawValue
      targetSnapshot = bucket.targetSnapshot
      unitSnapshot = bucket.unitSnapshot
      habitID = bucket.habit?.persistentModelID
      entryIDs = (bucket.entries ?? []).map(\.persistentModelID).sorted()
    }
  }

  private struct EntryFingerprint: Equatable {
    let id: PersistentIdentifier
    let publicID: UUID
    let timestamp: Date
    let amount: Int
    let habitID: PersistentIdentifier?
    let bucketID: PersistentIdentifier?

    init(_ entry: LogEntry) {
      id = entry.persistentModelID
      publicID = entry.id
      timestamp = entry.timestamp
      amount = entry.amount
      habitID = entry.habit?.persistentModelID
      bucketID = entry.bucket?.persistentModelID
    }
  }
}
