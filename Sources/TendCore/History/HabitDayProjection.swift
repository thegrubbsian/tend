import Foundation

public enum HabitDayProjectionState: Equatable, Sendable {
  case met
  case missed
  case open
  case grace
  case exempt
  case inactive
  case beforeCreation
  case future
}

public struct HabitDayProjection: Equatable, Sendable {
  public let periodKey: String
  public let periodStart: Date
  public let periodEnd: Date
  public let state: HabitDayProjectionState
  public let progress: Int?
  public let target: Int?
  public let unit: String?
  public let isRequirementMet: Bool?

  public init(
    periodKey: String,
    periodStart: Date,
    periodEnd: Date,
    state: HabitDayProjectionState,
    progress: Int? = nil,
    target: Int? = nil,
    unit: String? = nil,
    isRequirementMet: Bool? = nil
  ) {
    self.periodKey = periodKey
    self.periodStart = periodStart
    self.periodEnd = periodEnd
    self.state = state
    self.progress = progress
    self.target = target
    self.unit = unit
    self.isRequirementMet = isRequirementMet
  }
}

struct HabitDayProjector {
  private let evaluator = BucketEvaluator()

  func project(
    _ period: CalendarBucketPeriod,
    habit: Habit,
    bucket: HabitBucket?,
    activityPeriods: [HabitActivityPeriod],
    creationPeriod: CalendarBucketPeriod,
    instant: Date,
    timeZone: TimeZone
  ) throws -> HabitDayProjection {
    guard let bucket else {
      return try projectMissingBucket(
        period,
        activityPeriods: activityPeriods,
        creationPeriod: creationPeriod,
        instant: instant
      )
    }

    let evaluation = try evaluator.evaluate(
      habit: habit,
      bucket: bucket,
      at: instant,
      timeZone: timeZone
    )
    let state: HabitDayProjectionState
    let progress: Int?
    let target: Int?
    let unit: String?
    let isRequirementMet: Bool?

    switch (evaluation.phase, evaluation.standing) {
    case (.final, .met), (.dueForFinalization, .met):
      state = .met
      progress = try checkedProgress(in: bucket)
      target = evaluation.target
      unit = evaluation.unit
      isRequirementMet = true
    case (.final, .missed), (.dueForFinalization, .missed):
      state = .missed
      progress = try checkedProgress(in: bucket)
      target = evaluation.target
      unit = evaluation.unit
      isRequirementMet = false
    case (.open, .pendingMet), (.open, .pendingUnmet),
      (.grace, .pendingMet), (.grace, .pendingUnmet):
      guard let provisionalProgress = evaluation.progress else {
        throw HabitStreakComputationError.unexpectedBucketState(
          key: bucket.periodKey,
          phase: evaluation.phase,
          standing: evaluation.standing
        )
      }
      state = evaluation.phase == .open ? .open : .grace
      progress = provisionalProgress
      target = evaluation.target
      unit = evaluation.unit
      isRequirementMet = evaluation.standing == .pendingMet
    case (.exempt, .exempt):
      state = .exempt
      progress = nil
      target = nil
      unit = nil
      isRequirementMet = nil
    default:
      throw HabitStreakComputationError.unexpectedBucketState(
        key: bucket.periodKey,
        phase: evaluation.phase,
        standing: evaluation.standing
      )
    }

    return HabitDayProjection(
      periodKey: period.key,
      periodStart: period.start,
      periodEnd: period.end,
      state: state,
      progress: progress,
      target: target,
      unit: unit,
      isRequirementMet: isRequirementMet
    )
  }

  private func projectMissingBucket(
    _ period: CalendarBucketPeriod,
    activityPeriods: [HabitActivityPeriod],
    creationPeriod: CalendarBucketPeriod,
    instant: Date
  ) throws -> HabitDayProjection {
    let state: HabitDayProjectionState
    if instant < period.start {
      state = .future
    } else if period.end <= creationPeriod.start {
      state = .beforeCreation
    } else if activityPeriods.contains(where: { overlaps($0, period: period) }) {
      throw HabitDetailComputationError.missingActiveBucket(period.key)
    } else {
      state = .inactive
    }
    return HabitDayProjection(
      periodKey: period.key,
      periodStart: period.start,
      periodEnd: period.end,
      state: state
    )
  }

  private func checkedProgress(in bucket: HabitBucket) throws -> Int {
    var progress = 0
    for entry in bucket.entries ?? [] {
      guard entry.amount > 0 else {
        throw BucketEvaluationError.invalidEntryAmount(entry.amount)
      }
      let addition = progress.addingReportingOverflow(entry.amount)
      guard !addition.overflow else {
        throw BucketEvaluationError.progressOverflow
      }
      progress = addition.partialValue
    }
    return progress
  }

  private func overlaps(
    _ activityPeriod: HabitActivityPeriod,
    period: CalendarBucketPeriod
  ) -> Bool {
    let activityEnd = activityPeriod.endedAt ?? .distantFuture
    guard activityEnd > activityPeriod.startedAt else { return false }
    return activityPeriod.startedAt < period.end && activityEnd > period.start
  }
}
