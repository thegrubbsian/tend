import Foundation
import SwiftData

public struct HabitTodaySnapshot: Equatable, Sendable {
  public let periodKey: String
  public let progress: Int
  public let target: Int
  public let unit: String
  public let cadence: HabitCadence
  public let currentStreak: Int
  public let isAtRisk: Bool
  public let isMet: Bool

  public init(
    periodKey: String,
    progress: Int,
    target: Int,
    unit: String,
    cadence: HabitCadence,
    currentStreak: Int,
    isAtRisk: Bool,
    isMet: Bool
  ) {
    self.periodKey = periodKey
    self.progress = progress
    self.target = target
    self.unit = unit
    self.cadence = cadence
    self.currentStreak = currentStreak
    self.isAtRisk = isAtRisk
    self.isMet = isMet
  }
}

public enum HabitTodayComputationError: Error, Equatable, Sendable {
  case inactiveHabit
  case missingCurrentBucket(String)
  case multipleCurrentBuckets(String)
  case invalidBucketRelationship(String)
  case invalidEntryRelationship(UUID)
  case unexpectedCurrentBucketState(
    key: String,
    phase: BucketPhase,
    standing: BucketStanding
  )
}

@MainActor
public final class HabitTodayComputation {
  typealias Reconcile = (Habit, Date, TimeZone) throws -> Void
  typealias ComputeStreak = (Habit, Date, TimeZone) throws -> HabitStreakState

  private let context: ModelContext
  private let reconcile: Reconcile
  private let computeStreak: ComputeStreak
  private let evaluator = BucketEvaluator()

  public init(context: ModelContext) {
    let reconciler = BucketReconciler(context: context)
    let streakComputation = HabitStreakComputation(context: context)
    self.context = context
    reconcile = { habit, instant, timeZone in
      try reconciler.reconcile(
        habit: habit,
        at: instant,
        timeZone: timeZone
      )
    }
    computeStreak = { habit, instant, timeZone in
      try streakComputation.compute(
        habit: habit,
        at: instant,
        timeZone: timeZone
      )
    }
  }

  init(context: ModelContext, save: @escaping () throws -> Void) {
    let reconciler = BucketReconciler(context: context, save: save)
    let streakComputation = HabitStreakComputation(context: context, save: save)
    self.context = context
    reconcile = { habit, instant, timeZone in
      try reconciler.reconcile(
        habit: habit,
        at: instant,
        timeZone: timeZone
      )
    }
    computeStreak = { habit, instant, timeZone in
      try streakComputation.compute(
        habit: habit,
        at: instant,
        timeZone: timeZone
      )
    }
  }

  init(
    context: ModelContext,
    reconcile: @escaping Reconcile = { _, _, _ in },
    computeStreak: @escaping ComputeStreak
  ) {
    self.context = context
    self.reconcile = reconcile
    self.computeStreak = computeStreak
  }

  public func snapshot(
    for habit: Habit,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> HabitTodaySnapshot {
    guard isPersisted(habit) else {
      throw HabitStreakComputationError.detachedHabit
    }
    guard habit.isActive else {
      throw HabitTodayComputationError.inactiveHabit
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

    try validateRelationships(for: habit)
    // Validate the current projection before streak computation can persist a
    // better best streak. Its second reconciliation is then idempotent.
    try reconcile(habit, instant, timeZone)
    let currentPeriod = try CalendarBucketSchedule(timeZone: timeZone).period(
      containing: instant,
      cadence: cadence
    )
    let current = try currentBucket(
      for: habit,
      periodKey: currentPeriod.key
    )
    try validateCurrentRelationships(current, for: habit)
    let evaluation = try evaluator.evaluate(
      habit: habit,
      bucket: current,
      at: instant,
      timeZone: timeZone
    )

    let isMet: Bool
    switch (evaluation.phase, evaluation.standing) {
    case (.open, .pendingMet):
      isMet = true
    case (.open, .pendingUnmet):
      isMet = false
    default:
      throw HabitTodayComputationError.unexpectedCurrentBucketState(
        key: currentPeriod.key,
        phase: evaluation.phase,
        standing: evaluation.standing
      )
    }
    guard let progress = evaluation.progress else {
      throw HabitTodayComputationError.unexpectedCurrentBucketState(
        key: currentPeriod.key,
        phase: evaluation.phase,
        standing: evaluation.standing
      )
    }
    let streak = try computeStreak(habit, instant, timeZone)

    return HabitTodaySnapshot(
      periodKey: currentPeriod.key,
      progress: progress,
      target: evaluation.target,
      unit: evaluation.unit,
      cadence: cadence,
      currentStreak: streak.currentStreak,
      isAtRisk: streak.isAtRisk,
      isMet: isMet
    )
  }

  private func currentBucket(
    for habit: Habit,
    periodKey: String
  ) throws -> HabitBucket {
    let habitIdentifier = habit.persistentModelID
    let descriptor = FetchDescriptor<HabitBucket>(
      predicate: #Predicate<HabitBucket> { bucket in
        bucket.habit?.persistentModelID == habitIdentifier
          && bucket.periodKey == periodKey
      })
    let buckets = try context.fetch(descriptor)
    guard !buckets.isEmpty else {
      throw HabitTodayComputationError.missingCurrentBucket(periodKey)
    }
    guard buckets.count == 1, let bucket = buckets.first else {
      throw HabitTodayComputationError.multipleCurrentBuckets(periodKey)
    }
    return bucket
  }

  private func validateRelationships(for habit: Habit) throws {
    let habitIdentifier = habit.persistentModelID
    let bucketDescriptor = FetchDescriptor<HabitBucket>(
      predicate: #Predicate<HabitBucket> { bucket in
        bucket.habit?.persistentModelID == habitIdentifier
      })
    var buckets = try context.fetch(bucketDescriptor)
    var bucketIdentifiers = Set(buckets.map(\.persistentModelID))
    for bucket in habit.buckets ?? []
    where bucketIdentifiers.insert(bucket.persistentModelID).inserted {
      buckets.append(bucket)
    }
    buckets.sort { first, second in
      if first.periodKey != second.periodKey {
        return first.periodKey < second.periodKey
      }
      return uuidPrecedes(first.id, second.id)
    }
    for bucket in buckets {
      guard isPersisted(bucket),
        bucket.habit?.persistentModelID == habitIdentifier
      else {
        throw HabitTodayComputationError.invalidBucketRelationship(bucket.periodKey)
      }
    }

    let entryDescriptor = FetchDescriptor<LogEntry>(
      predicate: #Predicate<LogEntry> { entry in
        entry.habit?.persistentModelID == habitIdentifier
      })
    var entries = try context.fetch(entryDescriptor)
    var entryIdentifiers = Set(entries.map(\.persistentModelID))
    for entry in habit.entries ?? []
    where entryIdentifiers.insert(entry.persistentModelID).inserted {
      entries.append(entry)
    }
    for bucket in buckets {
      for entry in bucket.entries ?? []
      where entryIdentifiers.insert(entry.persistentModelID).inserted {
        entries.append(entry)
      }
    }
    entries.sort { uuidPrecedes($0.id, $1.id) }
    for entry in entries {
      try validateEntry(
        entry,
        habitIdentifier: habitIdentifier,
        bucketIdentifiers: bucketIdentifiers
      )
    }
  }

  private func validateCurrentRelationships(
    _ bucket: HabitBucket,
    for habit: Habit
  ) throws {
    let habitIdentifier = habit.persistentModelID
    guard isPersisted(bucket),
      bucket.habit?.persistentModelID == habitIdentifier
    else {
      throw HabitTodayComputationError.invalidBucketRelationship(bucket.periodKey)
    }
    let bucketIdentifiers: Set<PersistentIdentifier> = [bucket.persistentModelID]
    for entry in (bucket.entries ?? []).sorted(by: { uuidPrecedes($0.id, $1.id) }) {
      try validateEntry(
        entry,
        habitIdentifier: habitIdentifier,
        bucketIdentifiers: bucketIdentifiers
      )
    }
  }

  private func validateEntry(
    _ entry: LogEntry,
    habitIdentifier: PersistentIdentifier,
    bucketIdentifiers: Set<PersistentIdentifier>
  ) throws {
    guard isPersisted(entry),
      entry.habit?.persistentModelID == habitIdentifier,
      let bucket = entry.bucket,
      isPersisted(bucket),
      bucket.habit?.persistentModelID == habitIdentifier,
      bucketIdentifiers.contains(bucket.persistentModelID),
      bucket.entries?.contains(where: {
        $0.persistentModelID == entry.persistentModelID
      }) == true
    else {
      throw HabitTodayComputationError.invalidEntryRelationship(entry.id)
    }
  }

  private func uuidPrecedes(_ first: UUID, _ second: UUID) -> Bool {
    var firstBytes = first.uuid
    var secondBytes = second.uuid
    return withUnsafeBytes(of: &firstBytes) { firstBuffer in
      withUnsafeBytes(of: &secondBytes) { secondBuffer in
        firstBuffer.lexicographicallyPrecedes(secondBuffer)
      }
    }
  }

  private func isPersisted<T>(_ model: T) -> Bool where T: PersistentModel {
    model.modelContext == context && model.persistentModelID.storeIdentifier != nil
      && !model.isDeleted
  }
}
