import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Habit today computation")
struct HabitTodayComputationTests {
  @Test("daily snapshot reconciles repeated over-target progress")
  func dailySnapshotReconcilesRepeatedOverTargetProgress() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T18:00:00Z")
    let habit = try create(
      in: context,
      name: "Read",
      cadence: .daily,
      target: 3,
      unit: "pages",
      at: try instant("2024-01-01T08:00:00Z"),
      timeZone: zone
    )
    let logging = LogEntryOperations(context: context)
    try logging.append(amount: 2, to: habit, at: now, timeZone: zone)
    try logging.append(amount: 3, to: habit, at: now, timeZone: zone)

    let snapshot = try HabitTodayComputation(context: context).snapshot(
      for: habit,
      at: now,
      timeZone: zone
    )

    #expect(
      snapshot
        == HabitTodaySnapshot(
          periodKey: "day:2024-01-01",
          progress: 5,
          target: 3,
          unit: "pages",
          cadence: .daily,
          currentStreak: 1,
          isAtRisk: false,
          isMet: true
        ))
  }

  @Test("unmet snapshot creates every missing current period")
  func unmetSnapshotCreatesEveryMissingCurrentPeriod() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let habit = try create(
      in: context,
      name: "Walk",
      cadence: .daily,
      target: 2,
      at: try instant("2024-01-01T12:00:00Z"),
      timeZone: zone
    )

    let snapshot = try HabitTodayComputation(context: context).snapshot(
      for: habit,
      at: try instant("2024-01-03T12:00:00Z"),
      timeZone: zone
    )

    #expect(snapshot.periodKey == "day:2024-01-03")
    #expect(snapshot.progress == 0)
    #expect(snapshot.target == 2)
    #expect(snapshot.unit == "times")
    #expect(snapshot.cadence == .daily)
    #expect(snapshot.currentStreak == 0)
    #expect(!snapshot.isAtRisk)
    #expect(!snapshot.isMet)
    #expect(
      try buckets(for: habit, in: context).map(\.periodKey)
        == ["day:2024-01-01", "day:2024-01-02", "day:2024-01-03"]
    )
  }

  @Test("weekly snapshot stays present on every weekday regardless of pins")
  func weeklySnapshotStaysPresentEveryDay() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let habit = try create(
      in: context,
      name: "Publish",
      cadence: .weekly,
      target: 1,
      pinnedWeekdays: .wednesday,
      at: try instant("2024-01-01T08:00:00Z"),
      timeZone: zone
    )
    let computation = HabitTodayComputation(context: context)

    for value in [
      "2024-01-01T12:00:00Z",
      "2024-01-02T12:00:00Z",
      "2024-01-03T12:00:00Z",
      "2024-01-04T12:00:00Z",
      "2024-01-05T12:00:00Z",
      "2024-01-06T12:00:00Z",
      "2024-01-07T12:00:00Z",
    ] {
      let snapshot = try computation.snapshot(
        for: habit,
        at: try instant(value),
        timeZone: zone
      )
      #expect(snapshot.periodKey == "week:2024-01-01")
      #expect(snapshot.cadence == .weekly)
      #expect(snapshot.progress == 0)
      #expect(!snapshot.isMet)
    }
  }

  @Test("Monday snapshot keeps current progress separate from prior grace risk")
  func mondaySnapshotKeepsCurrentProgressSeparateFromGraceRisk() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let habit = try create(
      in: context,
      name: "Publish",
      cadence: .weekly,
      target: 2,
      at: try instant("2024-01-01T08:00:00Z"),
      timeZone: zone
    )
    let logging = LogEntryOperations(context: context)
    try logging.append(
      amount: 2,
      to: habit,
      at: try instant("2024-01-01T12:00:00Z"),
      timeZone: zone
    )
    _ = try HabitStreakComputation(context: context).compute(
      habit: habit,
      at: try instant("2024-01-09T00:00:00Z"),
      timeZone: zone
    )
    let monday = try instant("2024-01-15T12:00:00Z")
    try logging.append(amount: 2, to: habit, at: monday, timeZone: zone)

    let snapshot = try HabitTodayComputation(context: context).snapshot(
      for: habit,
      at: monday,
      timeZone: zone
    )

    #expect(snapshot.periodKey == "week:2024-01-15")
    #expect(snapshot.progress == 2)
    #expect(snapshot.target == 2)
    #expect(snapshot.currentStreak == 2)
    #expect(snapshot.isAtRisk)
    #expect(snapshot.isMet)
  }

  @Test("local midnight DST and time-zone changes select civil current keys")
  func calendarChangesSelectCivilCurrentKeys() throws {
    let cases = [
      (
        creation: "2024-03-09T12:00:00Z",
        snapshot: "2024-03-11T07:00:00Z",
        creationZone: "America/Los_Angeles",
        snapshotZone: "America/Los_Angeles",
        expected: "day:2024-03-11"
      ),
      (
        creation: "2024-11-02T12:00:00Z",
        snapshot: "2024-11-04T08:00:00Z",
        creationZone: "America/Los_Angeles",
        snapshotZone: "America/Los_Angeles",
        expected: "day:2024-11-04"
      ),
      (
        creation: "2024-01-01T23:30:00Z",
        snapshot: "2024-01-01T23:45:00Z",
        creationZone: "UTC",
        snapshotZone: "Asia/Tokyo",
        expected: "day:2024-01-02"
      ),
    ]

    for item in cases {
      let context = try makeContext()
      let creationZone = try timeZone(item.creationZone)
      let habit = try create(
        in: context,
        name: "Read",
        cadence: .daily,
        target: 1,
        at: try instant(item.creation),
        timeZone: creationZone
      )

      let snapshot = try HabitTodayComputation(context: context).snapshot(
        for: habit,
        at: try instant(item.snapshot),
        timeZone: try timeZone(item.snapshotZone)
      )

      #expect(snapshot.periodKey == item.expected)
    }
  }

  @Test("exact Monday midnight selects the new weekly bucket")
  func exactMondayMidnightSelectsNewWeeklyBucket() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let habit = try create(
      in: context,
      name: "Review",
      cadence: .weekly,
      target: 1,
      at: try instant("2024-01-03T12:00:00Z"),
      timeZone: zone
    )
    let computation = HabitTodayComputation(context: context)

    let sunday = try computation.snapshot(
      for: habit,
      at: try instant("2024-01-07T23:59:59Z"),
      timeZone: zone
    )
    let monday = try computation.snapshot(
      for: habit,
      at: try instant("2024-01-08T00:00:00Z"),
      timeZone: zone
    )

    #expect(sunday.periodKey == "week:2024-01-01")
    #expect(monday.periodKey == "week:2024-01-08")
  }

  @Test("detached deleted foreign and inactive habits are rejected")
  func invalidHabitIdentityAndActivityAreRejected() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T12:00:00Z")
    let detached = Habit(name: "Detached", cadence: .daily, target: 1)
    try expectError(HabitStreakComputationError.detachedHabit) {
      _ = try HabitTodayComputation(context: context).snapshot(
        for: detached,
        at: now,
        timeZone: zone
      )
    }

    let foreignContext = try makeContext()
    let foreign = try create(
      in: foreignContext,
      name: "Foreign",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    try expectError(HabitStreakComputationError.detachedHabit) {
      _ = try HabitTodayComputation(context: context).snapshot(
        for: foreign,
        at: now,
        timeZone: zone
      )
    }

    let deleted = try create(
      in: context,
      name: "Deleted",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    context.delete(deleted)
    try expectError(HabitStreakComputationError.detachedHabit) {
      _ = try HabitTodayComputation(context: context).snapshot(
        for: deleted,
        at: now,
        timeZone: zone
      )
    }

    let inactiveContext = try makeContext()
    let inactive = try create(
      in: inactiveContext,
      name: "Inactive",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    try HabitActivityOperations(context: inactiveContext).deactivate(
      inactive,
      at: now,
      timeZone: zone
    )
    try expectError(HabitTodayComputationError.inactiveHabit) {
      _ = try HabitTodayComputation(context: inactiveContext).snapshot(
        for: inactive,
        at: now,
        timeZone: zone
      )
    }
  }

  @Test("invalid persisted habit values fail before projection")
  func invalidPersistedHabitValuesFailBeforeProjection() throws {
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T12:00:00Z")

    let cadenceContext = try makeContext()
    let cadence = Habit(name: "Cadence", cadence: .daily, target: 1)
    cadence.cadenceRawValue = "monthly"
    cadence.activityPeriods = [HabitActivityPeriod(startedAt: now)]
    cadenceContext.insert(cadence)
    try cadenceContext.save()
    try expectError(BucketEvaluationError.unsupportedCadence("monthly")) {
      _ = try HabitTodayComputation(context: cadenceContext).snapshot(
        for: cadence,
        at: now,
        timeZone: zone
      )
    }

    let targetContext = try makeContext()
    let target = Habit(name: "Target", cadence: .daily, target: 0)
    target.activityPeriods = [HabitActivityPeriod(startedAt: now)]
    targetContext.insert(target)
    try targetContext.save()
    try expectError(BucketEvaluationError.invalidRequirement(0)) {
      _ = try HabitTodayComputation(context: targetContext).snapshot(
        for: target,
        at: now,
        timeZone: zone
      )
    }

    let bestContext = try makeContext()
    let best = Habit(name: "Best", cadence: .daily, target: 1, bestStreak: -1)
    best.activityPeriods = [HabitActivityPeriod(startedAt: now)]
    bestContext.insert(best)
    try bestContext.save()
    try expectError(HabitStreakComputationError.invalidBestStreak(-1)) {
      _ = try HabitTodayComputation(context: bestContext).snapshot(
        for: best,
        at: now,
        timeZone: zone
      )
    }
  }

  @Test("missing and duplicate current buckets fail explicitly")
  func missingAndDuplicateCurrentBucketsFailExplicitly() throws {
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T12:00:00Z")

    let missingContext = try makeContext()
    let missingHabit = try create(
      in: missingContext,
      name: "Missing",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    for bucket in try buckets(for: missingHabit, in: missingContext) {
      missingContext.delete(bucket)
    }
    try missingContext.save()
    let missingComputation = HabitTodayComputation(
      context: missingContext,
      computeStreak: { _, _, _ in
        HabitStreakState(
          currentStreak: 0,
          bestStreak: 0,
          isAtRisk: false,
          cadence: .daily
        )
      }
    )
    try expectError(HabitTodayComputationError.missingCurrentBucket("day:2024-01-01")) {
      _ = try missingComputation.snapshot(for: missingHabit, at: now, timeZone: zone)
    }

    let duplicateContext = try makeContext()
    let duplicateHabit = try create(
      in: duplicateContext,
      name: "Duplicate",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let period = try CalendarBucketSchedule(timeZone: zone).period(
      containing: now,
      cadence: .daily
    )
    duplicateContext.insert(
      HabitBucket(
        periodKey: period.key,
        startAt: period.start,
        endAt: period.end,
        cadence: .daily,
        habit: duplicateHabit
      ))
    try duplicateContext.save()
    let duplicateComputation = HabitTodayComputation(
      context: duplicateContext,
      computeStreak: { _, _, _ in
        HabitStreakState(
          currentStreak: 0,
          bestStreak: 0,
          isAtRisk: false,
          cadence: .daily
        )
      }
    )
    try expectError(
      HabitTodayComputationError.multipleCurrentBuckets("day:2024-01-01")
    ) {
      _ = try duplicateComputation.snapshot(
        for: duplicateHabit,
        at: now,
        timeZone: zone
      )
    }
  }

  @Test("malformed current entry relationships are rejected")
  func malformedCurrentEntryRelationshipsAreRejected() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T12:00:00Z")
    let habit = try create(
      in: context,
      name: "Owner",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let other = try create(
      in: context,
      name: "Other",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let bucket = try #require(try buckets(for: habit, in: context).first)
    let malformed = LogEntry(
      timestamp: now,
      amount: 1,
      habit: other,
      bucket: bucket
    )
    context.insert(malformed)
    try context.save()

    try expectError(
      HabitTodayComputationError.invalidEntryRelationship(malformed.id)
    ) {
      _ = try HabitTodayComputation(context: context).snapshot(
        for: habit,
        at: now,
        timeZone: zone
      )
    }
  }

  @Test("reconciliation and evaluation failures propagate unchanged")
  func dependencyFailuresPropagateUnchanged() throws {
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T12:00:00Z")

    let activityContext = try makeContext()
    let missingActivity = Habit(name: "Missing activity", cadence: .daily, target: 1)
    activityContext.insert(missingActivity)
    try activityContext.save()
    try expectError(BucketReconciliationError.missingOpenActivityPeriod) {
      _ = try HabitTodayComputation(context: activityContext).snapshot(
        for: missingActivity,
        at: now,
        timeZone: zone
      )
    }

    let saveContext = try makeContext()
    let saveHabit = try create(
      in: saveContext,
      name: "Save failure",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    try expectError(TodaySaveFailure.expected) {
      _ = try HabitTodayComputation(
        context: saveContext,
        save: {
          throw TodaySaveFailure.expected
        }
      ).snapshot(
        for: saveHabit,
        at: try instant("2024-01-02T12:00:00Z"),
        timeZone: zone
      )
    }
    #expect(!saveContext.hasChanges)
    #expect(
      try buckets(for: saveHabit, in: saveContext).map(\.periodKey)
        == ["day:2024-01-01"]
    )

    let evaluationContext = try makeContext()
    let invalidEntryHabit = try create(
      in: evaluationContext,
      name: "Invalid entry",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let bucket = try #require(try buckets(for: invalidEntryHabit, in: evaluationContext).first)
    evaluationContext.insert(
      LogEntry(
        timestamp: now,
        amount: 0,
        habit: invalidEntryHabit,
        bucket: bucket
      ))
    try evaluationContext.save()
    try expectError(BucketEvaluationError.invalidEntryAmount(0)) {
      _ = try HabitTodayComputation(context: evaluationContext).snapshot(
        for: invalidEntryHabit,
        at: now,
        timeZone: zone
      )
    }
  }

  @Test("unexpected settled current bucket is not projected as current")
  func unexpectedSettledCurrentBucketIsRejected() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T12:00:00Z")
    let habit = try create(
      in: context,
      name: "Settled",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let bucket = try #require(try buckets(for: habit, in: context).first)
    bucket.finalizedAt = now
    bucket.verdictRawValue = BucketVerdict.met.rawValue
    bucket.targetSnapshot = 1
    bucket.unitSnapshot = "times"
    try context.save()

    try expectError(
      HabitTodayComputationError.unexpectedCurrentBucketState(
        key: "day:2024-01-01",
        phase: .final,
        standing: .met
      )
    ) {
      _ = try HabitTodayComputation(context: context).snapshot(
        for: habit,
        at: now,
        timeZone: zone
      )
    }
    #expect(habit.bestStreak == 0)
    #expect(!context.hasChanges)
  }

  @Test("best-streak save failure rolls back and propagates")
  func bestStreakSaveFailureRollsBackAndPropagates() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let createdAt = try instant("2024-01-01T08:00:00Z")
    let habit = try create(
      in: context,
      name: "Read",
      cadence: .daily,
      target: 1,
      at: createdAt,
      timeZone: zone
    )
    try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: createdAt,
      timeZone: zone
    )
    let evaluationInstant = try instant("2024-01-03T00:00:00Z")
    try BucketReconciler(context: context).reconcile(
      habit: habit,
      at: evaluationInstant,
      timeZone: zone
    )

    try expectError(TodaySaveFailure.expected) {
      _ = try HabitTodayComputation(
        context: context,
        save: {
          throw TodaySaveFailure.expected
        }
      ).snapshot(
        for: habit,
        at: evaluationInstant,
        timeZone: zone
      )
    }

    #expect(habit.bestStreak == 0)
    #expect(!context.hasChanges)
    let first = try #require(
      try buckets(for: habit, in: context).first {
        $0.periodKey == "day:2024-01-01"
      }
    )
    #expect(first.verdictRawValue == BucketVerdict.met.rawValue)
    #expect(first.finalizedAt == evaluationInstant)
  }

  @Test("persistent identity isolates habits sharing an ordinary UUID")
  func persistentIdentityIsolatesOrdinaryUUIDCollisions() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T12:00:00Z")
    let sharedID = UUID()
    let met = try create(
      in: context,
      name: "Met",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let unmet = try create(
      in: context,
      name: "Unmet",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    met.id = sharedID
    unmet.id = sharedID
    try context.save()
    try LogEntryOperations(context: context).append(
      amount: 1,
      to: met,
      at: now,
      timeZone: zone
    )
    let computation = HabitTodayComputation(context: context)

    let metSnapshot = try computation.snapshot(for: met, at: now, timeZone: zone)
    let unmetSnapshot = try computation.snapshot(for: unmet, at: now, timeZone: zone)

    #expect(metSnapshot.progress == 1)
    #expect(metSnapshot.isMet)
    #expect(unmetSnapshot.progress == 0)
    #expect(!unmetSnapshot.isMet)
  }

  private func create(
    in context: ModelContext,
    name: String,
    cadence: HabitCadence,
    target: Int,
    unit: String = "times",
    pinnedWeekdays: PinnedWeekdays = .none,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> Habit {
    try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(
        name: name,
        target: target,
        unit: unit,
        pinnedWeekdays: pinnedWeekdays
      ),
      cadence: cadence,
      at: instant,
      timeZone: timeZone
    )
  }

  private func buckets(for habit: Habit, in context: ModelContext) throws
    -> [HabitBucket]
  {
    let habitIdentifier = habit.persistentModelID
    return try context.fetch(FetchDescriptor<HabitBucket>())
      .filter { $0.habit?.persistentModelID == habitIdentifier }
      .sorted { $0.periodKey < $1.periodKey }
  }

  private func expectError<E>(
    _ expected: E,
    performing operation: () throws -> Void
  ) throws where E: Error & Equatable {
    do {
      try operation()
      Issue.record("Expected \(expected)")
    } catch let error as E {
      #expect(error == expected)
    }
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private func timeZone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }
}

private enum TodaySaveFailure: Error, Equatable {
  case expected
}
