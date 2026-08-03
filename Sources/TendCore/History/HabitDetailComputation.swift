import Foundation
import SwiftData

public enum HabitDetailComputationError: Error, Equatable, Sendable {
  case invalidBucketRelationship(String)
  case invalidEntryRelationship(UUID)
  case duplicateEntryID(UUID)
  case missingActiveBucket(String)
  case nonAdvancingCalendarPeriod(String)
}

@MainActor
public final class HabitDetailComputation {
  private let context: ModelContext
  private let reconciler: BucketReconciler
  private let streakComputation: HabitStreakComputation
  private let evaluator = BucketEvaluator()

  public init(context: ModelContext) {
    self.context = context
    reconciler = BucketReconciler(context: context)
    streakComputation = HabitStreakComputation(context: context)
  }

  init(context: ModelContext, save: @escaping () throws -> Void) {
    self.context = context
    reconciler = BucketReconciler(context: context, save: save)
    streakComputation = HabitStreakComputation(context: context, save: save)
  }

  public func snapshot(
    for habit: Habit,
    selectedMonth: Date,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> HabitDetailSnapshot {
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

    let calendar = calendar(timeZone: timeZone)
    let latestMonth = try month(containing: instant, calendar: calendar).start
    let creationPeriod = try CalendarBucketSchedule(timeZone: timeZone).period(
      containing: habit.createdAt,
      cadence: cadence
    )
    let creationMonth = try month(containing: creationPeriod.start, calendar: calendar).start
    guard
      let trailingStartCandidate = calendar.date(
        byAdding: .month,
        value: -2,
        to: latestMonth
      )
    else {
      throw CalendarBucketScheduleError.calendarCalculationFailed
    }
    let trailingStart = try month(containing: trailingStartCandidate, calendar: calendar).start
    let earliestMonth = min(creationMonth, trailingStart)
    let requestedMonth = try month(containing: selectedMonth, calendar: calendar).start
    let clampedMonth = min(max(requestedMonth, earliestMonth), latestMonth)
    let selectedInterval = try month(containing: clampedMonth, calendar: calendar)
    let periods = try periods(
      in: selectedInterval,
      cadence: cadence,
      timeZone: timeZone
    )

    let activityPeriods = try validatedActivityPeriods(for: habit)
    if habit.isActive {
      try reconciler.reconcile(habit: habit, at: instant, timeZone: timeZone)
    }
    let bucketsByKey = try indexedBuckets(
      for: habit,
      cadence: cadence,
      timeZone: timeZone
    )
    try validateBucketCoverage(
      bucketsByKey: bucketsByKey,
      activityPeriods: activityPeriods,
      cadence: cadence,
      at: instant,
      timeZone: timeZone
    )
    var history: [HabitHistoryPeriod] = []
    history.reserveCapacity(periods.count)
    for period in periods {
      history.append(
        try project(
          period,
          habit: habit,
          bucket: bucketsByKey[period.key],
          activityPeriods: activityPeriods,
          creationPeriod: creationPeriod,
          instant: instant,
          timeZone: timeZone
        ))
    }
    let editableEntries = try editableEntries(
      for: habit,
      bucketsByKey: bucketsByKey,
      cadence: cadence,
      at: instant,
      timeZone: timeZone
    )
    let streak = try streakComputation.compute(
      habit: habit,
      at: instant,
      timeZone: timeZone
    )

    return HabitDetailSnapshot(
      habitID: habit.id,
      cadence: cadence,
      monthRange: HabitDetailMonthRange(
        earliest: earliestMonth,
        selected: clampedMonth,
        latest: latestMonth
      ),
      streak: streak,
      history: history,
      editableEntries: editableEntries
    )
  }

  private func project(
    _ period: CalendarBucketPeriod,
    habit: Habit,
    bucket: HabitBucket?,
    activityPeriods: [HabitActivityPeriod],
    creationPeriod: CalendarBucketPeriod,
    instant: Date,
    timeZone: TimeZone
  ) throws -> HabitHistoryPeriod {
    if let bucket {
      let evaluation = try evaluator.evaluate(
        habit: habit,
        bucket: bucket,
        at: instant,
        timeZone: timeZone
      )
      let state: HabitHistoryState
      let progress: Int?
      let isRequirementMet: Bool?
      let target: Int?
      let unit: String?
      switch (evaluation.phase, evaluation.standing) {
      case (.final, .met):
        state = .met
        progress = nil
        isRequirementMet = nil
        target = evaluation.target
        unit = evaluation.unit
      case (.final, .missed):
        state = .missed
        progress = nil
        isRequirementMet = nil
        target = evaluation.target
        unit = evaluation.unit
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
        isRequirementMet = evaluation.standing == .pendingMet
        target = evaluation.target
        unit = evaluation.unit
      case (.exempt, .exempt):
        state = .inactive
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
      return HabitHistoryPeriod(
        key: period.key,
        start: period.start,
        end: period.end,
        state: state,
        progress: progress,
        target: target,
        unit: unit,
        isRequirementMet: isRequirementMet
      )
    }

    let state: HabitHistoryState
    if instant < period.start {
      state = .future
    } else if period.end <= creationPeriod.start {
      state = .beforeCreation
    } else if activityPeriods.contains(where: { overlaps($0, period: period) }) {
      throw HabitDetailComputationError.missingActiveBucket(period.key)
    } else {
      state = .inactive
    }
    return HabitHistoryPeriod(
      key: period.key,
      start: period.start,
      end: period.end,
      state: state
    )
  }

  private func periods(
    in month: DateInterval,
    cadence: HabitCadence,
    timeZone: TimeZone
  ) throws -> [CalendarBucketPeriod] {
    let schedule = CalendarBucketSchedule(timeZone: timeZone)
    var period = try schedule.period(containing: month.start, cadence: cadence)
    var result: [CalendarBucketPeriod] = []
    let firstStart = cadence == .daily ? month.start : period.start
    if cadence == .daily, period.start != firstStart {
      throw CalendarBucketScheduleError.calendarCalculationFailed
    }

    while period.start < month.end {
      result.append(period)
      let next = try schedule.next(after: period)
      guard next.start > period.start else {
        throw HabitDetailComputationError.nonAdvancingCalendarPeriod(period.key)
      }
      period = next
    }
    return result
  }
  private func validateBucketCoverage(
    bucketsByKey: [String: HabitBucket],
    activityPeriods: [HabitActivityPeriod],
    cadence: HabitCadence,
    at instant: Date,
    timeZone: TimeZone
  ) throws {
    let schedule = CalendarBucketSchedule(timeZone: timeZone)
    let buckets = Array(bucketsByKey.values)
    for activityPeriod in activityPeriods {
      guard activityPeriod.startedAt <= instant else {
        continue
      }
      let activityEnd = min(activityPeriod.endedAt ?? instant, instant)
      if activityPeriod.startedAt < activityEnd {
        let relevant = buckets.filter { bucket in
          bucket.startAt < activityEnd && bucket.endAt > activityPeriod.startedAt
        }.sorted { first, second in
          first.periodKey < second.periodKey
        }
        guard
          relevant.contains(where: { bucket in
            bucket.startAt <= activityPeriod.startedAt
              && bucket.endAt > activityPeriod.startedAt
          })
        else {
          let missing = try schedule.period(
            containing: activityPeriod.startedAt,
            cadence: cadence
          )
          throw HabitDetailComputationError.missingActiveBucket(missing.key)
        }
        for (previous, next) in zip(relevant, relevant.dropFirst()) {
          let previousPeriod = try schedule.period(forKey: previous.periodKey)
          let expected = try schedule.next(after: previousPeriod)
          guard next.periodKey == expected.key else {
            throw HabitDetailComputationError.missingActiveBucket(expected.key)
          }
        }
        if let endedAt = activityPeriod.endedAt, endedAt <= instant,
          !relevant.contains(where: { bucket in
            bucket.startAt < endedAt && bucket.endAt >= endedAt
          })
        {
          let lastPeriod = try schedule.period(
            forKey: relevant[relevant.index(before: relevant.endIndex)].periodKey
          )
          let missing = try schedule.next(after: lastPeriod)
          throw HabitDetailComputationError.missingActiveBucket(missing.key)
        }
      }
      if activityPeriod.endedAt == nil {
        let current = try schedule.period(containing: instant, cadence: cadence)
        guard bucketsByKey[current.key] != nil else {
          throw HabitDetailComputationError.missingActiveBucket(current.key)
        }
      }
    }
  }

  private func indexedBuckets(
    for habit: Habit,
    cadence: HabitCadence,
    timeZone: TimeZone
  ) throws -> [String: HabitBucket] {
    let habitIdentifier = habit.persistentModelID
    let descriptor = FetchDescriptor<HabitBucket>(
      predicate: #Predicate<HabitBucket> { bucket in
        bucket.habit?.persistentModelID == habitIdentifier
      })
    let buckets = try context.fetch(descriptor).sorted { first, second in
      if first.periodKey != second.periodKey {
        return first.periodKey < second.periodKey
      }
      return uuidPrecedes(first.id, second.id)
    }
    let schedule = CalendarBucketSchedule(timeZone: timeZone)
    var result: [String: HabitBucket] = [:]
    result.reserveCapacity(buckets.count)
    for bucket in buckets {
      guard isPersisted(bucket),
        bucket.habit?.persistentModelID == habitIdentifier
      else {
        throw HabitDetailComputationError.invalidBucketRelationship(bucket.periodKey)
      }
      let bucketCadence: HabitCadence
      guard let storedCadence = HabitCadence(rawValue: bucket.cadenceRawValue) else {
        throw BucketEvaluationError.unsupportedCadence(bucket.cadenceRawValue)
      }
      bucketCadence = storedCadence
      guard bucketCadence == cadence else {
        throw BucketEvaluationError.cadenceMismatch(
          habit: cadence,
          bucket: bucketCadence
        )
      }
      let period: CalendarBucketPeriod
      do {
        period = try schedule.period(
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
      if result.updateValue(bucket, forKey: bucket.periodKey) != nil {
        throw HabitStreakComputationError.duplicatePeriodKey(bucket.periodKey)
      }
    }
    return result
  }
  private func editableEntries(
    for habit: Habit,
    bucketsByKey: [String: HabitBucket],
    cadence: HabitCadence,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> [HabitEditableEntry] {
    let habitIdentifier = habit.persistentModelID
    let descriptor = FetchDescriptor<LogEntry>(
      predicate: #Predicate<LogEntry> { entry in
        entry.habit?.persistentModelID == habitIdentifier
      })
    var entries = try context.fetch(descriptor)
    var entryIdentifiers = Set(entries.map(\.persistentModelID))
    for bucket in bucketsByKey.values {
      for entry in bucket.entries ?? [] {
        guard entryIdentifiers.insert(entry.persistentModelID).inserted else {
          continue
        }
        entries.append(entry)
      }
    }
    entries.sort { uuidPrecedes($0.id, $1.id) }
    var seenIDs: Set<UUID> = []
    seenIDs.reserveCapacity(entries.count)
    var validated: [(entry: LogEntry, bucket: HabitBucket)] = []
    validated.reserveCapacity(entries.count)
    for entry in entries {
      guard seenIDs.insert(entry.id).inserted else {
        throw HabitDetailComputationError.duplicateEntryID(entry.id)
      }
      guard isPersisted(entry),
        entry.habit?.persistentModelID == habitIdentifier,
        let bucket = entry.bucket,
        isPersisted(bucket),
        bucket.habit?.persistentModelID == habitIdentifier,
        bucketsByKey[bucket.periodKey]?.persistentModelID == bucket.persistentModelID
      else {
        throw HabitDetailComputationError.invalidEntryRelationship(entry.id)
      }
      validated.append((entry, bucket))
    }

    var invalidAmount: Int?
    for item in validated where item.entry.amount <= 0 {
      invalidAmount = min(invalidAmount ?? item.entry.amount, item.entry.amount)
    }
    if let invalidAmount {
      throw BucketEvaluationError.invalidEntryAmount(invalidAmount)
    }
    var totalsByBucketKey: [String: Int] = [:]
    totalsByBucketKey.reserveCapacity(bucketsByKey.count)
    for item in validated {
      let total = totalsByBucketKey[item.bucket.periodKey, default: 0]
      let addition = total.addingReportingOverflow(item.entry.amount)
      guard !addition.overflow else {
        throw BucketEvaluationError.progressOverflow
      }
      totalsByBucketKey[item.bucket.periodKey] = addition.partialValue
    }
    guard !validated.isEmpty else {
      return []
    }
    let currentPeriodKey =
      habit.isActive
      ? try CalendarBucketSchedule(timeZone: timeZone).period(
        containing: instant,
        cadence: cadence
      ).key : nil

    var result: [HabitEditableEntry] = []
    result.reserveCapacity(validated.count)
    var bucketEditability: [String: Bool] = [:]
    bucketEditability.reserveCapacity(bucketsByKey.count)
    for item in validated {
      let isEditable: Bool
      if let cachedEditability = bucketEditability[item.bucket.periodKey] {
        isEditable = cachedEditability
      } else {
        let evaluation = try evaluator.evaluate(
          habit: habit,
          bucket: item.bucket,
          at: instant,
          timeZone: timeZone
        )
        switch evaluation.phase {
        case .open where item.bucket.periodKey == currentPeriodKey:
          isEditable = true
        case .grace where habit.isActive:
          isEditable = true
        case .open, .grace, .dueForFinalization, .final, .exempt:
          isEditable = false
        }
        bucketEditability[item.bucket.periodKey] = isEditable
      }
      guard isEditable else {
        continue
      }
      result.append(
        HabitEditableEntry(
          id: item.entry.id,
          timestamp: item.entry.timestamp,
          amount: item.entry.amount,
          bucketKey: item.bucket.periodKey,
          unit: habit.unit,
          bucketStart: item.bucket.startAt,
          bucketEnd: item.bucket.endAt
        ))
    }
    result.sort { first, second in
      if first.timestamp != second.timestamp {
        return first.timestamp > second.timestamp
      }
      return uuidPrecedes(first.id, second.id)
    }
    return result
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

  private func validatedActivityPeriods(for habit: Habit) throws -> [HabitActivityPeriod] {
    let habitIdentifier = habit.persistentModelID
    let descriptor = FetchDescriptor<HabitActivityPeriod>(
      predicate: #Predicate<HabitActivityPeriod> { period in
        period.habit?.persistentModelID == habitIdentifier
      })
    let periods = try context.fetch(descriptor).sorted { first, second in
      if first.startedAt != second.startedAt {
        return first.startedAt < second.startedAt
      }
      return (first.endedAt ?? .distantFuture) < (second.endedAt ?? .distantFuture)
    }
    var previousEnd: Date?
    var foundOpen = false
    for period in periods {
      guard isPersisted(period),
        period.habit?.persistentModelID == habitIdentifier
      else {
        throw HabitActivityOperationError.invalidActivityChronology
      }
      if let endedAt = period.endedAt {
        guard endedAt >= period.startedAt,
          !foundOpen,
          previousEnd.map({ period.startedAt >= $0 }) ?? true
        else {
          throw HabitActivityOperationError.invalidActivityChronology
        }
        previousEnd = endedAt
      } else {
        guard !foundOpen,
          previousEnd.map({ period.startedAt >= $0 }) ?? true
        else {
          throw HabitActivityOperationError.multipleOpenActivityPeriods
        }
        foundOpen = true
      }
    }
    if habit.isActive, !foundOpen {
      throw HabitActivityOperationError.missingOpenActivityPeriod
    }
    if !habit.isActive, foundOpen {
      throw HabitActivityOperationError.unexpectedOpenActivityPeriod
    }
    return periods
  }

  private func overlaps(
    _ activityPeriod: HabitActivityPeriod,
    period: CalendarBucketPeriod
  ) -> Bool {
    let activityEnd = activityPeriod.endedAt ?? .distantFuture
    guard activityEnd > activityPeriod.startedAt else {
      return false
    }
    return activityPeriod.startedAt < period.end && activityEnd > period.start
  }

  private func month(
    containing instant: Date,
    calendar: Calendar
  ) throws -> DateInterval {
    guard let interval = calendar.dateInterval(of: .month, for: instant) else {
      throw CalendarBucketScheduleError.calendarCalculationFailed
    }
    return interval
  }

  private func calendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
  }

  private func isPersisted<T>(_ model: T) -> Bool where T: PersistentModel {
    model.modelContext == context && model.persistentModelID.storeIdentifier != nil
      && !model.isDeleted
  }
}
