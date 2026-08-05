import Foundation
import SwiftData

public struct HabitLoggingEntrySnapshot: Identifiable {
  public let id: PersistentIdentifier
  public let uuid: UUID
  public let timestamp: Date
  public let amount: Int
  public let entry: LogEntry

  public init(
    id: PersistentIdentifier,
    uuid: UUID,
    timestamp: Date,
    amount: Int,
    entry: LogEntry
  ) {
    self.id = id
    self.uuid = uuid
    self.timestamp = timestamp
    self.amount = amount
    self.entry = entry
  }
}

public struct HabitLoggingBucketSnapshot {
  public let periodKey: String
  public let phase: BucketPhase
  public let progress: Int
  public let target: Int
  public let unit: String
  public let isMet: Bool
  public let entries: [HabitLoggingEntrySnapshot]

  public init(
    periodKey: String,
    phase: BucketPhase,
    progress: Int,
    target: Int,
    unit: String,
    isMet: Bool,
    entries: [HabitLoggingEntrySnapshot]
  ) {
    self.periodKey = periodKey
    self.phase = phase
    self.progress = progress
    self.target = target
    self.unit = unit
    self.isMet = isMet
    self.entries = entries
  }
}

public struct HabitLoggingSnapshot {
  public let habitID: PersistentIdentifier
  public let name: String
  public let cadence: HabitCadence
  public let target: Int
  public let unit: String
  public let current: HabitLoggingBucketSnapshot
  public let grace: HabitLoggingBucketSnapshot?

  public init(
    habitID: PersistentIdentifier,
    name: String,
    cadence: HabitCadence,
    target: Int,
    unit: String,
    current: HabitLoggingBucketSnapshot,
    grace: HabitLoggingBucketSnapshot?
  ) {
    self.habitID = habitID
    self.name = name
    self.cadence = cadence
    self.target = target
    self.unit = unit
    self.current = current
    self.grace = grace
  }
}

public enum HabitLoggingComputationError: Error, Equatable, Sendable {
  case detachedHabit
  case inactiveHabit
  case missingCurrentBucket(String)
  case multipleBuckets(String)
  case invalidBucketRelationship(String)
  case invalidEntryRelationship(UUID)
  case unexpectedBucketState(
    key: String,
    phase: BucketPhase,
    standing: BucketStanding
  )
}

@MainActor
public final class HabitLoggingComputation {
  typealias Reconcile = (Habit, Date, TimeZone) throws -> Void

  private let context: ModelContext
  private let reconcile: Reconcile
  private let evaluator = BucketEvaluator()
  private let relationshipValidator: HabitRelationshipValidator

  public init(context: ModelContext) {
    let reconciler = BucketReconciler(context: context)
    self.context = context
    reconcile = { habit, instant, timeZone in
      try reconciler.reconcile(
        habit: habit,
        at: instant,
        timeZone: timeZone
      )
    }
    relationshipValidator = HabitRelationshipValidator(context: context)
  }

  init(context: ModelContext, save: @escaping () throws -> Void) {
    let reconciler = BucketReconciler(context: context, save: save)
    self.context = context
    reconcile = { habit, instant, timeZone in
      try reconciler.reconcile(
        habit: habit,
        at: instant,
        timeZone: timeZone
      )
    }
    relationshipValidator = HabitRelationshipValidator(context: context)
  }

  init(
    context: ModelContext,
    reconcile: @escaping Reconcile
  ) {
    self.context = context
    self.reconcile = reconcile
    relationshipValidator = HabitRelationshipValidator(context: context)
  }

  public func snapshot(
    for habit: Habit,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> HabitLoggingSnapshot {
    guard relationshipValidator.isPersisted(habit) else {
      throw HabitLoggingComputationError.detachedHabit
    }
    guard habit.isActive else {
      throw HabitLoggingComputationError.inactiveHabit
    }
    guard let cadence = HabitCadence(rawValue: habit.cadenceRawValue) else {
      throw BucketEvaluationError.unsupportedCadence(habit.cadenceRawValue)
    }
    guard habit.target > 0 else {
      throw BucketEvaluationError.invalidRequirement(habit.target)
    }

    try validateGraph(for: habit)
    try reconcile(habit, instant, timeZone)

    let schedule = CalendarBucketSchedule(timeZone: timeZone)
    let currentPeriod = try schedule.period(containing: instant, cadence: cadence)
    let currentBucket = try requiredBucket(
      for: habit,
      periodKey: currentPeriod.key
    )
    try validate(currentBucket, for: habit)
    let currentEvaluation = try evaluator.evaluate(
      habit: habit,
      bucket: currentBucket,
      at: instant,
      timeZone: timeZone
    )
    let current = try bucketSnapshot(
      bucket: currentBucket,
      evaluation: currentEvaluation,
      expectedPhase: .open
    )

    let previousInstant = currentPeriod.start.addingTimeInterval(-1)
    let previousPeriod = try schedule.period(containing: previousInstant, cadence: cadence)
    let grace: HabitLoggingBucketSnapshot?
    if let previousBucket = try optionalBucket(
      for: habit,
      periodKey: previousPeriod.key
    ) {
      try validate(previousBucket, for: habit)
      let previousEvaluation = try evaluator.evaluate(
        habit: habit,
        bucket: previousBucket,
        at: instant,
        timeZone: timeZone
      )
      if previousEvaluation.phase == .grace {
        grace = try bucketSnapshot(
          bucket: previousBucket,
          evaluation: previousEvaluation,
          expectedPhase: .grace
        )
      } else {
        grace = nil
      }
    } else {
      grace = nil
    }

    return HabitLoggingSnapshot(
      habitID: habit.persistentModelID,
      name: habit.name,
      cadence: cadence,
      target: habit.target,
      unit: habit.unit,
      current: current,
      grace: grace
    )
  }

  private func requiredBucket(
    for habit: Habit,
    periodKey: String
  ) throws -> HabitBucket {
    let buckets = try buckets(for: habit, periodKey: periodKey)
    guard !buckets.isEmpty else {
      throw HabitLoggingComputationError.missingCurrentBucket(periodKey)
    }
    guard buckets.count == 1, let bucket = buckets.first else {
      throw HabitLoggingComputationError.multipleBuckets(periodKey)
    }
    return bucket
  }

  private func optionalBucket(
    for habit: Habit,
    periodKey: String
  ) throws -> HabitBucket? {
    let buckets = try buckets(for: habit, periodKey: periodKey)
    guard buckets.count <= 1 else {
      throw HabitLoggingComputationError.multipleBuckets(periodKey)
    }
    return buckets.first
  }

  private func buckets(
    for habit: Habit,
    periodKey: String
  ) throws -> [HabitBucket] {
    let habitIdentifier = habit.persistentModelID
    let descriptor = FetchDescriptor<HabitBucket>(
      predicate: #Predicate<HabitBucket> { bucket in
        bucket.habit?.persistentModelID == habitIdentifier
          && bucket.periodKey == periodKey
      })
    return try context.fetch(descriptor)
  }

  private func bucketSnapshot(
    bucket: HabitBucket,
    evaluation: BucketEvaluation,
    expectedPhase: BucketPhase
  ) throws -> HabitLoggingBucketSnapshot {
    guard evaluation.phase == expectedPhase,
      let progress = evaluation.progress,
      evaluation.standing == .pendingMet || evaluation.standing == .pendingUnmet
    else {
      throw HabitLoggingComputationError.unexpectedBucketState(
        key: bucket.periodKey,
        phase: evaluation.phase,
        standing: evaluation.standing
      )
    }
    let entries = (bucket.entries ?? [])
      .sorted { first, second in
        if first.timestamp != second.timestamp {
          return first.timestamp > second.timestamp
        }
        return first.persistentModelID < second.persistentModelID
      }
      .map {
        HabitLoggingEntrySnapshot(
          id: $0.persistentModelID,
          uuid: $0.id,
          timestamp: $0.timestamp,
          amount: $0.amount,
          entry: $0
        )
      }
    return HabitLoggingBucketSnapshot(
      periodKey: bucket.periodKey,
      phase: evaluation.phase,
      progress: progress,
      target: evaluation.target,
      unit: evaluation.unit,
      isMet: evaluation.standing == .pendingMet,
      entries: entries
    )
  }

  private func validateGraph(for habit: Habit) throws {
    do {
      try relationshipValidator.validateGraph(for: habit)
    } catch let error as HabitRelationshipValidationError {
      throw computationError(from: error)
    }
  }

  private func validate(_ bucket: HabitBucket, for habit: Habit) throws {
    do {
      try relationshipValidator.validate(bucket, for: habit)
    } catch let error as HabitRelationshipValidationError {
      throw computationError(from: error)
    }
  }

  private func computationError(
    from error: HabitRelationshipValidationError
  ) -> HabitLoggingComputationError {
    switch error {
    case .invalidBucketRelationship(let periodKey):
      .invalidBucketRelationship(periodKey)
    case .invalidEntryRelationship(let id):
      .invalidEntryRelationship(id)
    }
  }
}
