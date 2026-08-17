import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Goal standing computation")
struct GoalStandingComputationTests {
  @Test("an open goal without a deadline is on pace without invented timing facts")
  func noDeadlineHasNoExpectationOrRefresh() throws {
    let goal = try makeGoal(createdAt: "2024-01-01T00:00:00Z")

    let snapshot = try #require(try standing(goal, normalizedProgress: 0.25))

    #expect(snapshot.standing == .onPace)
    #expect(snapshot.actualNormalizedProgress == 0.25)
    #expect(snapshot.expectedNormalizedProgress == nil)
    #expect(snapshot.deadlineBoundary == nil)
    #expect(snapshot.nextTimeRefresh == nil)
  }

  @Test("creation and the exact expectation threshold stay on pace, then one second is behind")
  func expectationThresholdUsesEqualityAndOneSecondRefresh() throws {
    let goal = try makeGoal(
      createdAt: "2024-01-01T00:00:00Z",
      deadline: "2024-01-01"
    )
    let creation = try instant("2024-01-01T00:00:00Z")
    let threshold = try instant("2024-01-01T12:00:00Z")
    let oneSecondLater = try instant("2024-01-01T12:00:01Z")
    let boundary = try instant("2024-01-02T00:00:00Z")

    let atCreation = try #require(
      try standing(goal, normalizedProgress: 0, at: creation)
    )
    #expect(atCreation.standing == .onPace)
    #expect(atCreation.expectedNormalizedProgress == 0)
    #expect(atCreation.nextTimeRefresh == creation.addingTimeInterval(1))

    let beforeThreshold = try #require(
      try standing(
        goal,
        normalizedProgress: 0.5,
        at: threshold.addingTimeInterval(-1)
      )
    )
    #expect(beforeThreshold.standing == .onPace)
    #expect(beforeThreshold.nextTimeRefresh == oneSecondLater)

    let atThreshold = try #require(
      try standing(goal, normalizedProgress: 0.5, at: threshold)
    )
    #expect(atThreshold.standing == .onPace)
    #expect(atThreshold.expectedNormalizedProgress == 0.5)
    #expect(atThreshold.nextTimeRefresh == oneSecondLater)

    let afterThreshold = try #require(
      try standing(goal, normalizedProgress: 0.5, at: oneSecondLater)
    )
    #expect(afterThreshold.standing == .behind)
    #expect(afterThreshold.nextTimeRefresh == boundary)
  }

  @Test("the exact following-local-day boundary is past due and dominates completion")
  func deadlineBoundaryIsExclusiveAndPastDueDominatesProgress() throws {
    let goal = try makeGoal(
      createdAt: "2024-01-01T00:00:00Z",
      deadline: "2024-01-01"
    )
    let boundary = try instant("2024-01-02T00:00:00Z")

    for (evaluation, progress) in [
      (boundary, 1.0),
      (boundary.addingTimeInterval(1), 1.5),
    ] {
      let snapshot = try #require(
        try standing(goal, normalizedProgress: progress, at: evaluation)
      )
      #expect(snapshot.standing == .pastDue)
      #expect(snapshot.actualNormalizedProgress == progress)
      #expect(snapshot.expectedNormalizedProgress == 1)
      #expect(snapshot.deadlineBoundary == boundary)
      #expect(snapshot.nextTimeRefresh == nil)
    }
  }

  @Test("a behind goal refreshes only at its boundary while complete progress refreshes there")
  func refreshTimingForBehindAndCompleteProgress() throws {
    let goal = try makeGoal(
      createdAt: "2024-01-01T00:00:00Z",
      deadline: "2024-01-01"
    )
    let evaluation = try instant("2024-01-01T18:00:00Z")
    let boundary = try instant("2024-01-02T00:00:00Z")

    let behind = try #require(
      try standing(goal, normalizedProgress: 0.5, at: evaluation)
    )
    let complete = try #require(
      try standing(goal, normalizedProgress: 1, at: evaluation)
    )
    let overComplete = try #require(
      try standing(goal, normalizedProgress: 1.5, at: evaluation)
    )

    #expect(behind.standing == .behind)
    #expect(behind.nextTimeRefresh == boundary)
    #expect(complete.standing == .onPace)
    #expect(complete.nextTimeRefresh == boundary)
    #expect(overComplete.standing == .onPace)
    #expect(overComplete.actualNormalizedProgress == 1.5)
    #expect(overComplete.nextTimeRefresh == boundary)
  }

  @Test("spring-forward and fall-back deadlines use their real local durations")
  func daylightSavingBoundariesUseCalendarResolvedInstants() throws {
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let calendar = gregorian(in: losAngeles)

    let spring = try makeGoal(
      createdAt: "2024-03-09T08:00:00Z",
      deadline: "2024-03-10"
    )
    let springSnapshot = try #require(
      try standing(
        spring,
        normalizedProgress: 0.6,
        at: try instant("2024-03-10T08:00:00Z"),
        calendar: calendar,
        timeZone: losAngeles
      )
    )
    #expect(springSnapshot.deadlineBoundary == (try instant("2024-03-11T07:00:00Z")))
    #expect((try #require(springSnapshot.expectedNormalizedProgress)) == 24.0 / 47.0)

    let fall = try makeGoal(
      createdAt: "2024-11-02T07:00:00Z",
      deadline: "2024-11-03"
    )
    let fallSnapshot = try #require(
      try standing(
        fall,
        normalizedProgress: 0.6,
        at: try instant("2024-11-03T07:00:00Z"),
        calendar: calendar,
        timeZone: losAngeles
      )
    )
    #expect(fallSnapshot.deadlineBoundary == (try instant("2024-11-04T08:00:00Z")))
    #expect((try #require(fallSnapshot.expectedNormalizedProgress)) == 24.0 / 49.0)
  }

  @Test("deadline resolution stays proleptic Gregorian across the 1582 civil cutover")
  func deadlineResolutionUsesGoalDateCalendarSemantics() throws {
    let deadline = try goalDate("1582-10-04")
    let expectedBoundary = Date(timeIntervalSince1970: -12_220_156_800)
    let goal = Goal(
      name: "Read",
      kind: .accumulate,
      target: 10,
      unit: "pages",
      deadline: deadline,
      createdAt: expectedBoundary.addingTimeInterval(-12 * 60 * 60)
    )

    let snapshot = try #require(
      try standing(
        goal,
        normalizedProgress: 1,
        at: expectedBoundary,
        calendar: utcCalendar,
        timeZone: utc
      )
    )

    #expect(snapshot.deadlineBoundary == expectedBoundary)
    #expect(snapshot.standing == .pastDue)
  }

  @Test("a deadline on the creation day remains valid through that local day")
  func creationDayDeadlineUsesFollowingLocalDay() throws {
    let newYork = try #require(TimeZone(identifier: "America/New_York"))
    let goal = try makeGoal(
      createdAt: "2024-06-01T18:00:00Z",
      deadline: "2024-06-01"
    )

    let snapshot = try #require(
      try standing(
        goal,
        normalizedProgress: 0.5,
        at: try instant("2024-06-01T21:00:00Z"),
        calendar: gregorian(in: newYork),
        timeZone: newYork
      )
    )

    #expect(snapshot.deadlineBoundary == (try instant("2024-06-02T04:00:00Z")))
    #expect(snapshot.expectedNormalizedProgress == 0.3)
  }

  @Test("the same stored deadline resolves again when the viewing time zone changes")
  func timeZoneChangeMovesOnlyTheResolvedBoundary() throws {
    let goal = try makeGoal(
      createdAt: "2023-12-30T00:00:00Z",
      deadline: "2024-01-01"
    )
    let evaluation = try instant("2023-12-31T00:00:00Z")
    let newYork = try #require(TimeZone(identifier: "America/New_York"))
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))

    let eastern = try #require(
      try standing(
        goal,
        normalizedProgress: 0.5,
        at: evaluation,
        calendar: gregorian(in: newYork),
        timeZone: newYork
      )
    )
    let pacific = try #require(
      try standing(
        goal,
        normalizedProgress: 0.5,
        at: evaluation,
        calendar: gregorian(in: losAngeles),
        timeZone: losAngeles
      )
    )

    #expect(eastern.deadlineBoundary == (try instant("2024-01-02T05:00:00Z")))
    #expect(pacific.deadlineBoundary == (try instant("2024-01-02T08:00:00Z")))
    #expect(goal.deadlineKey == "2024-01-01")
    #expect(goal.createdAt == (try instant("2023-12-30T00:00:00Z")))
  }

  @Test("an edited deadline may already be past due when its full day still followed creation")
  func editedDeadlineCanBePastDueButChronologicallyValid() throws {
    let goal = try makeGoal(
      createdAt: "2024-01-01T12:00:00Z",
      deadline: "2024-01-01"
    )

    let snapshot = try #require(
      try standing(
        goal,
        normalizedProgress: 0.2,
        at: try instant("2024-01-03T00:00:00Z")
      )
    )

    #expect(snapshot.standing == .pastDue)
    #expect(snapshot.deadlineBoundary == (try instant("2024-01-02T00:00:00Z")))
  }

  @Test("the worked books example distinguishes ahead and behind progress")
  func workedBooksExample() throws {
    let goal = try makeGoal(
      target: 6,
      unit: "books",
      createdAt: "2024-10-01T00:00:00Z",
      deadline: "2024-12-31"
    )
    let evaluation = try instant("2024-11-15T00:00:00Z")

    let ahead = try #require(
      try standing(goal, normalizedProgress: 4.0 / 6.0, at: evaluation)
    )
    let behind = try #require(
      try standing(goal, normalizedProgress: 2.0 / 6.0, at: evaluation)
    )

    #expect(ahead.standing == .onPace)
    #expect(behind.standing == .behind)
  }

  @Test("accumulate and both measure directions consume their typed normalized progress")
  func allGoalKindsConsumeTypedProgress() throws {
    let evaluation = try instant("2024-01-01T12:00:00Z")
    let cases: [(Goal, GoalProgressSnapshot, GoalStanding)] = [
      (
        try makeGoal(createdAt: "2024-01-01T00:00:00Z", deadline: "2024-01-01"),
        accumulateProgress(0.75),
        .onPace
      ),
      (
        try makeGoal(
          kind: .measure,
          target: 20,
          baseline: 10,
          createdAt: "2024-01-01T00:00:00Z",
          deadline: "2024-01-01"
        ),
        measureProgress(0.25, baseline: 10, target: 20, current: 12),
        .behind
      ),
      (
        try makeGoal(
          kind: .measure,
          target: 10,
          baseline: 20,
          createdAt: "2024-01-01T00:00:00Z",
          deadline: "2024-01-01"
        ),
        measureProgress(0.5, baseline: 20, target: 10, current: 15),
        .onPace
      ),
    ]

    for (goal, progress, expectedStanding) in cases {
      let snapshot = try #require(
        try GoalStandingComputation().snapshot(
          for: goal,
          progress: progress,
          at: evaluation,
          calendar: utcCalendar,
          timeZone: utc
        )
      )
      #expect(snapshot.standing == expectedStanding)
    }
  }

  @Test("the worked weight arc is measured from baseline and stays past due when complete")
  func workedWeightExample() throws {
    let goal = try makeGoal(
      kind: .measure,
      target: 165,
      unit: "lbs",
      baseline: 195,
      createdAt: "2024-10-01T00:00:00Z",
      deadline: "2025-01-01"
    )
    let progress = measureProgress(12.0 / 30.0, baseline: 195, target: 165, current: 183)

    let beforeDeadline = try #require(
      try GoalStandingComputation().snapshot(
        for: goal,
        progress: progress,
        at: try instant("2024-11-01T00:00:00Z"),
        calendar: utcCalendar,
        timeZone: utc
      )
    )
    #expect(beforeDeadline.standing == .onPace)
    #expect(beforeDeadline.actualNormalizedProgress == 0.4)

    let completeAfterDeadline = try #require(
      try GoalStandingComputation().snapshot(
        for: goal,
        progress: measureProgress(1, baseline: 195, target: 165, current: 165),
        at: try instant("2025-01-09T00:00:00Z"),
        calendar: utcCalendar,
        timeZone: utc
      )
    )
    #expect(completeAfterDeadline.standing == .pastDue)
    #expect(completeAfterDeadline.actualNormalizedProgress == 1)
  }

  @Test("harvested and let-go goals expose closure directly and have no standing")
  func closedGoalsHaveNoStandingOrRefresh() throws {
    for closure in [GoalClosure.harvested, .letGo] {
      let goal = try makeGoal(
        createdAt: "2024-01-01T00:00:00Z",
        deadline: "2024-01-01"
      )
      goal.closureRawValue = closure.rawValue

      let snapshot = try standing(
        goal,
        normalizedProgress: 0.5,
        at: try instant("2024-01-01T12:00:00Z")
      )

      #expect(snapshot == nil)
      #expect(try goal.checkedClosure == closure)
    }
  }

  @Test("evaluation before creation fails instead of projecting backward")
  func evaluationBeforeCreationFails() throws {
    let goal = try makeGoal(createdAt: "2024-01-02T00:00:00Z")

    try expectError(.evaluationBeforeCreation) {
      _ = try standing(
        goal,
        normalizedProgress: 0,
        at: try instant("2024-01-01T23:59:59Z")
      )
    }
  }

  @Test("a deadline boundary at or before creation rejects zero or negative duration")
  func deadlineMustFollowCreation() throws {
    let cases = [
      ("2024-01-02T00:00:00Z", GoalStandingComputationError.deadlineNotAfterCreation),
      ("2024-01-02T00:00:01Z", GoalStandingComputationError.deadlineNotAfterCreation),
    ]

    for (createdAt, expected) in cases {
      let goal = try makeGoal(createdAt: createdAt, deadline: "2024-01-01")
      try expectError(expected) {
        _ = try standing(goal, normalizedProgress: 0, at: goal.createdAt)
      }
    }
  }

  @Test("malformed and unresolvable deadlines fail with typed deadline errors")
  func corruptDeadlinesFail() throws {
    let malformed = try makeGoal(createdAt: "2024-01-01T00:00:00Z")
    malformed.deadlineKey = "2024-02-30"
    try expectError(.invalidDeadline("2024-02-30")) {
      _ = try standing(malformed, normalizedProgress: 0)
    }

    let unresolvable = try makeGoal(
      createdAt: "2024-01-01T00:00:00Z",
      deadline: "9999-12-31"
    )
    try expectError(.invalidDeadlineBoundary(.unrepresentableDate)) {
      _ = try standing(unresolvable, normalizedProgress: 0)
    }
  }

  @Test("unknown closure data fails instead of becoming open")
  func corruptClosureFails() throws {
    let goal = try makeGoal(createdAt: "2024-01-01T00:00:00Z")
    goal.closureRawValue = "completed"

    try expectError(.invalidClosure("completed")) {
      _ = try standing(goal, normalizedProgress: 0)
    }
  }

  @Test("corrupt kind and kind-specific goal configurations fail before pace math")
  func corruptGoalConfigurationFails() throws {
    let unknownKind = try makeGoal(createdAt: "2024-01-01T00:00:00Z")
    unknownKind.kindRawValue = "unknown"
    try expectError(.invalidGoalKind("unknown")) {
      _ = try standing(unknownKind, normalizedProgress: 0)
    }

    let badName = try makeGoal(createdAt: "2024-01-01T00:00:00Z")
    badName.name = " Read "
    try expectError(.invalidName(" Read ")) {
      _ = try standing(badName, normalizedProgress: 0)
    }

    let badTarget = try makeGoal(createdAt: "2024-01-01T00:00:00Z")
    badTarget.target = 0
    try expectError(.invalidTarget(0)) {
      _ = try standing(badTarget, normalizedProgress: 0)
    }

    let badUnit = try makeGoal(createdAt: "2024-01-01T00:00:00Z")
    badUnit.unit = ""
    try expectError(.invalidUnit("")) {
      _ = try standing(badUnit, normalizedProgress: 0)
    }

    let accumulateBaseline = try makeGoal(createdAt: "2024-01-01T00:00:00Z")
    accumulateBaseline.baseline = 2
    try expectError(.invalidAccumulateBaseline(2)) {
      _ = try standing(accumulateBaseline, normalizedProgress: 0)
    }

    let missingMeasureBaseline = try makeGoal(
      kind: .measure,
      target: 20,
      baseline: 10,
      createdAt: "2024-01-01T00:00:00Z"
    )
    missingMeasureBaseline.baseline = nil
    try expectError(.missingMeasureBaseline) {
      _ = try standing(
        missingMeasureBaseline,
        progress: measureProgress(0, baseline: 10, target: 20, current: 10)
      )
    }

    let equalMeasureBaseline = try makeGoal(
      kind: .measure,
      target: 20,
      baseline: 10,
      createdAt: "2024-01-01T00:00:00Z"
    )
    equalMeasureBaseline.baseline = 20
    try expectError(.measureBaselineEqualsTarget(20)) {
      _ = try standing(
        equalMeasureBaseline,
        progress: measureProgress(0, baseline: 20, target: 20, current: 20)
      )
    }
  }

  @Test("kind-mismatched progress fails before comparison")
  func wrongKindProgressFails() throws {
    let accumulate = try makeGoal(createdAt: "2024-01-01T00:00:00Z")
    try expectError(.progressKindMismatch(expected: .accumulate, actual: .measure)) {
      _ = try standing(
        accumulate,
        progress: measureProgress(0, baseline: 10, target: 20, current: 10)
      )
    }
  }

  @Test("negative and nonfinite normalized progress fail without repair")
  func malformedNormalizedProgressFails() throws {
    let goal = try makeGoal(createdAt: "2024-01-01T00:00:00Z")

    try expectError(.negativeNormalizedProgress(-0.01)) {
      _ = try standing(goal, normalizedProgress: -0.01)
    }
    try expectError(.nonFiniteNormalizedProgress) {
      _ = try standing(goal, normalizedProgress: .infinity)
    }
    try expectError(.nonFiniteNormalizedProgress) {
      _ = try standing(goal, normalizedProgress: .nan)
    }
  }

  @Test("invalid instants fail before duration arithmetic")
  func nonfiniteInstantsFail() throws {
    let invalidCreation = try makeGoal(createdAt: "2024-01-01T00:00:00Z")
    invalidCreation.createdAt = Date(timeIntervalSinceReferenceDate: .nan)
    try expectError(.invalidCreationInstant) {
      _ = try standing(invalidCreation, normalizedProgress: 0)
    }

    let goal = try makeGoal(createdAt: "2024-01-01T00:00:00Z")
    try expectError(.invalidEvaluationInstant) {
      _ = try standing(
        goal,
        normalizedProgress: 0,
        at: Date(timeIntervalSinceReferenceDate: .infinity)
      )
    }
  }

  @Test("standing calculation does not mutate the goal or save unrelated pending work")
  func calculationHasNoMutationOrPersistenceSideEffects() throws {
    let context = ModelContext(try TendModelContainer.inMemory())
    let goal = try makeGoal(
      createdAt: "2024-01-01T00:00:00Z",
      deadline: "2024-01-01"
    )
    context.insert(goal)
    try context.save()
    let pending = Habit(name: "Pending", cadence: .daily, target: 1)
    context.insert(pending)
    let facts = GoalFacts(goal)

    _ = try standing(
      goal,
      normalizedProgress: 0.5,
      at: try instant("2024-01-01T12:00:00Z")
    )

    #expect(GoalFacts(goal) == facts)
    #expect(context.hasChanges)
    let verification = ModelContext(context.container)
    #expect(try verification.fetch(FetchDescriptor<Habit>()).isEmpty)
  }

  private func standing(
    _ goal: Goal,
    normalizedProgress: Double,
    at evaluation: Date? = nil,
    calendar: Calendar? = nil,
    timeZone: TimeZone? = nil
  ) throws -> GoalStandingSnapshot? {
    try standing(
      goal,
      progress: accumulateProgress(normalizedProgress),
      at: evaluation,
      calendar: calendar,
      timeZone: timeZone
    )
  }

  private func standing(
    _ goal: Goal,
    progress: GoalProgressSnapshot,
    at evaluation: Date? = nil,
    calendar: Calendar? = nil,
    timeZone: TimeZone? = nil
  ) throws -> GoalStandingSnapshot? {
    let timeZone = timeZone ?? utc
    return try GoalStandingComputation().snapshot(
      for: goal,
      progress: progress,
      at: evaluation ?? goal.createdAt,
      calendar: calendar ?? gregorian(in: timeZone),
      timeZone: timeZone
    )
  }

  private func makeGoal(
    kind: GoalKind = .accumulate,
    target: Int = 10,
    unit: String = "pages",
    baseline: Int? = nil,
    createdAt: String,
    deadline: String? = nil
  ) throws -> Goal {
    Goal(
      name: kind == .accumulate ? "Read" : "Weight",
      kind: kind,
      target: target,
      unit: unit,
      baseline: kind == .measure ? (baseline ?? 20) : baseline,
      deadline: try deadline.map(goalDate),
      createdAt: try instant(createdAt)
    )
  }

  private func accumulateProgress(_ normalizedProgress: Double) -> GoalProgressSnapshot {
    .accumulate(
      AccumulateGoalProgress(
        total: 0,
        target: 10,
        unit: "pages",
        normalizedProgress: normalizedProgress
      )
    )
  }

  private func measureProgress(
    _ normalizedProgress: Double,
    baseline: Int,
    target: Int,
    current: Int
  ) -> GoalProgressSnapshot {
    .measure(
      MeasureGoalProgress(
        baseline: baseline,
        target: target,
        currentValue: current,
        effectiveReadingID: nil,
        completedDistance: 0,
        totalDistance: abs(target - baseline),
        unit: "lbs",
        normalizedProgress: normalizedProgress
      )
    )
  }

  private func expectError(
    _ expected: GoalStandingComputationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected GoalStandingComputationError: \(expected)")
    } catch let error as GoalStandingComputationError {
      #expect(error == expected)
    }
  }

  private var utc: TimeZone {
    TimeZone(secondsFromGMT: 0)!
  }

  private var utcCalendar: Calendar {
    gregorian(in: utc)
  }

  private func gregorian(in timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private func goalDate(_ value: String) throws -> GoalDate {
    try #require(GoalDate(rawValue: value))
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
  let closureRawValue: String?

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
    closureRawValue = goal.closureRawValue
  }
}
