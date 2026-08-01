import Foundation
import SwiftData

public enum LogEntryDestination: Equatable, Sendable {
  case current
  case periodKey(String)
}

public enum LogEntryOperationError: Error, Equatable, Sendable {
  case inactiveHabit
  case invalidAmount(Int)
  case detachedHabit
  case detachedEntry
  case detachedEntryBucket
  case missingEntryHabit
  case missingEntryBucket
  case missingBucketHabit
  case foreignEntryHabit
  case foreignEntryBucket
  case destinationUnavailable(String)
  case destinationNotEditable(key: String, phase: BucketPhase)
  case progressOverflow
}

@MainActor
public final class LogEntryOperations {
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

  @discardableResult
  public func append(
    amount: Int,
    to habit: Habit,
    destination: LogEntryDestination = .current,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> LogEntry {
    guard amount > 0 else {
      throw LogEntryOperationError.invalidAmount(amount)
    }
    guard habit.isActive else {
      throw LogEntryOperationError.inactiveHabit
    }
    guard isPersisted(habit) else {
      throw LogEntryOperationError.detachedHabit
    }

    try reconciler.reconcile(habit: habit, at: instant, timeZone: timeZone)

    let cadence = try cadence(for: habit)
    let schedule = CalendarBucketSchedule(timeZone: timeZone)
    let currentPeriod = try schedule.period(containing: instant, cadence: cadence)
    let destinationKey: String
    switch destination {
    case .current:
      destinationKey = currentPeriod.key
    case .periodKey(let key):
      let selectedPeriod: CalendarBucketPeriod
      do {
        selectedPeriod = try schedule.period(forKey: key)
      } catch let error as CalendarBucketScheduleError {
        throw BucketEvaluationError.calendar(error)
      }
      guard selectedPeriod.cadence == cadence else {
        throw BucketEvaluationError.periodCadenceMismatch(
          key: key,
          cadence: cadence
        )
      }
      destinationKey = key
    }
    let bucket = try bucket(for: habit, periodKey: destinationKey)
    let evaluation = try evaluator.evaluate(
      habit: habit,
      bucket: bucket,
      at: instant,
      timeZone: timeZone
    )
    try authorize(
      evaluation,
      bucket: bucket,
      currentPeriodKey: currentPeriod.key
    )

    guard let progress = evaluation.progress else {
      throw LogEntryOperationError.destinationNotEditable(
        key: bucket.periodKey,
        phase: evaluation.phase
      )
    }
    guard !progress.addingReportingOverflow(amount).overflow else {
      throw LogEntryOperationError.progressOverflow
    }

    let entry = LogEntry(
      timestamp: instant,
      amount: amount,
      habit: habit,
      bucket: bucket
    )
    context.insert(entry)
    do {
      try saveContext()
      return entry
    } catch {
      entry.habit = nil
      entry.bucket = nil
      context.rollback()
      throw error
    }
  }
  public func delete(
    _ entry: LogEntry,
    from habit: Habit,
    at instant: Date,
    timeZone: TimeZone
  ) throws {
    guard habit.isActive else {
      throw LogEntryOperationError.inactiveHabit
    }
    guard isPersisted(habit) else {
      throw LogEntryOperationError.detachedHabit
    }
    guard isPersisted(entry) else {
      throw LogEntryOperationError.detachedEntry
    }
    guard let entryHabit = entry.habit else {
      throw LogEntryOperationError.missingEntryHabit
    }
    guard entryHabit.persistentModelID == habit.persistentModelID else {
      throw LogEntryOperationError.foreignEntryHabit
    }
    guard let bucket = entry.bucket else {
      throw LogEntryOperationError.missingEntryBucket
    }
    guard isPersisted(bucket) else {
      throw LogEntryOperationError.detachedEntryBucket
    }
    guard let bucketHabit = bucket.habit else {
      throw LogEntryOperationError.missingBucketHabit
    }
    guard bucketHabit.persistentModelID == habit.persistentModelID else {
      throw LogEntryOperationError.foreignEntryBucket
    }

    try reconciler.reconcile(habit: habit, at: instant, timeZone: timeZone)

    let cadence = try cadence(for: habit)
    let currentPeriod = try CalendarBucketSchedule(timeZone: timeZone).period(
      containing: instant,
      cadence: cadence
    )
    let evaluation = try evaluator.evaluate(
      habit: habit,
      bucket: bucket,
      at: instant,
      timeZone: timeZone
    )
    try authorize(
      evaluation,
      bucket: bucket,
      currentPeriodKey: currentPeriod.key
    )

    context.delete(entry)
    do {
      try saveContext()
    } catch {
      context.rollback()
      throw error
    }
  }

  private func isPersisted<T>(_ model: T) -> Bool where T: PersistentModel {
    model.modelContext == context && model.persistentModelID.storeIdentifier != nil
      && !model.isDeleted
  }

  private func cadence(for habit: Habit) throws -> HabitCadence {
    guard let cadence = HabitCadence(rawValue: habit.cadenceRawValue) else {
      throw BucketEvaluationError.unsupportedCadence(habit.cadenceRawValue)
    }
    return cadence
  }

  private func bucket(for habit: Habit, periodKey: String) throws -> HabitBucket {
    let habitIdentifier = habit.persistentModelID
    let descriptor = FetchDescriptor<HabitBucket>(
      predicate: #Predicate<HabitBucket> { bucket in
        bucket.habit?.persistentModelID == habitIdentifier
          && bucket.periodKey == periodKey
      })
    let matches = try context.fetch(descriptor)
    guard let bucket = matches.first, matches.count == 1 else {
      throw LogEntryOperationError.destinationUnavailable(periodKey)
    }
    return bucket
  }

  private func authorize(
    _ evaluation: BucketEvaluation,
    bucket: HabitBucket,
    currentPeriodKey: String
  ) throws {
    switch evaluation.phase {
    case .open where bucket.periodKey == currentPeriodKey:
      return
    case .grace:
      return
    case .open, .dueForFinalization, .final, .exempt:
      throw LogEntryOperationError.destinationNotEditable(
        key: bucket.periodKey,
        phase: evaluation.phase
      )
    }
  }
}
