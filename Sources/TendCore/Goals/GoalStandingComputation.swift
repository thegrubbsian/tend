import Foundation

public enum GoalStanding: Equatable, Sendable {
  case onPace
  case behind
  case pastDue
}

public struct GoalStandingSnapshot: Equatable, Sendable {
  public let standing: GoalStanding
  public let actualNormalizedProgress: Double
  public let expectedNormalizedProgress: Double?
  public let deadlineBoundary: Date?
  public let nextTimeRefresh: Date?

  public init(
    standing: GoalStanding,
    actualNormalizedProgress: Double,
    expectedNormalizedProgress: Double?,
    deadlineBoundary: Date?,
    nextTimeRefresh: Date?
  ) {
    self.standing = standing
    self.actualNormalizedProgress = actualNormalizedProgress
    self.expectedNormalizedProgress = expectedNormalizedProgress
    self.deadlineBoundary = deadlineBoundary
    self.nextTimeRefresh = nextTimeRefresh
  }
}

public enum GoalStandingComputationError: Error, Equatable, Sendable {
  case invalidGoalKind(String)
  case invalidName(String)
  case invalidTarget(Int)
  case invalidUnit(String)
  case invalidAccumulateBaseline(Int)
  case missingMeasureBaseline
  case measureBaselineEqualsTarget(Int)
  case invalidClosure(String)
  case invalidCreationInstant
  case invalidEvaluationInstant
  case evaluationBeforeCreation
  case invalidDeadline(String)
  case invalidDeadlineBoundary(GoalDateError)
  case deadlineNotAfterCreation
  case progressKindMismatch(expected: GoalKind, actual: GoalKind)
  case nonFiniteNormalizedProgress
  case negativeNormalizedProgress(Double)
}

public struct GoalStandingComputation: Sendable {
  public init() {}

  public func snapshot(
    for goal: Goal,
    progress: GoalProgressSnapshot,
    at instant: Date,
    calendar: Calendar,
    timeZone: TimeZone
  ) throws -> GoalStandingSnapshot? {
    let goalKind = try validatedKindAndConfiguration(of: goal)
    let closure = try validatedClosure(of: goal)
    try validateChronology(createdAt: goal.createdAt, instant: instant)
    let deadlineBoundary = try validatedDeadlineBoundary(
      of: goal,
      calendar: calendar,
      timeZone: timeZone
    )
    let actualProgress = try validatedProgress(progress, for: goalKind)

    if closure != nil {
      return nil
    }

    guard let deadlineBoundary else {
      return GoalStandingSnapshot(
        standing: .onPace,
        actualNormalizedProgress: actualProgress,
        expectedNormalizedProgress: nil,
        deadlineBoundary: nil,
        nextTimeRefresh: nil
      )
    }

    if instant >= deadlineBoundary {
      return GoalStandingSnapshot(
        standing: .pastDue,
        actualNormalizedProgress: actualProgress,
        expectedNormalizedProgress: 1,
        deadlineBoundary: deadlineBoundary,
        nextTimeRefresh: nil
      )
    }

    let totalDuration = deadlineBoundary.timeIntervalSince(goal.createdAt)
    let elapsedDuration = instant.timeIntervalSince(goal.createdAt)
    let expectedProgress = min(max(elapsedDuration / totalDuration, 0), 1)
    let standing: GoalStanding = actualProgress >= expectedProgress ? .onPace : .behind
    let nextTimeRefresh: Date
    if standing == .behind || actualProgress >= 1 {
      nextTimeRefresh = deadlineBoundary
    } else {
      let threshold = goal.createdAt.addingTimeInterval(actualProgress * totalDuration)
      nextTimeRefresh = min(
        max(
          threshold.addingTimeInterval(1),
          instant.addingTimeInterval(1)
        ),
        deadlineBoundary
      )
    }

    return GoalStandingSnapshot(
      standing: standing,
      actualNormalizedProgress: actualProgress,
      expectedNormalizedProgress: expectedProgress,
      deadlineBoundary: deadlineBoundary,
      nextTimeRefresh: nextTimeRefresh
    )
  }

  private func validatedKindAndConfiguration(of goal: Goal) throws -> GoalKind {
    let name = normalized(goal.name)
    guard !name.isEmpty, name == goal.name else {
      throw GoalStandingComputationError.invalidName(goal.name)
    }
    guard goal.target > 0 else {
      throw GoalStandingComputationError.invalidTarget(goal.target)
    }
    let unit = normalized(goal.unit)
    guard !unit.isEmpty, unit == goal.unit else {
      throw GoalStandingComputationError.invalidUnit(goal.unit)
    }
    guard let kind = GoalKind(rawValue: goal.kindRawValue) else {
      throw GoalStandingComputationError.invalidGoalKind(goal.kindRawValue)
    }

    switch kind {
    case .accumulate:
      if let baseline = goal.baseline {
        throw GoalStandingComputationError.invalidAccumulateBaseline(baseline)
      }
    case .measure:
      guard let baseline = goal.baseline else {
        throw GoalStandingComputationError.missingMeasureBaseline
      }
      guard baseline != goal.target else {
        throw GoalStandingComputationError.measureBaselineEqualsTarget(baseline)
      }
    }
    return kind
  }

  private func validatedClosure(of goal: Goal) throws -> GoalClosure? {
    do {
      return try goal.checkedClosure
    } catch GoalClosureError.unsupportedRawValue(let rawValue) {
      throw GoalStandingComputationError.invalidClosure(rawValue)
    }
  }

  private func validateChronology(createdAt: Date, instant: Date) throws {
    guard createdAt.timeIntervalSinceReferenceDate.isFinite else {
      throw GoalStandingComputationError.invalidCreationInstant
    }
    guard instant.timeIntervalSinceReferenceDate.isFinite else {
      throw GoalStandingComputationError.invalidEvaluationInstant
    }
    guard instant >= createdAt else {
      throw GoalStandingComputationError.evaluationBeforeCreation
    }
  }

  private func validatedDeadlineBoundary(
    of goal: Goal,
    calendar _: Calendar,
    timeZone: TimeZone
  ) throws -> Date? {
    guard let deadlineKey = goal.deadlineKey else {
      return nil
    }
    guard let deadline = GoalDate(rawValue: deadlineKey) else {
      throw GoalStandingComputationError.invalidDeadline(deadlineKey)
    }

    let boundary: Date
    do {
      boundary = try deadline.next().start(in: timeZone)
    } catch let error as GoalDateError {
      throw GoalStandingComputationError.invalidDeadlineBoundary(error)
    }
    guard boundary.timeIntervalSinceReferenceDate.isFinite else {
      throw GoalStandingComputationError.invalidDeadlineBoundary(.calendarCalculationFailed)
    }
    guard boundary > goal.createdAt else {
      throw GoalStandingComputationError.deadlineNotAfterCreation
    }
    return boundary
  }

  private func validatedProgress(
    _ progress: GoalProgressSnapshot,
    for expectedKind: GoalKind
  ) throws -> Double {
    let actualKind: GoalKind
    let normalizedProgress: Double
    switch progress {
    case .accumulate(let value):
      actualKind = .accumulate
      normalizedProgress = value.normalizedProgress
    case .measure(let value):
      actualKind = .measure
      normalizedProgress = value.normalizedProgress
    }

    guard actualKind == expectedKind else {
      throw GoalStandingComputationError.progressKindMismatch(
        expected: expectedKind,
        actual: actualKind
      )
    }
    guard normalizedProgress.isFinite else {
      throw GoalStandingComputationError.nonFiniteNormalizedProgress
    }
    guard normalizedProgress >= 0 else {
      throw GoalStandingComputationError.negativeNormalizedProgress(normalizedProgress)
    }
    return normalizedProgress
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
