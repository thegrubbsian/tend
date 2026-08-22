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

  var isMet: Bool { facts?.snapshot.isMet == true }
  var isAvailable: Bool { facts != nil }
}

struct TodayGoalFacts: Equatable, Sendable {
  let progress: GoalProgressSnapshot
  let standing: GoalStandingSnapshot
  let deadline: LocalDate?
}

enum TodayGoalProjection: Equatable, Sendable {
  case closed(GoalClosure)
  case open(TodayGoalFacts)
}

struct TodayGoalFailure: Equatable, Sendable {
  let message: String
  let retryTitle: String
}
struct TodayJournalFailure: Equatable, Sendable {
  let message: String
  let retryTitle: String
}

enum TodayJournalInvitation: Equatable, Sendable {
  case invitation(day: LocalDate)
  case complete
  case unavailable(TodayJournalFailure)
}

struct TodayGoalRow: Identifiable {
  let id: PersistentIdentifier
  let goal: Goal
  let name: String
  let createdAt: Date
  let deadline: LocalDate?
  let facts: TodayGoalFacts?
  let failure: TodayGoalFailure?
  let progress: GoalDetailProgressFact?
  let progressText: String
  let normalizedProgress: Double?
  let expectedNormalizedProgress: Double?
  let deadlineText: String
  let standingText: String
  let accessibilityLabel: String
  let accessibilityValue: String

  var nextTransition: Date? { facts?.standing.nextTimeRefresh }
  var isAvailable: Bool { facts != nil }
}

struct TodayDashboardPresentation {
  let toTendRows: [TodayHabitRow]
  let tendedRows: [TodayHabitRow]
  let goalRows: [TodayGoalRow]
  let nextGoalTransition: Date?
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
  typealias GoalFacts = (
    _ goal: Goal,
    _ context: TodayRefreshContext
  ) throws -> TodayGoalProjection
  typealias JournalEntryExists = (
    _ day: LocalDate,
    _ context: TodayRefreshContext
  ) throws -> Bool

  let snapshot: Snapshot
  let goalFacts: GoalFacts
  let journalEntryExists: JournalEntryExists

  init(
    snapshot: @escaping Snapshot,
    goalFacts: @escaping GoalFacts = { _, _ in
      throw TodayOperationsError.goalProjectionUnavailable
    },
    journalEntryExists: @escaping JournalEntryExists = { _, _ in false }
  ) {
    self.snapshot = snapshot
    self.goalFacts = goalFacts
    self.journalEntryExists = journalEntryExists
  }

  static func live(context: ModelContext) -> Self {
    let habitComputation = HabitTodayComputation(context: context)
    let progressComputation = GoalProgressComputation(context: context)
    let standingComputation = GoalStandingComputation()
    let journalQuery = JournalEntryQuery(context: context)
    return Self(
      snapshot: { habit, refreshContext in
        try habitComputation.snapshot(
          for: habit,
          at: refreshContext.instant,
          timeZone: refreshContext.timeZone
        )
      },
      goalFacts: { goal, refreshContext in
        if let closure = try goal.checkedClosure {
          return .closed(closure)
        }
        let deadline: LocalDate?
        if let key = goal.deadlineKey {
          guard let parsed = LocalDate(rawValue: key) else {
            throw TodayOperationsError.invalidGoalDeadline(key)
          }
          deadline = parsed
        } else {
          deadline = nil
        }
        let progress = try progressComputation.snapshot(for: goal)
        guard
          let standing = try standingComputation.snapshot(
            for: goal,
            progress: progress,
            at: refreshContext.instant,
            calendar: refreshContext.calendar,
            timeZone: refreshContext.timeZone
          )
        else {
          throw TodayOperationsError.inconsistentGoalLifecycle
        }
        return .open(
          TodayGoalFacts(
            progress: progress,
            standing: standing,
            deadline: deadline
          ))
      },
      journalEntryExists: { day, _ in
        try journalQuery.entry(on: day) != nil
      }
    )
  }
}

private enum TodayOperationsError: Error {
  case goalProjectionUnavailable
  case invalidGoalDeadline(String)
  case inconsistentGoalLifecycle
}

@MainActor
@Observable
final class TodayModel {
  @ObservationIgnored private let operations: TodayOperations
  private var generation: Generation?
  @ObservationIgnored private var lastHabitInputs: [PersistentIdentifier: HabitInputFingerprint] =
    [:]
  @ObservationIgnored private var lastGoalInputs: [PersistentIdentifier: GoalInputFingerprint] = [:]
  @ObservationIgnored private var lastJournalInputs:
    [PersistentIdentifier: JournalInputFingerprint] = [:]
  @ObservationIgnored private var retainedGoals: [Goal] = []
  @ObservationIgnored private var retainedJournalEntries: [JournalEntry] = []
  @ObservationIgnored private var generationContext: TodayRefreshContext?

  var presentation: TodayPresentation? { generation?.presentation }
  var goalRows: [TodayGoalRow] { generation?.goalRows ?? [] }
  var nextGoalTransition: Date? { generation?.nextGoalTransition }
  var journalInvitation: TodayJournalInvitation? { generation?.journalInvitation }

  init(context: ModelContext) {
    operations = .live(context: context)
  }

  init(operations: TodayOperations) {
    self.operations = operations
  }

  func refresh(
    habits: [Habit],
    goals: [Goal],
    journalEntries: [JournalEntry],
    context: TodayRefreshContext
  ) {
    let goalInputs = uniqueGoalInputs(from: goals)
    let journalInputs = uniqueJournalInputs(from: journalEntries)
    retainedGoals = goalInputs.map(\.goal)
    retainedJournalEntries = journalInputs.map(\.entry)
    refresh(
      habits: habits,
      goalInputs: goalInputs,
      journalInputs: journalInputs,
      context: context
    )
  }

  func refresh(
    habits: [Habit],
    context: TodayRefreshContext
  ) {
    refresh(
      habits: habits,
      goalInputs: uniqueGoalInputs(from: retainedGoals),
      journalInputs: uniqueJournalInputs(from: retainedJournalEntries),
      context: context
    )
  }

  private func refresh(
    habits: [Habit],
    goalInputs: [GoalInput],
    journalInputs: [JournalInput],
    context: TodayRefreshContext
  ) {
    let habitInputs = uniqueHabitInputs(from: habits)
    let activeHabitInputs = habitInputs.filter { $0.habit.isActive }
    let formatter = TodayPresentationFormatter(context: context)
    let goalProjection = projectGoals(goalInputs, formatter: formatter, context: context)
    let journalInvitation = projectJournal(context: context)

    let replacementPresentation: TodayPresentation
    if habitInputs.isEmpty {
      replacementPresentation = .firstLaunch
    } else if activeHabitInputs.isEmpty {
      replacementPresentation = .inactiveOnly
    } else {
      var habitRows: [TodayHabitRow] = []
      habitRows.reserveCapacity(activeHabitInputs.count)
      for input in activeHabitInputs {
        habitRows.append(projectHabit(input, formatter: formatter, context: context))
      }
      replacementPresentation = .dashboard(
        dashboard(
          habitRows: habitRows,
          goalRows: goalProjection.rows,
          nextGoalTransition: goalProjection.nextTransition,
          formatter: formatter
        ))
    }

    let replacement = Generation(
      presentation: replacementPresentation,
      goalRows: goalProjection.rows,
      nextGoalTransition: goalProjection.nextTransition,
      journalInvitation: journalInvitation
    )
    lastHabitInputs = habitFingerprints(for: habitInputs)
    lastGoalInputs = goalFingerprints(for: goalInputs)
    lastJournalInputs = journalFingerprints(for: journalInputs)
    generationContext = context
    generation = replacement
  }

  func retry(
    habitID: PersistentIdentifier,
    habits: [Habit],
    journalEntries: [JournalEntry],
    context: TodayRefreshContext
  ) {
    guard case .dashboard(let current)? = presentation,
      (current.toTendRows + current.tendedRows).contains(where: {
        $0.id == habitID && $0.failure != nil
      })
    else { return }

    let habitInputs = uniqueHabitInputs(from: habits)
    let activeHabitInputs = habitInputs.filter { $0.habit.isActive }
    let goalInputs = uniqueGoalInputs(from: retainedGoals)
    let journalInputs = uniqueJournalInputs(from: journalEntries)
    guard habitFingerprints(for: habitInputs) == lastHabitInputs,
      generationContext == context,
      goalFingerprints(for: goalInputs) == lastGoalInputs,
      journalFingerprints(for: journalInputs) == lastJournalInputs,
      let journalInvitation = generation?.journalInvitation,
      let retryInput = activeHabitInputs.first(where: { $0.id == habitID })
    else {
      refresh(
        habits: habits,
        goals: retainedGoals,
        journalEntries: journalEntries,
        context: context
      )
      return
    }

    let formatter = TodayPresentationFormatter(context: context)
    let replacement: TodayHabitRow
    do {
      replacement = try formatter.availableRow(
        for: retryInput.habit,
        id: retryInput.id,
        snapshot: operations.snapshot(retryInput.habit, context)
      )
    } catch {
      return
    }

    var rows = current.toTendRows + current.tendedRows
    guard let index = rows.firstIndex(where: { $0.id == habitID }) else {
      refresh(
        habits: habits,
        goals: retainedGoals,
        journalEntries: journalEntries,
        context: context
      )
      return
    }
    rows[index] = replacement
    let dashboard = dashboard(
      habitRows: rows,
      goalRows: current.goalRows,
      nextGoalTransition: current.nextGoalTransition,
      formatter: formatter
    )
    generation = Generation(
      presentation: .dashboard(dashboard),
      goalRows: current.goalRows,
      nextGoalTransition: current.nextGoalTransition,
      journalInvitation: journalInvitation
    )
  }

  func retry(
    goalID: PersistentIdentifier,
    habits: [Habit],
    goals: [Goal],
    journalEntries: [JournalEntry],
    context: TodayRefreshContext
  ) {
    guard goalRows.contains(where: { $0.id == goalID && $0.failure != nil }) else {
      return
    }
    let habitInputs = uniqueHabitInputs(from: habits)
    let goalInputs = uniqueGoalInputs(from: goals)
    let journalInputs = uniqueJournalInputs(from: journalEntries)
    guard habitFingerprints(for: habitInputs) == lastHabitInputs,
      generationContext == context,
      goalFingerprints(for: goalInputs) == lastGoalInputs,
      journalFingerprints(for: journalInputs) == lastJournalInputs,
      let journalInvitation = generation?.journalInvitation,
      let retryInput = goalInputs.first(where: { $0.id == goalID })
    else {
      refresh(
        habits: habits,
        goals: goals,
        journalEntries: journalEntries,
        context: context
      )
      return
    }

    let formatter = TodayPresentationFormatter(context: context)
    let projection: TodayGoalProjection
    do {
      projection = try operations.goalFacts(retryInput.goal, context)
    } catch {
      return
    }
    guard case .open(let facts) = projection else {
      refresh(
        habits: habits,
        goals: goals,
        journalEntries: journalEntries,
        context: context
      )
      return
    }
    let replacement: TodayGoalRow
    do {
      replacement = try formatter.availableGoalRow(
        for: retryInput.goal,
        id: retryInput.id,
        facts: facts
      )
    } catch {
      return
    }
    guard isEligible(facts, context: context) else {
      refresh(
        habits: habits,
        goals: goals,
        journalEntries: journalEntries,
        context: context
      )
      return
    }

    var rows = goalRows
    guard let index = rows.firstIndex(where: { $0.id == goalID }) else {
      refresh(
        habits: habits,
        goals: goals,
        journalEntries: journalEntries,
        context: context
      )
      return
    }
    rows[index] = replacement
    rows.sort(by: formatter.areGoalsOrdered)
    let transition = [
      generation?.nextGoalTransition,
      earliestFutureTransition(in: rows, after: context.instant),
    ]
    .compactMap { $0 }
    .filter { $0 > context.instant }
    .min()
    let replacementPresentation: TodayPresentation
    switch presentation {
    case .dashboard(let current):
      replacementPresentation = .dashboard(
        dashboard(
          habitRows: current.toTendRows + current.tendedRows,
          goalRows: rows,
          nextGoalTransition: transition,
          formatter: formatter
        ))
    case .firstLaunch:
      replacementPresentation = .firstLaunch
    case .inactiveOnly:
      replacementPresentation = .inactiveOnly
    case nil:
      return
    }
    generation = Generation(
      presentation: replacementPresentation,
      goalRows: rows,
      nextGoalTransition: transition,
      journalInvitation: journalInvitation
    )
  }

  func retryJournal(
    habits: [Habit],
    goals: [Goal],
    journalEntries: [JournalEntry],
    context: TodayRefreshContext
  ) {
    guard case .unavailable? = journalInvitation, let current = generation else {
      return
    }
    let habitInputs = uniqueHabitInputs(from: habits)
    let goalInputs = uniqueGoalInputs(from: goals)
    let journalInputs = uniqueJournalInputs(from: journalEntries)
    guard habitFingerprints(for: habitInputs) == lastHabitInputs,
      goalFingerprints(for: goalInputs) == lastGoalInputs,
      journalFingerprints(for: journalInputs) == lastJournalInputs,
      let generationContext,
      matchesJournalRetryContext(generationContext, context)
    else {
      refresh(
        habits: habits,
        goals: goals,
        journalEntries: journalEntries,
        context: context
      )
      return
    }

    let replacement = projectJournal(context: context)
    guard case .unavailable = replacement else {
      generation = Generation(
        presentation: current.presentation,
        goalRows: current.goalRows,
        nextGoalTransition: current.nextGoalTransition,
        journalInvitation: replacement
      )
      return
    }
  }

  private func projectHabit(
    _ input: HabitInput,
    formatter: TodayPresentationFormatter,
    context: TodayRefreshContext
  ) -> TodayHabitRow {
    do {
      return try formatter.availableRow(
        for: input.habit,
        id: input.id,
        snapshot: operations.snapshot(input.habit, context)
      )
    } catch {
      return formatter.unavailableRow(for: input.habit, id: input.id, error: error)
    }
  }

  private func projectJournal(context: TodayRefreshContext) -> TodayJournalInvitation {
    guard let day = localLocalDate(at: context.instant, timeZone: context.timeZone) else {
      return unavailableJournal()
    }
    do {
      return try operations.journalEntryExists(day, context)
        ? .complete
        : .invitation(day: day)
    } catch {
      return unavailableJournal()
    }
  }

  private func unavailableJournal() -> TodayJournalInvitation {
    .unavailable(
      TodayJournalFailure(
        message: "Journal is unavailable right now.",
        retryTitle: "Try again"
      )
    )
  }

  private func projectGoals(
    _ inputs: [GoalInput],
    formatter: TodayPresentationFormatter,
    context: TodayRefreshContext
  ) -> GoalProjectionResult {
    var rows: [TodayGoalRow] = []
    rows.reserveCapacity(inputs.count)
    var nextTransition: Date?

    for input in inputs {
      do {
        switch try operations.goalFacts(input.goal, context) {
        case .closed:
          continue
        case .open(let facts):
          let row = try formatter.availableGoalRow(
            for: input.goal,
            id: input.id,
            facts: facts
          )
          if let candidate = row.nextTransition,
            candidate > context.instant,
            nextTransition.map({ candidate < $0 }) ?? true
          {
            nextTransition = candidate
          }
          guard isEligible(facts, context: context) else { continue }
          rows.append(row)
        }
      } catch {
        rows.append(formatter.unavailableGoalRow(for: input.goal, id: input.id, error: error))
      }
    }
    rows.sort(by: formatter.areGoalsOrdered)
    return GoalProjectionResult(rows: rows, nextTransition: nextTransition)
  }

  private func isEligible(
    _ facts: TodayGoalFacts,
    context: TodayRefreshContext
  ) -> Bool {
    switch facts.standing.standing {
    case .behind, .pastDue:
      return true
    case .onPace:
      guard let deadline = facts.deadline,
        var candidate = localLocalDate(
          at: context.instant,
          timeZone: context.timeZone
        )
      else { return false }
      for offset in 0...7 {
        if deadline == candidate { return true }
        guard offset < 7, let next = try? candidate.next() else { return false }
        candidate = next
      }
      return false
    }
  }

  private func localLocalDate(
    at instant: Date,
    timeZone: TimeZone
  ) -> LocalDate? {
    var ownerCalendar = Calendar(identifier: .gregorian)
    ownerCalendar.timeZone = timeZone
    let components = ownerCalendar.dateComponents([.year, .month, .day], from: instant)
    guard
      let year = components.year,
      let month = components.month,
      let day = components.day
    else { return nil }
    return LocalDate(year: year, month: month, day: day)
  }

  private func matchesJournalRetryContext(
    _ previous: TodayRefreshContext,
    _ current: TodayRefreshContext
  ) -> Bool {
    previous.timeZone == current.timeZone
      && previous.calendar == current.calendar
      && previous.locale == current.locale
      && localLocalDate(at: previous.instant, timeZone: previous.timeZone)
        == localLocalDate(at: current.instant, timeZone: current.timeZone)
  }

  private func dashboard(
    habitRows: [TodayHabitRow],
    goalRows: [TodayGoalRow],
    nextGoalTransition: Date?,
    formatter: TodayPresentationFormatter
  ) -> TodayDashboardPresentation {
    var toTendRows: [TodayHabitRow] = []
    var tendedRows: [TodayHabitRow] = []
    toTendRows.reserveCapacity(habitRows.count)
    tendedRows.reserveCapacity(habitRows.count)
    for row in habitRows {
      if row.isMet { tendedRows.append(row) } else { toTendRows.append(row) }
    }
    toTendRows.sort(by: formatter.isOrdered)
    tendedRows.sort(by: formatter.isOrdered)
    let metCount = tendedRows.count
    let activeCount = habitRows.count
    return TodayDashboardPresentation(
      toTendRows: toTendRows,
      tendedRows: tendedRows,
      goalRows: goalRows,
      nextGoalTransition: nextGoalTransition,
      metCount: metCount,
      activeCount: activeCount,
      fractionText: formatter.fraction(met: metCount, active: activeCount),
      showsAllTended: activeCount > 0 && metCount == activeCount && goalRows.isEmpty
    )
  }

  private func earliestFutureTransition(
    in rows: [TodayGoalRow],
    after instant: Date
  ) -> Date? {
    rows.compactMap(\.nextTransition).filter { $0 > instant }.min()
  }

  private func uniqueHabitInputs(from habits: [Habit]) -> [HabitInput] {
    var seen: Set<PersistentIdentifier> = []
    var inputs: [HabitInput] = []
    inputs.reserveCapacity(habits.count)
    for habit in habits {
      let id = habit.persistentModelID
      guard seen.insert(id).inserted else { continue }
      inputs.append(HabitInput(id: id, habit: habit))
    }
    return inputs
  }

  private func uniqueGoalInputs(from goals: [Goal]) -> [GoalInput] {
    var seen: Set<PersistentIdentifier> = []
    var inputs: [GoalInput] = []
    inputs.reserveCapacity(goals.count)
    for goal in goals {
      let id = goal.persistentModelID
      guard seen.insert(id).inserted else { continue }
      inputs.append(GoalInput(id: id, goal: goal))
    }
    return inputs
  }

  private func uniqueJournalInputs(from entries: [JournalEntry]) -> [JournalInput] {
    var seen: Set<PersistentIdentifier> = []
    var inputs: [JournalInput] = []
    inputs.reserveCapacity(entries.count)
    for entry in entries {
      let id = entry.persistentModelID
      guard seen.insert(id).inserted else { continue }
      inputs.append(JournalInput(id: id, entry: entry))
    }
    return inputs
  }

  private func habitFingerprints(
    for inputs: [HabitInput]
  ) -> [PersistentIdentifier: HabitInputFingerprint] {
    Dictionary(uniqueKeysWithValues: inputs.map { ($0.id, HabitInputFingerprint(habit: $0.habit)) })
  }

  private func goalFingerprints(
    for inputs: [GoalInput]
  ) -> [PersistentIdentifier: GoalInputFingerprint] {
    Dictionary(uniqueKeysWithValues: inputs.map { ($0.id, GoalInputFingerprint(goal: $0.goal)) })
  }

  private func journalFingerprints(
    for inputs: [JournalInput]
  ) -> [PersistentIdentifier: JournalInputFingerprint] {
    Dictionary(
      uniqueKeysWithValues: inputs.map {
        ($0.id, JournalInputFingerprint(entry: $0.entry))
      }
    )
  }
}

extension TodayModel {
  private struct Generation {
    let presentation: TodayPresentation
    let goalRows: [TodayGoalRow]
    let nextGoalTransition: Date?
    let journalInvitation: TodayJournalInvitation
  }

  private struct GoalProjectionResult {
    let rows: [TodayGoalRow]
    let nextTransition: Date?
  }

  private struct HabitInput {
    let id: PersistentIdentifier
    let habit: Habit
  }

  private struct GoalInput {
    let id: PersistentIdentifier
    let goal: Goal
  }

  private struct JournalInput {
    let id: PersistentIdentifier
    let entry: JournalEntry
  }

  private struct JournalInputFingerprint: Equatable {
    let objectIdentifier: ObjectIdentifier
    let publicID: UUID
    let dayKey: String

    init(entry: JournalEntry) {
      objectIdentifier = ObjectIdentifier(entry)
      publicID = entry.id
      dayKey = entry.dayKey
    }
  }

  private struct HabitInputFingerprint: Equatable {
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
      activityPeriods = (habit.activityPeriods ?? []).map(ActivityPeriodFingerprint.init).sorted {
        $0.id < $1.id
      }
      buckets = (habit.buckets ?? []).map(BucketFingerprint.init).sorted { $0.id < $1.id }
      entries = (habit.entries ?? []).map(EntryFingerprint.init).sorted { $0.id < $1.id }
    }
  }

  private struct GoalInputFingerprint: Equatable {
    let objectIdentifier: ObjectIdentifier
    let publicID: UUID
    let name: String
    let kindRawValue: String
    let target: Int
    let unit: String
    let baseline: Int?
    let deadlineKey: String?
    let createdAt: Date
    let closureRawValue: String?
    let hasEntriesRelationship: Bool
    let hasReadingsRelationship: Bool
    let entries: [GoalEntryFingerprint]
    let readings: [GoalReadingFingerprint]

    init(goal: Goal) {
      objectIdentifier = ObjectIdentifier(goal)
      publicID = goal.id
      name = goal.name
      kindRawValue = goal.kindRawValue
      target = goal.target
      unit = goal.unit
      baseline = goal.baseline
      deadlineKey = goal.deadlineKey
      createdAt = goal.createdAt
      closureRawValue = goal.closureRawValue
      hasEntriesRelationship = goal.entries != nil
      hasReadingsRelationship = goal.readings != nil
      entries = (goal.entries ?? []).map(GoalEntryFingerprint.init).sorted { $0.id < $1.id }
      readings = (goal.readings ?? []).map(GoalReadingFingerprint.init).sorted { $0.id < $1.id }
    }
  }

  private struct GoalEntryFingerprint: Equatable {
    let id: PersistentIdentifier
    let publicID: UUID
    let amount: Int
    let assignedDateKey: String
    let appendedAt: Date
    let appendSequence: Int
    let goalID: PersistentIdentifier?

    init(_ entry: GoalEntry) {
      id = entry.persistentModelID
      publicID = entry.id
      amount = entry.amount
      assignedDateKey = entry.assignedDateKey
      appendedAt = entry.appendedAt
      appendSequence = entry.appendSequence
      goalID = entry.goal?.persistentModelID
    }
  }

  private struct GoalReadingFingerprint: Equatable {
    let id: PersistentIdentifier
    let publicID: UUID
    let value: Int
    let assignedDateKey: String
    let appendedAt: Date
    let appendSequence: Int
    let goalID: PersistentIdentifier?

    init(_ reading: GoalReading) {
      id = reading.persistentModelID
      publicID = reading.id
      value = reading.value
      assignedDateKey = reading.assignedDateKey
      appendedAt = reading.appendedAt
      appendSequence = reading.appendSequence
      goalID = reading.goal?.persistentModelID
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
