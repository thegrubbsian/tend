import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Goal progress computation")
struct GoalProgressComputationTests {
  @Test("kind-specific payload initializers fix their Goal kind")
  func payloadInitializersFixTheirKinds() {
    let accumulate = AccumulateGoalProgress(
      total: 2,
      target: 4,
      unit: "pages",
      normalizedProgress: 0.5
    )
    let measure = MeasureGoalProgress(
      baseline: 10,
      target: 20,
      currentValue: 15,
      effectiveReadingID: nil,
      completedDistance: 5,
      totalDistance: 10,
      unit: "kg",
      normalizedProgress: 0.5
    )

    #expect(accumulate.kind == .accumulate)
    #expect(measure.kind == .measure)
  }

  @Test("accumulate sums empty, one, many, exact, over-target, and old history")
  func accumulateSumsCompleteHistory() throws {
    let cases: [(amounts: [Int], target: Int, total: Int, normalized: Double)] = [
      ([], 10, 0, 0),
      ([3], 10, 3, 0.3),
      ([2, 3, 4], 10, 9, 0.9),
      ([4, 6], 10, 10, 1),
      ([8, 7], 10, 15, 1.5),
    ]

    for value in cases {
      let context = try makeContext()
      let entries = try value.amounts.enumerated().map { index, amount in
        GoalEntry(
          amount: amount,
          assignedDate: try goalDate(
            index.isMultiple(of: 2) ? "2020-01-01" : "2024-07-04"
          ),
          appendedAt: try instant("2024-07-05T00:00:00Z")
            .addingTimeInterval(TimeInterval(index)),
          appendSequence: index
        )
      }
      let goal = try persistedGoal(
        in: context,
        kind: .accumulate,
        target: value.target,
        entries: entries
      )

      let snapshot = try GoalProgressComputation(context: context).snapshot(for: goal)

      #expect(
        snapshot
          == .accumulate(
            AccumulateGoalProgress(
              total: value.total,
              target: value.target,
              unit: "pages",
              normalizedProgress: value.normalized
            )
          )
      )
    }
  }

  @Test("accumulate is independent of relationship order and accepts a unique Int.max sequence")
  func accumulateIsDeterministicAndAcceptsMaximumSequence() throws {
    let context = try makeContext()
    let entries = try [
      GoalEntry(
        amount: 2,
        assignedDate: goalDate("2024-07-03"),
        appendedAt: instant("2024-07-06T00:00:00Z"),
        appendSequence: Int.max
      ),
      GoalEntry(
        amount: 5,
        assignedDate: goalDate("2024-07-04"),
        appendedAt: instant("2024-07-05T00:00:00Z"),
        appendSequence: 0
      ),
    ]
    let goal = try persistedGoal(in: context, kind: .accumulate, target: 4, entries: entries)
    let computation = GoalProgressComputation(context: context)

    let first = try computation.snapshot(for: goal)
    goal.entries?.reverse()
    let second = try computation.snapshot(for: goal)

    #expect(first == second)
    #expect(
      second
        == .accumulate(
          AccumulateGoalProgress(
            total: 7,
            target: 4,
            unit: "pages",
            normalizedProgress: 1.75
          )
        )
    )
  }

  @Test("accumulate preserves finite uncapped progress at integer extremes")
  func accumulateProgressAtIntegerExtremeIsFinite() throws {
    let context = try makeContext()
    let goal = try persistedGoal(
      in: context,
      kind: .accumulate,
      target: 1,
      entries: [
        GoalEntry(
          amount: Int.max,
          assignedDate: try goalDate("2024-07-04"),
          appendedAt: try instant("2024-07-04T00:00:00Z"),
          appendSequence: Int.max
        )
      ]
    )

    let snapshot = try GoalProgressComputation(context: context).snapshot(for: goal)
    let progress = try #require(snapshot.accumulateValue)

    #expect(progress.total == Int.max)
    #expect(progress.normalizedProgress == Double(Int.max))
    #expect(progress.normalizedProgress.isFinite)
    #expect(progress.normalizedProgress > 1)
  }

  @Test("accumulate total overflow fails with a typed arithmetic error")
  func accumulateTotalOverflowFailsChecked() throws {
    let context = try makeContext()
    let goal = try persistedGoal(
      in: context,
      kind: .accumulate,
      entries: [
        try entry(amount: Int.max, sequence: 0),
        try entry(amount: 1, sequence: 1),
      ]
    )

    try expectComputationError(.accumulateTotalOverflow) {
      _ = try GoalProgressComputation(context: context).snapshot(for: goal)
    }
  }

  @Test("measure with no readings uses baseline and zero progress")
  func measureWithNoReadingsUsesBaseline() throws {
    let context = try makeContext()
    let goal = try persistedGoal(in: context, kind: .measure, target: 20, baseline: 10)

    let snapshot = try GoalProgressComputation(context: context).snapshot(for: goal)

    #expect(
      snapshot
        == .measure(
          MeasureGoalProgress(
            baseline: 10,
            target: 20,
            currentValue: 10,
            effectiveReadingID: nil,
            completedDistance: 0,
            totalDistance: 10,
            unit: "kg",
            normalizedProgress: 0
          )
        )
    )
  }

  @Test("measure preserves current while clamping increasing and decreasing progress")
  func measureClampsDirectionalDistanceButNotCurrent() throws {
    let cases:
      [(
        baseline: Int, target: Int, current: Int, completed: Int, total: Int, normalized: Double
      )] = [
        (10, 20, 15, 5, 10, 0.5),
        (10, 20, 5, 0, 10, 0),
        (10, 20, 20, 10, 10, 1),
        (10, 20, 30, 10, 10, 1),
        (20, 10, 15, 5, 10, 0.5),
        (20, 10, 25, 0, 10, 0),
        (20, 10, 5, 10, 10, 1),
        (-10, 10, 0, 10, 20, 0.5),
        (10, 20, -5, 0, 10, 0),
      ]

    for (index, value) in cases.enumerated() {
      let context = try makeContext()
      let readingID = UUID()
      let goal = try persistedGoal(
        in: context,
        kind: .measure,
        target: value.target,
        baseline: value.baseline,
        readings: [
          GoalReading(
            id: readingID,
            value: value.current,
            assignedDate: try goalDate("2024-07-04"),
            appendedAt: try instant("2024-07-04T00:00:00Z"),
            appendSequence: index
          )
        ]
      )

      let snapshot = try GoalProgressComputation(context: context).snapshot(for: goal)

      #expect(
        snapshot
          == .measure(
            MeasureGoalProgress(
              baseline: value.baseline,
              target: value.target,
              currentValue: value.current,
              effectiveReadingID: readingID,
              completedDistance: value.completed,
              totalDistance: value.total,
              unit: "kg",
              normalizedProgress: value.normalized
            )
          )
      )
    }
  }

  @Test("latest LocalDate then highest sequence selects the effective reading")
  func measureEffectivenessIgnoresAppendTimeAndArrayOrder() throws {
    let context = try makeContext()
    let effectiveID = UUID()
    let sameTimestamp = try instant("2024-07-05T12:00:00Z")
    let readings = [
      GoalReading(
        value: 12,
        assignedDate: try goalDate("2024-07-03"),
        appendedAt: try instant("2024-07-07T12:00:00Z"),
        appendSequence: 30
      ),
      GoalReading(
        value: 16,
        assignedDate: try goalDate("2024-07-05"),
        appendedAt: sameTimestamp,
        appendSequence: 4
      ),
      GoalReading(
        id: effectiveID,
        value: 18,
        assignedDate: try goalDate("2024-07-05"),
        appendedAt: sameTimestamp,
        appendSequence: Int.max
      ),
      GoalReading(
        value: 19,
        assignedDate: try goalDate("2024-07-04"),
        appendedAt: try instant("2024-07-08T12:00:00Z"),
        appendSequence: 40
      ),
    ]
    let goal = try persistedGoal(
      in: context,
      kind: .measure,
      target: 20,
      baseline: 10,
      readings: readings
    )
    let computation = GoalProgressComputation(context: context)

    let first = try computation.snapshot(for: goal)
    goal.readings = readings.reversed()
    let second = try computation.snapshot(for: goal)
    let progress = try #require(second.measureValue)

    #expect(first == second)
    #expect(progress.currentValue == 18)
    #expect(progress.effectiveReadingID == effectiveID)
    #expect(progress.completedDistance == 8)
    #expect(progress.normalizedProgress == 0.8)
    #expect(goal.readings?.count == 4)
  }

  @Test("measure remains finite at the largest nonoverflowing span")
  func measureLargestCheckedSpanIsFinite() throws {
    let context = try makeContext()
    let readingID = UUID()
    let goal = try persistedGoal(
      in: context,
      kind: .measure,
      target: Int.max,
      baseline: 0,
      readings: [
        GoalReading(
          id: readingID,
          value: Int.max,
          assignedDate: try goalDate("2024-07-04"),
          appendedAt: try instant("2024-07-04T12:00:00Z"),
          appendSequence: Int.max
        )
      ]
    )

    let snapshot = try GoalProgressComputation(context: context).snapshot(for: goal)
    let progress = try #require(snapshot.measureValue)

    #expect(progress.currentValue == Int.max)
    #expect(progress.effectiveReadingID == readingID)
    #expect(progress.completedDistance == Int.max)
    #expect(progress.totalDistance == Int.max)
    #expect(progress.normalizedProgress == 1)
    #expect(progress.normalizedProgress.isFinite)
  }

  @Test("measure span and traveled distance overflow fail instead of trapping")
  func measureArithmeticOverflowFailsChecked() throws {
    do {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: .measure,
        target: Int.max,
        baseline: Int.min
      )
      try expectComputationError(.measureSpanOverflow) {
        _ = try GoalProgressComputation(context: context).snapshot(for: goal)
      }
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: .measure,
        target: 1,
        baseline: -1,
        readings: [try reading(value: Int.max, sequence: 0)]
      )
      try expectComputationError(.measureTraveledDistanceOverflow) {
        _ = try GoalProgressComputation(context: context).snapshot(for: goal)
      }
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: .measure,
        target: Int.max - 1,
        baseline: Int.max,
        readings: [try reading(value: Int.min, sequence: 0)]
      )
      try expectComputationError(.measureTraveledDistanceOverflow) {
        _ = try GoalProgressComputation(context: context).snapshot(for: goal)
      }
    }
  }

  @Test("malformed goal scalar configuration is rejected before computation")
  func malformedScalarConfigurationIsRejected() throws {
    let cases: [(mutate: (Goal) -> Void, error: GoalProgressComputationError)] = [
      ({ $0.name = "" }, .invalidName("")),
      ({ $0.name = " padded " }, .invalidName(" padded ")),
      ({ $0.target = 0 }, .invalidTarget(0)),
      ({ $0.target = -1 }, .invalidTarget(-1)),
      ({ $0.unit = "\n" }, .invalidUnit("\n")),
      ({ $0.unit = " padded " }, .invalidUnit(" padded ")),
      ({ $0.kindRawValue = "count" }, .invalidGoalKind("count")),
      ({ $0.baseline = 0 }, .invalidAccumulateBaseline(0)),
      (
        {
          $0.kindRawValue = GoalKind.measure.rawValue
          $0.baseline = nil
        }, .missingMeasureBaseline
      ),
      (
        {
          $0.kindRawValue = GoalKind.measure.rawValue
          $0.baseline = $0.target
        }, .measureBaselineEqualsTarget(10)
      ),
      ({ $0.deadlineKey = "tomorrow" }, .invalidDeadline("tomorrow")),
    ]

    for value in cases {
      let context = try makeContext()
      let goal = try persistedGoal(in: context, kind: .accumulate)
      value.mutate(goal)
      let before = GoalFacts(goal)

      try expectComputationError(value.error) {
        _ = try GoalProgressComputation(context: context).snapshot(for: goal)
      }

      #expect(GoalFacts(goal) == before)
      #expect(context.hasChanges)
    }
  }

  @Test("a parseable elapsed deadline remains valid configuration")
  func elapsedDeadlineDoesNotFilterHistory() throws {
    let context = try makeContext()
    let goal = try persistedGoal(
      in: context,
      kind: .accumulate,
      target: 2,
      deadline: try goalDate("2020-01-01"),
      entries: [try entry(amount: 2, date: "2019-12-31", sequence: 0)]
    )

    let snapshot = try GoalProgressComputation(context: context).snapshot(for: goal)

    #expect(snapshot.accumulateValue?.total == 2)
    #expect(snapshot.accumulateValue?.normalizedProgress == 1)
  }

  @Test("children must be kind-consistent")
  func childrenMustBeKindConsistent() throws {

    do {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: .accumulate,
        readings: [try reading(value: 1, sequence: 0)]
      )
      try expectComputationError(.invalidGoalGraph) {
        _ = try GoalProgressComputation(context: context).snapshot(for: goal)
      }
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: .measure,
        baseline: 20,
        entries: [try entry(amount: 1, sequence: 0)]
      )
      try expectComputationError(.invalidGoalGraph) {
        _ = try GoalProgressComputation(context: context).snapshot(for: goal)
      }
    }
  }

  @Test("fetched inverse children must exactly equal unique relationship identities")
  func persistedGraphMustReconcileExactly() throws {
    let container = try TendModelContainer.inMemory()
    let firstContext = ModelContext(container)
    let goal = try persistedGoal(in: firstContext, kind: .accumulate)
    _ = goal.entries

    let secondContext = ModelContext(container)
    let secondGoal = try #require(secondContext.fetch(FetchDescriptor<Goal>()).first)
    let hidden = try entry(amount: 1, sequence: 0, goal: secondGoal)
    secondContext.insert(hidden)
    try secondContext.save()

    let before = GoalFacts(goal)
    try expectComputationError(.invalidGoalGraph) {
      _ = try GoalProgressComputation(context: firstContext).snapshot(for: goal)
    }
    #expect(GoalFacts(goal) == before)
    #expect(goal.entries?.isEmpty == true)
  }

  @Test("detached, deleted, malformed, and nonpositive children are rejected")
  func invalidChildFactsAreRejected() throws {
    do {
      let context = try makeContext()
      let goal = try persistedGoal(in: context, kind: .accumulate)
      goal.entries = [try entry(amount: 1, sequence: 0)]
      try expectComputationError(.invalidGoalGraph) {
        _ = try GoalProgressComputation(context: context).snapshot(for: goal)
      }
    }

    let entryCases: [(mutate: (GoalEntry) -> Void, error: GoalProgressComputationError)] = [
      ({ $0.assignedDateKey = "yesterday" }, .invalidAssignedDate("yesterday")),
      ({ $0.amount = 0 }, .invalidEntryAmount(0)),
      ({ $0.amount = -1 }, .invalidEntryAmount(-1)),
    ]
    for value in entryCases {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: .accumulate,
        entries: [try entry(amount: 1, sequence: 0)]
      )
      let child = try #require(goal.entries?.first)
      value.mutate(child)
      try expectComputationError(value.error) {
        _ = try GoalProgressComputation(context: context).snapshot(for: goal)
      }
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: .measure,
        baseline: 20,
        readings: [try reading(value: 19, sequence: 0)]
      )
      let child = try #require(goal.readings?.first)
      child.assignedDateKey = "2024-02-30"
      try expectComputationError(.invalidAssignedDate("2024-02-30")) {
        _ = try GoalProgressComputation(context: context).snapshot(for: goal)
      }
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: .accumulate,
        entries: [try entry(amount: 1, sequence: 0)]
      )
      let child = try #require(goal.entries?.first)
      context.delete(child)
      try expectComputationError(.invalidGoalGraph) {
        _ = try GoalProgressComputation(context: context).snapshot(for: goal)
      }
    }
  }

  @Test("relevant sequences must be globally unique and nonnegative")
  func sequenceHistoryIsValidatedWithoutAdvancingIt() throws {
    do {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: .accumulate,
        entries: [try entry(amount: 1, sequence: -1)]
      )
      try expectComputationError(.invalidSequence(-1)) {
        _ = try GoalProgressComputation(context: context).snapshot(for: goal)
      }
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: .measure,
        baseline: 20,
        readings: [
          try reading(value: 19, sequence: 7),
          try reading(value: 18, sequence: 7),
        ]
      )
      try expectComputationError(.duplicateSequence(7)) {
        _ = try GoalProgressComputation(context: context).snapshot(for: goal)
      }
    }
  }

  @Test("detached, deleted, and foreign-context goals are rejected")
  func invalidGoalOwnershipIsRejected() throws {
    let context = try makeContext()
    let computation = GoalProgressComputation(context: context)

    let detached = Goal(name: "Detached", kind: .accumulate, target: 1)
    try expectComputationError(.detachedGoal) {
      _ = try computation.snapshot(for: detached)
    }

    let deleted = try persistedGoal(in: context, kind: .accumulate)
    context.delete(deleted)
    try expectComputationError(.detachedGoal) {
      _ = try computation.snapshot(for: deleted)
    }

    let foreignContext = try makeContext()
    let foreign = try persistedGoal(in: foreignContext, kind: .accumulate)
    try expectComputationError(.foreignGoal) {
      _ = try computation.snapshot(for: foreign)
    }
  }

  @Test("success and failure never mutate models or save pending work")
  func computationHasNoMutationOrPersistenceSideEffects() throws {
    let context = try makeContext()
    let entries = [
      try entry(amount: 2, date: "2024-07-03", sequence: 2),
      try entry(amount: 3, date: "2024-07-04", sequence: 8),
    ]
    let goal = try persistedGoal(in: context, kind: .accumulate, entries: entries)
    let unrelated = Habit(name: "Pending", cadence: .daily, target: 1)
    context.insert(unrelated)
    let successFacts = GoalFacts(goal)
    let pendingIDs = context.insertedModelsArray.map(\.persistentModelID)

    _ = try GoalProgressComputation(context: context).snapshot(for: goal)

    #expect(GoalFacts(goal) == successFacts)
    #expect(context.insertedModelsArray.map(\.persistentModelID) == pendingIDs)
    #expect(context.deletedModelsArray.isEmpty)
    #expect(context.hasChanges)

    let first = try #require(goal.entries?.first)
    first.amount = 0
    let failureFacts = GoalFacts(goal)
    let failurePendingIDs = context.insertedModelsArray.map(\.persistentModelID)
    try expectComputationError(.invalidEntryAmount(0)) {
      _ = try GoalProgressComputation(context: context).snapshot(for: goal)
    }

    #expect(GoalFacts(goal) == failureFacts)
    #expect(context.insertedModelsArray.map(\.persistentModelID) == failurePendingIDs)
    #expect(context.deletedModelsArray.isEmpty)
    #expect(context.hasChanges)

    let verification = ModelContext(context.container)
    #expect(try verification.fetch(FetchDescriptor<Habit>()).isEmpty)
    let storedGoal = try #require(verification.fetch(FetchDescriptor<Goal>()).first)
    #expect(storedGoal.entries?.map(\.amount).sorted() == [2, 3])
  }

  private func persistedGoal(
    in context: ModelContext,
    kind: GoalKind,
    target: Int = 10,
    baseline: Int? = nil,
    deadline: LocalDate? = nil,
    entries: [GoalEntry] = [],
    readings: [GoalReading] = []
  ) throws -> Goal {
    let goal = Goal(
      name: kind == .accumulate ? "Read" : "Weight",
      kind: kind,
      target: target,
      unit: kind == .accumulate ? "pages" : "kg",
      baseline: kind == .measure ? (baseline ?? 20) : baseline,
      deadline: deadline,
      createdAt: try instant("2024-01-01T00:00:00Z")
    )
    goal.entries = entries
    goal.readings = readings
    context.insert(goal)
    try context.save()
    return goal
  }

  private func entry(
    amount: Int,
    date: String = "2024-07-04",
    sequence: Int,
    goal: Goal? = nil
  ) throws -> GoalEntry {
    GoalEntry(
      amount: amount,
      assignedDate: try goalDate(date),
      appendedAt: try instant("2024-07-04T12:00:00Z"),
      appendSequence: sequence,
      goal: goal
    )
  }

  private func reading(
    value: Int,
    date: String = "2024-07-04",
    sequence: Int,
    goal: Goal? = nil
  ) throws -> GoalReading {
    GoalReading(
      value: value,
      assignedDate: try goalDate(date),
      appendedAt: try instant("2024-07-04T12:00:00Z"),
      appendSequence: sequence,
      goal: goal
    )
  }

  private func expectComputationError(
    _ expected: GoalProgressComputationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected GoalProgressComputationError: \(expected)")
    } catch let error as GoalProgressComputationError {
      #expect(error == expected)
    }
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private func goalDate(_ value: String) throws -> LocalDate {
    try #require(LocalDate(rawValue: value))
  }
}

extension GoalProgressSnapshot {
  fileprivate var accumulateValue: AccumulateGoalProgress? {
    guard case .accumulate(let value) = self else { return nil }
    return value
  }

  fileprivate var measureValue: MeasureGoalProgress? {
    guard case .measure(let value) = self else { return nil }
    return value
  }
}

private struct GoalFacts: Equatable {
  let id: UUID
  let name: String
  let kindRawValue: String
  let target: Int
  let unit: String
  let baseline: Int?
  let deadlineKey: String?
  let createdAt: Date
  let entries: [EntryFacts]?
  let readings: [ReadingFacts]?

  @MainActor
  init(_ goal: Goal) {
    id = goal.id
    name = goal.name
    kindRawValue = goal.kindRawValue
    target = goal.target
    unit = goal.unit
    baseline = goal.baseline
    deadlineKey = goal.deadlineKey
    createdAt = goal.createdAt
    entries = goal.entries?.map(EntryFacts.init)
    readings = goal.readings?.map(ReadingFacts.init)
  }
}

private struct EntryFacts: Equatable {
  let id: UUID
  let amount: Int
  let assignedDateKey: String
  let appendedAt: Date
  let appendSequence: Int
  let goalID: UUID?

  @MainActor
  init(_ entry: GoalEntry) {
    id = entry.id
    amount = entry.amount
    assignedDateKey = entry.assignedDateKey
    appendedAt = entry.appendedAt
    appendSequence = entry.appendSequence
    goalID = entry.goal?.id
  }
}

private struct ReadingFacts: Equatable {
  let id: UUID
  let value: Int
  let assignedDateKey: String
  let appendedAt: Date
  let appendSequence: Int
  let goalID: UUID?

  @MainActor
  init(_ reading: GoalReading) {
    id = reading.id
    value = reading.value
    assignedDateKey = reading.assignedDateKey
    appendedAt = reading.appendedAt
    appendSequence = reading.appendSequence
    goalID = reading.goal?.id
  }
}
