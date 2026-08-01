import Foundation
import SwiftData

@MainActor
public final class HabitStreakComputation {
  private let context: ModelContext
  private let reconciler: BucketReconciler
  private let evaluator = BucketEvaluator()
  private let calculator = StreakCalculator()
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

  public func compute(
    habit: Habit,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> HabitStreakState {
    guard isPersisted(habit) else {
      throw HabitStreakComputationError.detachedHabit
    }
    guard let cadence = HabitCadence(rawValue: habit.cadenceRawValue) else {
      throw BucketEvaluationError.unsupportedCadence(habit.cadenceRawValue)
    }
    guard habit.target > 0 else {
      throw BucketEvaluationError.invalidRequirement(habit.target)
    }
    guard habit.bestStreak >= 0 else {
      throw HabitStreakComputationError.invalidBestStreak(habit.bestStreak)
    }

    if habit.isActive {
      try reconciler.reconcile(habit: habit, at: instant, timeZone: timeZone)
    }

    var persistedBuckets = try buckets(for: habit)
    try validateUniquePeriodKeys(in: persistedBuckets)
    persistedBuckets.sort {
      if $0.startAt != $1.startAt {
        return $0.startAt < $1.startAt
      }
      if $0.endAt != $1.endAt {
        return $0.endAt < $1.endAt
      }
      return $0.periodKey < $1.periodKey
    }

    var states: [StreakBucketState] = []
    states.reserveCapacity(persistedBuckets.count)
    for bucket in persistedBuckets {
      let evaluation = try evaluator.evaluate(
        habit: habit,
        bucket: bucket,
        at: instant,
        timeZone: timeZone
      )
      states.append(
        StreakBucketState(
          key: bucket.periodKey,
          phase: evaluation.phase,
          standing: evaluation.standing
        ))
    }

    let calculation = try calculator.calculate(
      cadence: cadence,
      persistedBest: habit.bestStreak,
      buckets: states
    )
    if calculation.derivedFinalizedBest > habit.bestStreak {
      let previousBest = habit.bestStreak
      habit.bestStreak = calculation.derivedFinalizedBest
      do {
        try saveContext()
      } catch {
        habit.bestStreak = previousBest
        context.rollback()
        throw error
      }
    }
    return calculation.state
  }

  private func buckets(for habit: Habit) throws -> [HabitBucket] {
    let habitIdentifier = habit.persistentModelID
    return try context.fetch(
      FetchDescriptor<HabitBucket>(
        predicate: #Predicate<HabitBucket> { bucket in
          bucket.habit?.persistentModelID == habitIdentifier
        }
      ))
  }

  private func validateUniquePeriodKeys(in buckets: [HabitBucket]) throws {
    var keys: Set<String> = []
    keys.reserveCapacity(buckets.count)
    var duplicateKey: String?
    for bucket in buckets where !keys.insert(bucket.periodKey).inserted {
      duplicateKey = min(duplicateKey ?? bucket.periodKey, bucket.periodKey)
    }
    if let duplicateKey {
      throw HabitStreakComputationError.duplicatePeriodKey(duplicateKey)
    }
  }

  private func isPersisted<T>(_ model: T) -> Bool where T: PersistentModel {
    model.modelContext == context && model.persistentModelID.storeIdentifier != nil
      && !model.isDeleted
  }
}
