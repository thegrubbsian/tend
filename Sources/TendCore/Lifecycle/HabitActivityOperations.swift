import Foundation
import SwiftData

public enum HabitActivityOperationError: Error, Equatable, Sendable {
  case detachedHabit
  case alreadyInactive
  case missingOpenActivityPeriod
  case multipleOpenActivityPeriods
  case invalidActivityChronology
  case duplicatePeriodKey(String)
  case unexpectedBucketPhase(key: String, phase: BucketPhase)
}

@MainActor
public final class HabitActivityOperations {
  private let context: ModelContext
  private let reconciler: BucketReconciler
  private let evaluator = BucketEvaluator()
  private let saveContext: () throws -> Void

  public init(context: ModelContext) {
    self.context = context
    reconciler = BucketReconciler(context: context)
    saveContext = { try context.save() }
  }

  init(context: ModelContext, save: @escaping () throws -> Void) {
    self.context = context
    reconciler = BucketReconciler(context: context)
    saveContext = save
  }

  public func deactivate(
    _ habit: Habit,
    at instant: Date,
    timeZone: TimeZone
  ) throws {
    guard isPersisted(habit) else {
      throw HabitActivityOperationError.detachedHabit
    }
    guard habit.isActive else {
      throw HabitActivityOperationError.alreadyInactive
    }
    let openActivityPeriod = try validatedOpenActivityPeriod(
      for: habit,
      at: instant
    )
    try validateUniquePeriodKeys(in: buckets(for: habit))

    try reconciler.reconcile(habit: habit, at: instant, timeZone: timeZone)

    guard let cadence = HabitCadence(rawValue: habit.cadenceRawValue) else {
      throw BucketEvaluationError.unsupportedCadence(habit.cadenceRawValue)
    }
    let currentPeriod = try CalendarBucketSchedule(timeZone: timeZone).period(
      containing: instant,
      cadence: cadence
    )
    let persistedBuckets = try buckets(for: habit)
    try validateUniquePeriodKeys(in: persistedBuckets)
    var bucketsToExempt: [HabitBucket] = []
    bucketsToExempt.reserveCapacity(persistedBuckets.count)
    for bucket in persistedBuckets {
      let evaluation = try evaluator.evaluate(
        habit: habit,
        bucket: bucket,
        at: instant,
        timeZone: timeZone
      )
      switch evaluation.phase {
      case .final:
        continue
      case .exempt where bucket.periodKey != currentPeriod.key:
        continue
      case .exempt:
        throw HabitActivityOperationError.unexpectedBucketPhase(
          key: bucket.periodKey,
          phase: evaluation.phase
        )
      case .open where bucket.periodKey == currentPeriod.key:
        bucketsToExempt.append(bucket)
      case .grace:
        bucketsToExempt.append(bucket)
      case .open, .dueForFinalization:
        throw HabitActivityOperationError.unexpectedBucketPhase(
          key: bucket.periodKey,
          phase: evaluation.phase
        )
      }
    }

    let exemptionSnapshots = bucketsToExempt.map { ($0, $0.isExempt) }
    let activityEndSnapshot = openActivityPeriod.endedAt
    let activeSnapshot = habit.isActive
    do {
      for bucket in bucketsToExempt {
        bucket.isExempt = true
      }
      openActivityPeriod.endedAt = instant
      habit.isActive = false
      try saveContext()
    } catch {
      for (bucket, wasExempt) in exemptionSnapshots {
        bucket.isExempt = wasExempt
      }
      openActivityPeriod.endedAt = activityEndSnapshot
      habit.isActive = activeSnapshot
      context.rollback()
      throw error
    }
  }

  private func validatedOpenActivityPeriod(
    for habit: Habit,
    at instant: Date
  ) throws -> HabitActivityPeriod {
    let activityPeriods = habit.activityPeriods ?? []
    var openActivityPeriod: HabitActivityPeriod?
    let habitIdentifier = habit.persistentModelID
    for activityPeriod in activityPeriods {
      guard isPersisted(activityPeriod),
        activityPeriod.habit?.persistentModelID == habitIdentifier
      else {
        throw HabitActivityOperationError.invalidActivityChronology
      }
      if let endedAt = activityPeriod.endedAt {
        guard endedAt >= activityPeriod.startedAt else {
          throw HabitActivityOperationError.invalidActivityChronology
        }
      } else {
        guard openActivityPeriod == nil else {
          throw HabitActivityOperationError.multipleOpenActivityPeriods
        }
        openActivityPeriod = activityPeriod
      }
    }
    guard let openActivityPeriod else {
      throw HabitActivityOperationError.missingOpenActivityPeriod
    }

    let orderedPeriods = activityPeriods.sorted { first, second in
      if first.startedAt != second.startedAt {
        return first.startedAt < second.startedAt
      }
      switch (first.endedAt, second.endedAt) {
      case (let firstEnd?, let secondEnd?):
        return firstEnd < secondEnd
      case (_?, nil):
        return true
      case (nil, _?):
        return false
      case (nil, nil):
        return false
      }
    }
    var previousEnd: Date?
    var reachedOpenPeriod = false
    for activityPeriod in orderedPeriods {
      guard !reachedOpenPeriod else {
        throw HabitActivityOperationError.invalidActivityChronology
      }
      if let previousEnd {
        guard activityPeriod.startedAt >= previousEnd else {
          throw HabitActivityOperationError.invalidActivityChronology
        }
      }
      if let endedAt = activityPeriod.endedAt {
        previousEnd = endedAt
      } else {
        reachedOpenPeriod = true
      }
    }
    guard openActivityPeriod.startedAt <= instant else {
      throw HabitActivityOperationError.invalidActivityChronology
    }
    return openActivityPeriod
  }

  private func validateUniquePeriodKeys(in buckets: [HabitBucket]) throws {
    var keys: Set<String> = []
    keys.reserveCapacity(buckets.count)
    var duplicateKey: String?
    for bucket in buckets where !keys.insert(bucket.periodKey).inserted {
      duplicateKey = min(duplicateKey ?? bucket.periodKey, bucket.periodKey)
    }
    if let duplicateKey {
      throw HabitActivityOperationError.duplicatePeriodKey(duplicateKey)
    }
  }

  private func buckets(for habit: Habit) throws -> [HabitBucket] {
    let habitIdentifier = habit.persistentModelID
    return try context.fetch(
      FetchDescriptor<HabitBucket>(
        predicate: #Predicate<HabitBucket> { bucket in
          bucket.habit?.persistentModelID == habitIdentifier
        },
        sortBy: [SortDescriptor(\.periodKey)]
      ))
  }

  private func isPersisted<T>(_ model: T) -> Bool where T: PersistentModel {
    model.modelContext == context && model.persistentModelID.storeIdentifier != nil
      && !model.isDeleted
  }
}
