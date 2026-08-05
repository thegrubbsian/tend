import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Habit logging computation")
struct HabitLoggingComputationTests {
  @Test("daily snapshot returns current and grace facts with stable entry order")
  func dailySnapshotReturnsEditableFactsAndStableEntryOrder() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let habit = try create(
      in: context,
      name: "Practice piano",
      cadence: .daily,
      target: 5,
      unit: "min",
      at: instant("2024-01-01T08:00:00Z"),
      timeZone: zone
    )
    let logging = LogEntryOperations(context: context)
    let graceEntry = try logging.append(
      amount: 10,
      to: habit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: zone
    )
    let olderCurrent = try logging.append(
      amount: 2,
      to: habit,
      at: instant("2024-01-02T10:00:00Z"),
      timeZone: zone
    )
    let sharedTimestamp = try instant("2024-01-02T11:00:00Z")
    let sameTimeFirst = try logging.append(
      amount: 3,
      to: habit,
      at: sharedTimestamp,
      timeZone: zone
    )
    let sameTimeSecond = try logging.append(
      amount: 4,
      to: habit,
      at: sharedTimestamp,
      timeZone: zone
    )
    let sharedUUID = UUID()
    sameTimeFirst.id = sharedUUID
    sameTimeSecond.id = sharedUUID
    try context.save()

    let snapshot = try HabitLoggingComputation(context: context).snapshot(
      for: habit,
      at: instant("2024-01-02T12:00:00Z"),
      timeZone: zone
    )

    #expect(snapshot.habitID == habit.persistentModelID)
    #expect(snapshot.name == "Practice piano")
    #expect(snapshot.cadence == .daily)
    #expect(snapshot.target == 5)
    #expect(snapshot.unit == "min")
    #expect(snapshot.current.periodKey == "day:2024-01-02")
    #expect(snapshot.current.phase == .open)
    #expect(snapshot.current.progress == 9)
    #expect(snapshot.current.target == 5)
    #expect(snapshot.current.unit == "min")
    #expect(snapshot.current.isMet)

    let sameTimeEntries = [sameTimeFirst, sameTimeSecond].sorted {
      $0.persistentModelID < $1.persistentModelID
    }
    let expectedEntries = sameTimeEntries + [olderCurrent]
    #expect(snapshot.current.entries.map(\.id) == expectedEntries.map(\.persistentModelID))
    #expect(snapshot.current.entries.map(\.uuid) == expectedEntries.map(\.id))
    #expect(snapshot.current.entries.map(\.amount) == expectedEntries.map(\.amount))
    #expect(
      zip(snapshot.current.entries, expectedEntries).allSatisfy {
        $0.entry === $1 && $0.timestamp == $1.timestamp
      }
    )

    let grace = try #require(snapshot.grace)
    #expect(grace.periodKey == "day:2024-01-01")
    #expect(grace.phase == .grace)
    #expect(grace.progress == 10)
    #expect(grace.target == 5)
    #expect(grace.unit == "min")
    #expect(grace.isMet)
    #expect(grace.entries.map(\.id) == [graceEntry.persistentModelID])
    #expect(grace.entries[0].entry.persistentModelID == graceEntry.persistentModelID)
  }

  @Test("weekly grace is projected throughout Monday and omitted at Tuesday midnight")
  func weeklyGraceUsesEvaluatedCalendarPhase() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let habit = try create(
      in: context,
      name: "Weekly review",
      cadence: .weekly,
      target: 3,
      unit: "times",
      pinnedWeekdays: .wednesday,
      at: instant("2024-01-01T08:00:00Z"),
      timeZone: zone
    )
    let logging = LogEntryOperations(context: context)
    try logging.append(
      amount: 2,
      to: habit,
      at: instant("2024-01-03T12:00:00Z"),
      timeZone: zone
    )
    let computation = HabitLoggingComputation(context: context)

    let mondayInstant = try instant("2024-01-08T23:59:59Z")
    let monday = try computation.snapshot(
      for: habit,
      at: mondayInstant,
      timeZone: zone
    )
    try logging.append(
      amount: 1,
      to: habit,
      destination: .periodKey("week:2024-01-01"),
      at: mondayInstant,
      timeZone: zone
    )
    let metMonday = try computation.snapshot(
      for: habit,
      at: mondayInstant,
      timeZone: zone
    )
    let tuesday = try computation.snapshot(
      for: habit,
      at: instant("2024-01-09T00:00:00Z"),
      timeZone: zone
    )

    #expect(monday.current.periodKey == "week:2024-01-08")
    #expect(monday.current.progress == 0)
    #expect(!monday.current.isMet)
    #expect(monday.grace?.periodKey == "week:2024-01-01")
    #expect(monday.grace?.phase == .grace)
    #expect(monday.grace?.progress == 2)
    #expect(monday.grace?.isMet == false)
    #expect(metMonday.grace?.progress == 3)
    #expect(metMonday.grace?.isMet == true)
    #expect(tuesday.current.periodKey == "week:2024-01-08")
    #expect(tuesday.grace == nil)
  }

  @Test("non-grace preceding buckets are omitted and duplicate preceding keys fail")
  func nonGraceAndDuplicatePrecedingBucketsAreRejected() throws {
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-02T12:00:00Z")
    let context = try makeContext()
    let habit = try create(
      in: context,
      name: "Prior phases",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let previousPeriod = try CalendarBucketSchedule(timeZone: zone).period(
      forKey: "day:2024-01-01"
    )
    let previous = HabitBucket(
      periodKey: previousPeriod.key,
      startAt: previousPeriod.start,
      endAt: previousPeriod.end,
      cadence: .daily,
      habit: habit
    )
    context.insert(previous)
    previous.isExempt = true
    try context.save()
    let exemptSnapshot = try HabitLoggingComputation(
      context: context,
      reconcile: { _, _, _ in }
    ).snapshot(for: habit, at: now, timeZone: zone)
    #expect(exemptSnapshot.grace == nil)

    previous.isExempt = false
    previous.finalizedAt = try instant("2024-01-02T00:00:00Z")
    previous.verdictRawValue = BucketVerdict.missed.rawValue
    previous.targetSnapshot = 1
    previous.unitSnapshot = "times"
    try context.save()
    let finalSnapshot = try HabitLoggingComputation(
      context: context,
      reconcile: { _, _, _ in }
    ).snapshot(for: habit, at: now, timeZone: zone)
    #expect(finalSnapshot.grace == nil)

    let dueContext = try makeContext()
    let dueNow = try instant("2024-01-09T12:00:00Z")
    let dueHabit = try create(
      in: dueContext,
      name: "Due prior",
      cadence: .weekly,
      target: 1,
      at: instant("2024-01-08T08:00:00Z"),
      timeZone: zone
    )
    let duePeriod = try CalendarBucketSchedule(timeZone: zone).period(
      forKey: "week:2024-01-01"
    )
    let dueBucket = HabitBucket(
      periodKey: duePeriod.key,
      startAt: duePeriod.start,
      endAt: duePeriod.end,
      cadence: .weekly,
      habit: dueHabit
    )
    dueContext.insert(dueBucket)
    try dueContext.save()
    let dueEvaluation = try BucketEvaluator().evaluate(
      habit: dueHabit,
      bucket: dueBucket,
      at: dueNow,
      timeZone: zone
    )
    #expect(dueEvaluation.phase == .dueForFinalization)
    let dueSnapshot = try HabitLoggingComputation(
      context: dueContext,
      reconcile: { _, _, _ in }
    ).snapshot(for: dueHabit, at: dueNow, timeZone: zone)
    #expect(dueSnapshot.grace == nil)

    let duplicateContext = try makeContext()
    let duplicateHabit = try create(
      in: duplicateContext,
      name: "Duplicate prior",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    for _ in 0..<2 {
      duplicateContext.insert(
        HabitBucket(
          periodKey: previousPeriod.key,
          startAt: previousPeriod.start,
          endAt: previousPeriod.end,
          cadence: .daily,
          habit: duplicateHabit
        ))
    }
    try duplicateContext.save()
    try expectError(HabitLoggingComputationError.multipleBuckets(previousPeriod.key)) {
      _ = try HabitLoggingComputation(
        context: duplicateContext,
        reconcile: { _, _, _ in }
      ).snapshot(for: duplicateHabit, at: now, timeZone: zone)
    }
  }

  @Test("civil current and grace keys survive DST and time-zone changes")
  func calendarBoundariesSelectCivilEditableKeys() throws {
    let cases = [
      (
        creation: "2024-03-09T20:00:00Z",
        now: "2024-03-11T07:30:00Z",
        creationZone: "America/Los_Angeles",
        snapshotZone: "America/Los_Angeles",
        current: "day:2024-03-11",
        grace: "day:2024-03-10"
      ),
      (
        creation: "2024-01-01T08:00:00Z",
        now: "2024-01-01T16:30:00Z",
        creationZone: "UTC",
        snapshotZone: "Asia/Tokyo",
        current: "day:2024-01-02",
        grace: "day:2024-01-01"
      ),
    ]

    for item in cases {
      let context = try makeContext()
      let habit = try create(
        in: context,
        name: "Civil",
        cadence: .daily,
        target: 1,
        at: instant(item.creation),
        timeZone: timeZone(item.creationZone)
      )

      let snapshot = try HabitLoggingComputation(context: context).snapshot(
        for: habit,
        at: instant(item.now),
        timeZone: timeZone(item.snapshotZone)
      )

      #expect(snapshot.current.periodKey == item.current)
      #expect(snapshot.grace?.periodKey == item.grace)
    }
  }

  @Test("exact shortened extended and weekly local boundaries select schedule keys")
  func exactOwnerLocalRolloverBoundariesSelectScheduleKeys() throws {
    let cases:
      [(
        cadence: HabitCadence,
        zone: String,
        creation: String,
        before: String,
        rollover: String,
        beforeKey: String,
        currentKey: String
      )] = [
        (
          cadence: .daily,
          zone: "America/Los_Angeles",
          creation: "2024-03-10T09:00:00Z",
          before: "2024-03-11T06:59:59Z",
          rollover: "2024-03-11T07:00:00Z",
          beforeKey: "day:2024-03-10",
          currentKey: "day:2024-03-11"
        ),
        (
          cadence: .daily,
          zone: "America/Los_Angeles",
          creation: "2024-11-03T20:00:00Z",
          before: "2024-11-04T07:59:59Z",
          rollover: "2024-11-04T08:00:00Z",
          beforeKey: "day:2024-11-03",
          currentKey: "day:2024-11-04"
        ),
        (
          cadence: .weekly,
          zone: "Asia/Tokyo",
          creation: "2024-01-01T03:00:00Z",
          before: "2024-01-07T14:59:59Z",
          rollover: "2024-01-07T15:00:00Z",
          beforeKey: "week:2024-01-01",
          currentKey: "week:2024-01-08"
        ),
      ]

    for item in cases {
      let context = try makeContext()
      let zone = try timeZone(item.zone)
      let habit = try create(
        in: context,
        name: "Boundary",
        cadence: item.cadence,
        target: 1,
        at: instant(item.creation),
        timeZone: zone
      )
      let computation = HabitLoggingComputation(context: context)

      let before = try computation.snapshot(
        for: habit,
        at: instant(item.before),
        timeZone: zone
      )
      let rollover = try computation.snapshot(
        for: habit,
        at: instant(item.rollover),
        timeZone: zone
      )

      #expect(before.current.periodKey == item.beforeKey)
      #expect(before.grace == nil)
      #expect(rollover.current.periodKey == item.currentKey)
      #expect(rollover.grace?.periodKey == item.beforeKey)
      #expect(rollover.grace?.phase == .grace)
    }
  }

  @Test("reconciliation creates current periods and save failure rolls back")
  func reconciliationCreatesPeriodsAndPreservesRollback() throws {
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-03T12:00:00Z")

    let context = try makeContext()
    let habit = try create(
      in: context,
      name: "Walk",
      cadence: .daily,
      target: 1,
      at: instant("2024-01-01T08:00:00Z"),
      timeZone: zone
    )
    var saveCount = 0
    let snapshot = try HabitLoggingComputation(
      context: context,
      save: {
        saveCount += 1
        try context.save()
      }
    ).snapshot(for: habit, at: now, timeZone: zone)
    #expect(saveCount == 1)
    #expect(snapshot.current.periodKey == "day:2024-01-03")
    #expect(snapshot.grace?.periodKey == "day:2024-01-02")
    #expect(
      try buckets(for: habit, in: context).map(\.periodKey) == [
        "day:2024-01-01", "day:2024-01-02", "day:2024-01-03",
      ])
    let expired = try #require(
      try buckets(for: habit, in: context).first {
        $0.periodKey == "day:2024-01-01"
      }
    )
    let expectedFinalizedAt = try instant("2024-01-03T00:00:00Z")
    #expect(expired.finalizedAt == expectedFinalizedAt)
    #expect(expired.verdictRawValue == BucketVerdict.missed.rawValue)
    #expect(expired.targetSnapshot == 1)
    #expect(expired.unitSnapshot == "times")

    let failingContext = try makeContext()
    let failingHabit = try create(
      in: failingContext,
      name: "Fail",
      cadence: .daily,
      target: 1,
      at: instant("2024-01-01T08:00:00Z"),
      timeZone: zone
    )
    try expectError(LoggingSaveFailure.expected) {
      _ = try HabitLoggingComputation(
        context: failingContext,
        save: { throw LoggingSaveFailure.expected }
      ).snapshot(for: failingHabit, at: now, timeZone: zone)
    }
    #expect(!failingContext.hasChanges)
    #expect(
      try buckets(for: failingHabit, in: failingContext).map(\.periodKey) == [
        "day:2024-01-01"
      ])

    let reconciliationContext = try makeContext()
    let reconciliationHabit = try create(
      in: reconciliationContext,
      name: "Duplicate reconciliation",
      cadence: .daily,
      target: 1,
      at: instant("2024-01-01T08:00:00Z"),
      timeZone: zone
    )
    let duplicatePeriod = try CalendarBucketSchedule(timeZone: zone).period(
      forKey: "day:2024-01-01"
    )
    reconciliationContext.insert(
      HabitBucket(
        periodKey: duplicatePeriod.key,
        startAt: duplicatePeriod.start,
        endAt: duplicatePeriod.end,
        cadence: .daily,
        habit: reconciliationHabit
      ))
    try reconciliationContext.save()
    try expectError(BucketReconciliationError.duplicatePeriodKey(duplicatePeriod.key)) {
      _ = try HabitLoggingComputation(context: reconciliationContext).snapshot(
        for: reconciliationHabit,
        at: now,
        timeZone: zone
      )
    }
  }

  @Test("detached deleted foreign inactive and invalid habits are rejected")
  func invalidHabitStatesAreRejected() throws {
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T12:00:00Z")
    let context = try makeContext()
    let computation = HabitLoggingComputation(context: context)

    try expectError(HabitLoggingComputationError.detachedHabit) {
      _ = try computation.snapshot(
        for: Habit(name: "Detached", cadence: .daily, target: 1),
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
    try expectError(HabitLoggingComputationError.detachedHabit) {
      _ = try computation.snapshot(for: foreign, at: now, timeZone: zone)
    }

    let inactive = try create(
      in: context,
      name: "Inactive",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    inactive.isActive = false
    try context.save()
    try expectError(HabitLoggingComputationError.inactiveHabit) {
      _ = try computation.snapshot(for: inactive, at: now, timeZone: zone)
    }

    let invalidCadence = try create(
      in: context,
      name: "Cadence",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    invalidCadence.cadenceRawValue = "monthly"
    try context.save()
    try expectError(BucketEvaluationError.unsupportedCadence("monthly")) {
      _ = try computation.snapshot(for: invalidCadence, at: now, timeZone: zone)
    }

    let invalidTarget = try create(
      in: context,
      name: "Target",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    invalidTarget.target = 0
    try context.save()
    try expectError(BucketEvaluationError.invalidRequirement(0)) {
      _ = try computation.snapshot(for: invalidTarget, at: now, timeZone: zone)
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
    try expectError(HabitLoggingComputationError.detachedHabit) {
      _ = try computation.snapshot(for: deleted, at: now, timeZone: zone)
    }
  }

  @Test("missing duplicate and settled current buckets fail explicitly")
  func invalidCurrentBucketSelectionIsRejected() throws {
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
    try expectError(HabitLoggingComputationError.missingCurrentBucket("day:2024-01-01")) {
      _ = try HabitLoggingComputation(
        context: missingContext,
        reconcile: { _, _, _ in }
      ).snapshot(for: missingHabit, at: now, timeZone: zone)
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
    try expectError(HabitLoggingComputationError.multipleBuckets("day:2024-01-01")) {
      _ = try HabitLoggingComputation(
        context: duplicateContext,
        reconcile: { _, _, _ in }
      ).snapshot(for: duplicateHabit, at: now, timeZone: zone)
    }

    let settledContext = try makeContext()
    let settledHabit = try create(
      in: settledContext,
      name: "Settled",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let settledBucket = try #require(try buckets(for: settledHabit, in: settledContext).first)
    settledBucket.finalizedAt = now
    settledBucket.verdictRawValue = BucketVerdict.met.rawValue
    settledBucket.targetSnapshot = 1
    settledBucket.unitSnapshot = "times"
    try settledContext.save()
    try expectError(
      HabitLoggingComputationError.unexpectedBucketState(
        key: "day:2024-01-01",
        phase: .final,
        standing: .met
      )
    ) {
      _ = try HabitLoggingComputation(
        context: settledContext,
        reconcile: { _, _, _ in }
      ).snapshot(for: settledHabit, at: now, timeZone: zone)
    }
  }

  @Test("malformed bucket and entry relationships are rejected")
  func malformedRelationshipsAreRejected() throws {
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T12:00:00Z")

    let entryContext = try makeContext()
    let owner = try create(
      in: entryContext,
      name: "Owner",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let other = try create(
      in: entryContext,
      name: "Other",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let ownerBucket = try #require(try buckets(for: owner, in: entryContext).first)
    let malformedEntry = LogEntry(
      timestamp: now,
      amount: 1,
      habit: other,
      bucket: ownerBucket
    )
    entryContext.insert(malformedEntry)
    try entryContext.save()
    try expectError(
      HabitLoggingComputationError.invalidEntryRelationship(malformedEntry.id)
    ) {
      _ = try HabitLoggingComputation(context: entryContext).snapshot(
        for: owner,
        at: now,
        timeZone: zone
      )
    }

    let missingHabit = try loggedFixture(
      name: "Missing habit inverse",
      at: now,
      timeZone: zone
    )
    missingHabit.entry.habit = nil
    try missingHabit.context.save()
    try expectError(
      HabitLoggingComputationError.invalidEntryRelationship(missingHabit.entry.id)
    ) {
      _ = try HabitLoggingComputation(context: missingHabit.context).snapshot(
        for: missingHabit.habit,
        at: now,
        timeZone: zone
      )
    }

    let missingBucket = try loggedFixture(
      name: "Missing bucket inverse",
      at: now,
      timeZone: zone
    )
    missingBucket.entry.bucket = nil
    try missingBucket.context.save()
    try expectError(
      HabitLoggingComputationError.invalidEntryRelationship(missingBucket.entry.id)
    ) {
      _ = try HabitLoggingComputation(context: missingBucket.context).snapshot(
        for: missingBucket.habit,
        at: now,
        timeZone: zone
      )
    }

    let foreignBucket = try loggedFixture(
      name: "Foreign bucket inverse",
      at: now,
      timeZone: zone
    )
    let foreignBucketOwner = try create(
      in: foreignBucket.context,
      name: "Other bucket owner",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let foreignBuckets = try buckets(
      for: foreignBucketOwner,
      in: foreignBucket.context
    )
    try #require(foreignBuckets.count == 1)
    foreignBucket.entry.bucket = foreignBuckets[0]
    try foreignBucket.context.save()
    try expectError(
      HabitLoggingComputationError.invalidEntryRelationship(foreignBucket.entry.id)
    ) {
      _ = try HabitLoggingComputation(context: foreignBucket.context).snapshot(
        for: foreignBucket.habit,
        at: now,
        timeZone: zone
      )
    }

    let detachedEntry = try loggedFixture(
      name: "Detached entry",
      at: now,
      timeZone: zone
    )
    detachedEntry.context.delete(detachedEntry.entry)
    try expectError(
      HabitLoggingComputationError.invalidEntryRelationship(detachedEntry.entry.id)
    ) {
      _ = try HabitLoggingComputation(context: detachedEntry.context).snapshot(
        for: detachedEntry.habit,
        at: now,
        timeZone: zone
      )
    }

    let bucketContext = try makeContext()
    let bucketOwner = try create(
      in: bucketContext,
      name: "Bucket owner",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let detachedBucket = try #require(try buckets(for: bucketOwner, in: bucketContext).first)
    bucketContext.delete(detachedBucket)
    try expectError(
      HabitLoggingComputationError.invalidBucketRelationship(detachedBucket.periodKey)
    ) {
      _ = try HabitLoggingComputation(
        context: bucketContext,
        reconcile: { _, _, _ in }
      ).snapshot(for: bucketOwner, at: now, timeZone: zone)
    }
  }

  @Test("nil entry relationships project an empty zero-progress bucket")
  func nilEntryRelationshipsProjectEmptyProgress() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T12:00:00Z")
    let habit = try create(
      in: context,
      name: "Empty",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let bucket = try #require(try buckets(for: habit, in: context).first)
    habit.entries = nil
    bucket.entries = nil
    try context.save()

    let snapshot = try HabitLoggingComputation(context: context).snapshot(
      for: habit,
      at: now,
      timeZone: zone
    )

    #expect(snapshot.current.progress == 0)
    #expect(snapshot.current.entries.isEmpty)
    #expect(snapshot.grace == nil)
  }

  @Test("evaluation failures propagate without partial snapshots")
  func evaluationFailuresPropagate() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T12:00:00Z")
    let habit = try create(
      in: context,
      name: "Overflow",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let bucket = try #require(try buckets(for: habit, in: context).first)
    context.insert(LogEntry(timestamp: now, amount: Int.max, habit: habit, bucket: bucket))
    context.insert(LogEntry(timestamp: now, amount: 1, habit: habit, bucket: bucket))
    try context.save()

    try expectError(BucketEvaluationError.progressOverflow) {
      _ = try HabitLoggingComputation(context: context).snapshot(
        for: habit,
        at: now,
        timeZone: zone
      )
    }

    let invalidContext = try makeContext()
    let invalidHabit = try create(
      in: invalidContext,
      name: "Invalid",
      cadence: .daily,
      target: 1,
      at: now,
      timeZone: zone
    )
    let invalidBucket = try #require(
      try buckets(for: invalidHabit, in: invalidContext).first
    )
    invalidContext.insert(
      LogEntry(
        timestamp: now,
        amount: 0,
        habit: invalidHabit,
        bucket: invalidBucket
      )
    )
    try invalidContext.save()
    try expectError(BucketEvaluationError.invalidEntryAmount(0)) {
      _ = try HabitLoggingComputation(context: invalidContext).snapshot(
        for: invalidHabit,
        at: now,
        timeZone: zone
      )
    }
  }

  private func loggedFixture(
    name: String,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> (
    context: ModelContext,
    habit: Habit,
    bucket: HabitBucket,
    entry: LogEntry
  ) {
    let context = try makeContext()
    let habit = try create(
      in: context,
      name: name,
      cadence: .daily,
      target: 2,
      at: instant,
      timeZone: timeZone
    )
    let entry = try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: instant,
      timeZone: timeZone
    )
    return (
      context,
      habit,
      try #require(entry.bucket),
      entry
    )
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

  private func buckets(for habit: Habit, in context: ModelContext) throws -> [HabitBucket] {
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

private enum LoggingSaveFailure: Error, Equatable {
  case expected
}
