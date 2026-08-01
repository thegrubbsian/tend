import Foundation

public enum BucketPhase: Equatable, Sendable {
  case open
  case grace
  case dueForFinalization
  case final
  case exempt
}

public enum BucketStanding: Equatable, Sendable {
  case pendingMet
  case pendingUnmet
  case met
  case missed
  case exempt
}

public struct BucketFinalization: Equatable, Sendable {
  public let targetSnapshot: Int
  public let unitSnapshot: String
  public let verdict: BucketVerdict
  public let finalizedAt: Date
}

public struct BucketEvaluation: Equatable, Sendable {
  public let progress: Int?
  public let target: Int
  public let unit: String
  public let phase: BucketPhase
  public let standing: BucketStanding
  public let period: CalendarBucketPeriod?
  public let finalization: BucketFinalization?
}

public enum BucketEvaluationError: Error, Equatable, Sendable {
  case unsupportedCadence(String)
  case cadenceMismatch(habit: HabitCadence, bucket: HabitCadence)
  case periodCadenceMismatch(key: String, cadence: HabitCadence)
  case calendar(CalendarBucketScheduleError)
  case invalidRequirement(Int)
  case invalidEntryAmount(Int)
  case progressOverflow
  case partialFinality
  case exemptFinalityConflict
  case unsupportedVerdict(String)
}

public struct BucketEvaluator: Sendable {
  public init() {}

  public func evaluate(
    habit: Habit,
    bucket: HabitBucket,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> BucketEvaluation {
    if let finalization = try settledFinalization(from: bucket) {
      return BucketEvaluation(
        progress: nil,
        target: finalization.targetSnapshot,
        unit: finalization.unitSnapshot,
        phase: .final,
        standing: standing(for: finalization.verdict),
        period: nil,
        finalization: finalization
      )
    }

    guard habit.target > 0 else {
      throw BucketEvaluationError.invalidRequirement(habit.target)
    }
    let habitCadence = try cadence(from: habit.cadenceRawValue)
    let bucketCadence = try cadence(from: bucket.cadenceRawValue)
    guard habitCadence == bucketCadence else {
      throw BucketEvaluationError.cadenceMismatch(
        habit: habitCadence,
        bucket: bucketCadence
      )
    }

    let period: CalendarBucketPeriod
    do {
      period = try CalendarBucketSchedule(timeZone: timeZone).period(
        forKey: bucket.periodKey
      )
    } catch let error as CalendarBucketScheduleError {
      throw BucketEvaluationError.calendar(error)
    }
    guard period.cadence == bucketCadence else {
      throw BucketEvaluationError.periodCadenceMismatch(
        key: bucket.periodKey,
        cadence: bucketCadence
      )
    }

    let progress = try checkedProgress(in: bucket)
    if bucket.isExempt {
      return BucketEvaluation(
        progress: progress,
        target: habit.target,
        unit: habit.unit,
        phase: .exempt,
        standing: .exempt,
        period: period,
        finalization: nil
      )
    }

    if instant < period.end {
      return provisionalEvaluation(
        progress: progress,
        habit: habit,
        phase: .open,
        period: period
      )
    }
    if instant < period.graceEnd {
      return provisionalEvaluation(
        progress: progress,
        habit: habit,
        phase: .grace,
        period: period
      )
    }

    let verdict: BucketVerdict = progress >= habit.target ? .met : .missed
    let finalization = BucketFinalization(
      targetSnapshot: habit.target,
      unitSnapshot: habit.unit,
      verdict: verdict,
      finalizedAt: period.graceEnd
    )
    return BucketEvaluation(
      progress: progress,
      target: habit.target,
      unit: habit.unit,
      phase: .dueForFinalization,
      standing: standing(for: verdict),
      period: period,
      finalization: finalization
    )
  }

  private func settledFinalization(from bucket: HabitBucket) throws
    -> BucketFinalization?
  {
    let hasAnyFinalFact =
      bucket.finalizedAt != nil || bucket.verdictRawValue != nil
      || bucket.targetSnapshot != nil || bucket.unitSnapshot != nil
    if bucket.isExempt && hasAnyFinalFact {
      throw BucketEvaluationError.exemptFinalityConflict
    }

    switch (
      bucket.finalizedAt,
      bucket.verdictRawValue,
      bucket.targetSnapshot,
      bucket.unitSnapshot
    ) {
    case (nil, nil, nil, nil):
      return nil
    case (let finalizedAt?, let verdictRawValue?, let targetSnapshot?, let unitSnapshot?):
      guard let verdict = BucketVerdict(rawValue: verdictRawValue) else {
        throw BucketEvaluationError.unsupportedVerdict(verdictRawValue)
      }
      guard targetSnapshot > 0 else {
        throw BucketEvaluationError.invalidRequirement(targetSnapshot)
      }
      return BucketFinalization(
        targetSnapshot: targetSnapshot,
        unitSnapshot: unitSnapshot,
        verdict: verdict,
        finalizedAt: finalizedAt
      )
    default:
      throw BucketEvaluationError.partialFinality
    }
  }

  private func cadence(from rawValue: String) throws -> HabitCadence {
    guard let cadence = HabitCadence(rawValue: rawValue) else {
      throw BucketEvaluationError.unsupportedCadence(rawValue)
    }
    return cadence
  }

  private func checkedProgress(in bucket: HabitBucket) throws -> Int {
    guard let entries = bucket.entries else {
      return 0
    }

    var invalidAmount: Int?
    for entry in entries where entry.amount <= 0 {
      invalidAmount = min(invalidAmount ?? entry.amount, entry.amount)
    }
    if let invalidAmount {
      throw BucketEvaluationError.invalidEntryAmount(invalidAmount)
    }

    var progress = 0
    for entry in entries {
      let addition = progress.addingReportingOverflow(entry.amount)
      guard !addition.overflow else {
        throw BucketEvaluationError.progressOverflow
      }
      progress = addition.partialValue
    }
    return progress
  }

  private func provisionalEvaluation(
    progress: Int,
    habit: Habit,
    phase: BucketPhase,
    period: CalendarBucketPeriod
  ) -> BucketEvaluation {
    BucketEvaluation(
      progress: progress,
      target: habit.target,
      unit: habit.unit,
      phase: phase,
      standing: progress >= habit.target ? .pendingMet : .pendingUnmet,
      period: period,
      finalization: nil
    )
  }

  private func standing(for verdict: BucketVerdict) -> BucketStanding {
    switch verdict {
    case .met:
      .met
    case .missed:
      .missed
    }
  }
}
