import Foundation
import SwiftData

public enum BucketReconciliationError: Error, Equatable, Sendable {
  case missingOpenActivityPeriod
  case multipleOpenActivityPeriods
  case instantBeforeActivityStart
  case duplicatePeriodKey(String)
  case missingFinalizationCandidate(String)
  case nonAdvancingCalendarPeriod(String)
}

@MainActor
public final class BucketReconciler {
  private let context: ModelContext
  private let saveContext: () throws -> Void
  private let evaluator = BucketEvaluator()

  public init(context: ModelContext) {
    self.context = context
    saveContext = { try context.save() }
  }

  init(context: ModelContext, save: @escaping () throws -> Void) {
    self.context = context
    saveContext = save
  }

  /// Reconciles before a caller changes the habit's target, unit, entries, or
  /// activity state, so elapsed buckets freeze the facts in force at finality.
  public func reconcile(
    habit: Habit,
    at instant: Date,
    timeZone: TimeZone
  ) throws {
    guard habit.isActive else {
      return
    }

    let activityPeriod = try openActivityPeriod(for: habit)
    guard activityPeriod.startedAt <= instant else {
      throw BucketReconciliationError.instantBeforeActivityStart
    }
    guard let cadence = HabitCadence(rawValue: habit.cadenceRawValue) else {
      throw BucketEvaluationError.unsupportedCadence(habit.cadenceRawValue)
    }
    guard habit.target > 0 else {
      throw BucketEvaluationError.invalidRequirement(habit.target)
    }

    let existingBuckets = try fetchBuckets(for: habit)
    var bucketsByKey = try indexByPeriodKey(existingBuckets)
    let schedule = CalendarBucketSchedule(timeZone: timeZone)
    var mutations: [PlannedBucketMutation] = []
    mutations.reserveCapacity(existingBuckets.count)

    for bucket in existingBuckets {
      try validateIdentity(
        of: bucket,
        habitCadence: cadence,
        schedule: schedule
      )
      if let mutation = try plannedMutation(
        for: bucket,
        habit: habit,
        instant: instant,
        timeZone: timeZone,
        isCreation: false
      ) {
        mutations.append(mutation)
      }
    }

    var period = try schedule.period(
      containing: activityPeriod.startedAt,
      cadence: cadence
    )
    let finalPeriod = try schedule.period(containing: instant, cadence: cadence)
    while period.start <= finalPeriod.start {
      if bucketsByKey[period.key] == nil {
        let bucket = HabitBucket(
          periodKey: period.key,
          startAt: period.start,
          endAt: period.end,
          cadence: cadence
        )
        let mutation = try plannedMutation(
          for: bucket,
          habit: habit,
          instant: instant,
          timeZone: timeZone,
          isCreation: true
        )
        guard let mutation else {
          throw BucketReconciliationError.missingFinalizationCandidate(period.key)
        }
        mutations.append(mutation)
        bucketsByKey[period.key] = bucket
      }

      if period.key == finalPeriod.key {
        break
      }
      let next = try schedule.next(after: period)
      guard next.start > period.start else {
        throw BucketReconciliationError.nonAdvancingCalendarPeriod(period.key)
      }
      period = next
    }

    guard !mutations.isEmpty else {
      return
    }

    do {
      for mutation in mutations {
        apply(mutation, to: habit)
      }
      try saveContext()
    } catch {
      for mutation in mutations where mutation.isCreation {
        mutation.bucket.habit = nil
      }
      context.rollback()
      throw error
    }
  }

  private func openActivityPeriod(for habit: Habit) throws -> HabitActivityPeriod {
    var openPeriod: HabitActivityPeriod?
    if let activityPeriods = habit.activityPeriods {
      for activityPeriod in activityPeriods where activityPeriod.endedAt == nil {
        guard openPeriod == nil else {
          throw BucketReconciliationError.multipleOpenActivityPeriods
        }
        openPeriod = activityPeriod
      }
    }
    guard let openPeriod else {
      throw BucketReconciliationError.missingOpenActivityPeriod
    }
    return openPeriod
  }

  private func fetchBuckets(for habit: Habit) throws -> [HabitBucket] {
    let habitIdentifier = habit.persistentModelID
    let descriptor = FetchDescriptor<HabitBucket>(
      predicate: #Predicate<HabitBucket> { bucket in
        bucket.habit?.persistentModelID == habitIdentifier
      },
      sortBy: [SortDescriptor(\HabitBucket.periodKey)]
    )
    return try context.fetch(descriptor)
  }

  private func indexByPeriodKey(_ buckets: [HabitBucket]) throws
    -> [String: HabitBucket]
  {
    var bucketsByKey: [String: HabitBucket] = [:]
    bucketsByKey.reserveCapacity(buckets.count)
    var duplicateKey: String?
    for bucket in buckets {
      if bucketsByKey.updateValue(bucket, forKey: bucket.periodKey) != nil {
        duplicateKey = min(duplicateKey ?? bucket.periodKey, bucket.periodKey)
      }
    }
    if let duplicateKey {
      throw BucketReconciliationError.duplicatePeriodKey(duplicateKey)
    }
    return bucketsByKey
  }

  private func validateIdentity(
    of bucket: HabitBucket,
    habitCadence: HabitCadence,
    schedule: CalendarBucketSchedule
  ) throws {
    guard let bucketCadence = HabitCadence(rawValue: bucket.cadenceRawValue)
    else {
      throw BucketEvaluationError.unsupportedCadence(bucket.cadenceRawValue)
    }
    guard habitCadence == bucketCadence else {
      throw BucketEvaluationError.cadenceMismatch(
        habit: habitCadence,
        bucket: bucketCadence
      )
    }

    let period: CalendarBucketPeriod
    do {
      period = try schedule.period(forKey: bucket.periodKey)
    } catch let error as CalendarBucketScheduleError {
      throw BucketEvaluationError.calendar(error)
    }
    guard period.cadence == bucketCadence else {
      throw BucketEvaluationError.periodCadenceMismatch(
        key: bucket.periodKey,
        cadence: bucketCadence
      )
    }
  }

  private func plannedMutation(
    for bucket: HabitBucket,
    habit: Habit,
    instant: Date,
    timeZone: TimeZone,
    isCreation: Bool
  ) throws -> PlannedBucketMutation? {
    let evaluation = try evaluator.evaluate(
      habit: habit,
      bucket: bucket,
      at: instant,
      timeZone: timeZone
    )
    switch evaluation.phase {
    case .final, .exempt:
      return nil
    case .open, .grace, .dueForFinalization:
      guard let period = evaluation.period else {
        throw BucketReconciliationError.nonAdvancingCalendarPeriod(bucket.periodKey)
      }
      let finalization: BucketFinalization?
      if evaluation.phase == .dueForFinalization {
        guard let candidate = evaluation.finalization else {
          throw BucketReconciliationError.missingFinalizationCandidate(bucket.periodKey)
        }
        finalization = candidate
      } else {
        finalization = nil
      }

      let boundariesChanged =
        bucket.startAt != period.start || bucket.endAt != period.end
      guard isCreation || boundariesChanged || finalization != nil else {
        return nil
      }
      return PlannedBucketMutation(
        bucket: bucket,
        period: period,
        finalization: finalization,
        isCreation: isCreation
      )
    }
  }

  private func apply(_ mutation: PlannedBucketMutation, to habit: Habit) {
    if mutation.isCreation {
      context.insert(mutation.bucket)
      mutation.bucket.habit = habit
    }
    mutation.bucket.startAt = mutation.period.start
    mutation.bucket.endAt = mutation.period.end
    if let finalization = mutation.finalization {
      mutation.bucket.finalizedAt = finalization.finalizedAt
      mutation.bucket.verdictRawValue = finalization.verdict.rawValue
      mutation.bucket.targetSnapshot = finalization.targetSnapshot
      mutation.bucket.unitSnapshot = finalization.unitSnapshot
    }
  }
}

private struct PlannedBucketMutation {
  let bucket: HabitBucket
  let period: CalendarBucketPeriod
  let finalization: BucketFinalization?
  let isCreation: Bool
}
