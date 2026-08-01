import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Habit activity operations")
struct HabitActivityOperationsTests {
  @Test("daily deactivation reconciles then exempts current and grace")
  func dailyDeactivationReconcilesThenExemptsEditableBuckets() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let logging = LogEntryOperations(context: context)
    let finalEntry = try logging.append(
      amount: 1,
      to: habit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let graceEntry = try logging.append(
      amount: 2,
      to: habit,
      at: instant("2024-01-02T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let operationInstant = try instant("2024-01-03T12:00:00Z")
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      try context.save()
    }

    try operations.deactivate(
      habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    let activityPeriod = try #require(habit.activityPeriods?.first)
    let persistedBuckets = try buckets(for: habit, in: context)
    let final = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-01-01" }
    )
    let grace = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-01-02" }
    )
    let current = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-01-03" }
    )
    #expect(!habit.isActive)
    #expect(activityPeriod.endedAt == operationInstant)
    #expect(lifecycleSaveCount == 1)
    #expect(
      persistedBuckets.map(\.periodKey) == [
        "day:2024-01-01", "day:2024-01-02", "day:2024-01-03",
      ])
    #expect(!final.isExempt)
    #expect(final.finalizedAt == (try instant("2024-01-03T00:00:00Z")))
    #expect(final.verdictRawValue == BucketVerdict.met.rawValue)
    #expect(
      final.entries?.map(\.persistentModelID) == [
        finalEntry.persistentModelID
      ])
    #expect(grace.isExempt)
    #expect(grace.finalizedAt == nil)
    #expect(
      grace.entries?.map(\.persistentModelID) == [
        graceEntry.persistentModelID
      ])
    #expect(current.isExempt)
    #expect(current.entries?.isEmpty == true)
    #expect(
      try entries(in: context).map(\.persistentModelID).sorted()
        == [
          finalEntry.persistentModelID, graceEntry.persistentModelID,
        ].sorted())
    #expect(!context.hasChanges)

    try BucketReconciler(context: context).reconcile(
      habit: habit,
      at: instant("2024-01-10T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    #expect(
      try buckets(for: habit, in: context).map(\.periodKey) == [
        "day:2024-01-01", "day:2024-01-02", "day:2024-01-03",
      ])
  }

  @Test("Monday weekly deactivation exempts met grace and current week")
  func mondayWeeklyDeactivationExemptsGraceAndCurrent() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .weekly,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let entry = try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: instant("2024-01-04T18:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let operationInstant = try instant("2024-01-08T12:00:00Z")
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      try context.save()
    }

    try operations.deactivate(
      habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    let persistedBuckets = try buckets(for: habit, in: context)
    let grace = try #require(
      persistedBuckets.first { $0.periodKey == "week:2024-01-01" }
    )
    let current = try #require(
      persistedBuckets.first { $0.periodKey == "week:2024-01-08" }
    )
    #expect(!habit.isActive)
    #expect(habit.activityPeriods?.first?.endedAt == operationInstant)
    #expect(lifecycleSaveCount == 1)
    #expect(
      persistedBuckets.map(\.periodKey) == [
        "week:2024-01-01", "week:2024-01-08",
      ])
    #expect(grace.isExempt)
    #expect(grace.finalizedAt == nil)
    #expect(grace.entries?.map(\.persistentModelID) == [entry.persistentModelID])
    #expect(current.isExempt)
    #expect(current.entries?.isEmpty == true)
    #expect(!context.hasChanges)
  }

  @Test("daily grace end across spring forward finalizes before exemption")
  func dailyGraceEndAcrossSpringForwardFinalizesBeforeExemption() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-03-09T20:00:00Z"
    )
    let operationInstant = try instant("2024-03-11T07:00:00Z")
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      try context.save()
    }

    try operations.deactivate(
      habit,
      at: operationInstant,
      timeZone: timeZone("America/Los_Angeles")
    )

    let persistedBuckets = try buckets(for: habit, in: context)
    let final = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-03-09" }
    )
    let grace = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-03-10" }
    )
    let current = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-03-11" }
    )
    #expect(lifecycleSaveCount == 1)
    #expect(!habit.isActive)
    #expect(habit.activityPeriods?.first?.endedAt == operationInstant)
    #expect(
      persistedBuckets.map(\.periodKey) == [
        "day:2024-03-09", "day:2024-03-10", "day:2024-03-11",
      ])
    #expect(final.startAt == (try instant("2024-03-09T08:00:00Z")))
    #expect(final.endAt == (try instant("2024-03-10T08:00:00Z")))
    #expect(final.finalizedAt == operationInstant)
    #expect(final.verdictRawValue == BucketVerdict.missed.rawValue)
    #expect(!final.isExempt)
    #expect(grace.startAt == (try instant("2024-03-10T08:00:00Z")))
    #expect(grace.endAt == operationInstant)
    #expect(grace.endAt.timeIntervalSince(grace.startAt) == 23 * 60 * 60)
    #expect(grace.finalizedAt == nil)
    #expect(grace.isExempt)
    #expect(current.startAt == operationInstant)
    #expect(current.endAt == (try instant("2024-03-12T07:00:00Z")))
    #expect(current.isExempt)
    #expect(!context.hasChanges)
  }

  @Test("weekly grace end after spring forward preserves final facts")
  func weeklyGraceEndAfterSpringForwardPreservesFinalFacts() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .weekly,
      target: 1,
      activityStart: "2024-03-04T16:00:00Z"
    )
    let operationInstant = try instant("2024-03-12T07:00:00Z")
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      try context.save()
    }

    try operations.deactivate(
      habit,
      at: operationInstant,
      timeZone: timeZone("America/Los_Angeles")
    )

    let persistedBuckets = try buckets(for: habit, in: context)
    let final = try #require(
      persistedBuckets.first { $0.periodKey == "week:2024-03-04" }
    )
    let current = try #require(
      persistedBuckets.first { $0.periodKey == "week:2024-03-11" }
    )
    #expect(lifecycleSaveCount == 1)
    #expect(!habit.isActive)
    #expect(habit.activityPeriods?.first?.endedAt == operationInstant)
    #expect(
      persistedBuckets.map(\.periodKey) == [
        "week:2024-03-04", "week:2024-03-11",
      ])
    #expect(final.startAt == (try instant("2024-03-04T08:00:00Z")))
    #expect(final.endAt == (try instant("2024-03-11T07:00:00Z")))
    #expect(final.endAt.timeIntervalSince(final.startAt) == 167 * 60 * 60)
    #expect(final.finalizedAt == operationInstant)
    #expect(final.verdictRawValue == BucketVerdict.missed.rawValue)
    #expect(!final.isExempt)
    #expect(current.startAt == (try instant("2024-03-11T07:00:00Z")))
    #expect(current.endAt == (try instant("2024-03-18T07:00:00Z")))
    #expect(current.finalizedAt == nil)
    #expect(current.isExempt)
    #expect(!context.hasChanges)
  }

  @Test("daily same-period reactivation restores the exact bucket and entries")
  func dailySamePeriodReactivationRestoresBucketAndEntries() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T08:00:00Z"
    )
    let entry = try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: instant("2024-01-01T10:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let secondEntry = try LogEntryOperations(context: context).append(
      amount: 2,
      to: habit,
      at: instant("2024-01-01T11:00:00Z"),
      timeZone: timeZone("UTC")
    )
    try HabitActivityOperations(context: context).deactivate(
      habit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let exemptBucket = try #require(buckets(for: habit, in: context).first)
    let bucketIdentifier = exemptBucket.persistentModelID
    exemptBucket.startAt = try instant("2023-12-31T23:00:00Z")
    exemptBucket.endAt = try instant("2024-01-01T23:00:00Z")
    try context.save()
    let operationInstant = try instant("2024-01-01T18:00:00Z")
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      try context.save()
    }

    try operations.reactivate(
      habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    let restored = try #require(buckets(for: habit, in: context).first)
    let activityPeriods = try #require(habit.activityPeriods).sorted {
      $0.startedAt < $1.startedAt
    }
    #expect(habit.isActive)
    #expect(lifecycleSaveCount == 1)
    #expect(activityPeriods.count == 2)
    #expect(activityPeriods[0].endedAt == (try instant("2024-01-01T12:00:00Z")))
    #expect(activityPeriods[1].startedAt == operationInstant)
    #expect(activityPeriods[1].endedAt == nil)
    #expect(restored.persistentModelID == bucketIdentifier)
    #expect(!restored.isExempt)
    #expect(restored.startAt == (try instant("2024-01-01T00:00:00Z")))
    #expect(restored.endAt == (try instant("2024-01-02T00:00:00Z")))
    #expect(
      restored.entries?.map(\.persistentModelID).sorted()
        == [
          entry.persistentModelID, secondEntry.persistentModelID,
        ].sorted())
    #expect(
      try buckets(for: habit, in: context).map(\.periodKey) == [
        "day:2024-01-01"
      ])
    #expect(!context.hasChanges)
  }

  @Test("Monday weekly reactivation restores current but not prior grace")
  func mondayWeeklyReactivationRestoresOnlyCurrentBucket() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .weekly,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    habit.pinnedWeekdaysRawValue = PinnedWeekdays.wednesday.rawValue
    try context.save()
    let entry = try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: instant("2024-01-04T18:00:00Z"),
      timeZone: timeZone("UTC")
    )
    try HabitActivityOperations(context: context).deactivate(
      habit,
      at: instant("2024-01-08T00:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let before = try buckets(for: habit, in: context)
    let graceIdentifier = try #require(
      before.first { $0.periodKey == "week:2024-01-01" }
    ).persistentModelID
    let currentIdentifier = try #require(
      before.first { $0.periodKey == "week:2024-01-08" }
    ).persistentModelID
    let operationInstant = try instant("2024-01-08T00:00:00Z")
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      try context.save()
    }

    try operations.reactivate(
      habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    let persistedBuckets = try buckets(for: habit, in: context)
    let grace = try #require(
      persistedBuckets.first { $0.periodKey == "week:2024-01-01" }
    )
    let current = try #require(
      persistedBuckets.first { $0.periodKey == "week:2024-01-08" }
    )
    let openPeriod = try #require(
      habit.activityPeriods?.first { $0.endedAt == nil }
    )
    #expect(habit.isActive)
    #expect(lifecycleSaveCount == 1)
    #expect(openPeriod.startedAt == operationInstant)
    #expect(grace.persistentModelID == graceIdentifier)
    #expect(grace.isExempt)
    #expect(grace.entries?.map(\.persistentModelID) == [entry.persistentModelID])
    #expect(current.persistentModelID == currentIdentifier)
    #expect(!current.isExempt)
    #expect(current.entries?.isEmpty == true)
    #expect(
      persistedBuckets.map(\.periodKey) == [
        "week:2024-01-01", "week:2024-01-08",
      ])
    #expect(!context.hasChanges)
  }

  @Test("later daily reactivation creates only the current DST bucket")
  func laterDailyReactivationCreatesOnlyCurrentBucket() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-03-09T20:00:00Z"
    )
    try HabitActivityOperations(context: context).deactivate(
      habit,
      at: instant("2024-03-09T22:00:00Z"),
      timeZone: timeZone("America/Los_Angeles")
    )
    let oldBucket = try #require(buckets(for: habit, in: context).first)
    let oldBucketIdentifier = oldBucket.persistentModelID
    let operationInstant = try instant("2024-03-12T15:00:00Z")
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      try context.save()
    }

    try operations.reactivate(
      habit,
      at: operationInstant,
      timeZone: timeZone("America/Los_Angeles")
    )

    let persistedBuckets = try buckets(for: habit, in: context)
    let historical = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-03-09" }
    )
    let current = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-03-12" }
    )
    #expect(habit.isActive)
    #expect(lifecycleSaveCount == 1)
    #expect(
      persistedBuckets.map(\.periodKey) == [
        "day:2024-03-09", "day:2024-03-12",
      ])
    #expect(historical.persistentModelID == oldBucketIdentifier)
    #expect(historical.isExempt)
    #expect(current.startAt == (try instant("2024-03-12T07:00:00Z")))
    #expect(current.endAt == (try instant("2024-03-13T07:00:00Z")))
    #expect(!current.isExempt)
    #expect(current.finalizedAt == nil)
    #expect(current.entries?.isEmpty == true)
    #expect(habit.activityPeriods?.count == 2)
    #expect(
      habit.activityPeriods?.first { $0.endedAt == nil }?.startedAt
        == operationInstant)
    #expect(!context.hasChanges)
  }

  @Test("time-zone key change creates a new bucket at a touching boundary")
  func timeZoneKeyChangeCreatesNewBucketAtTouchingBoundary() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operationInstant = try instant("2024-01-01T15:00:00Z")
    try HabitActivityOperations(context: context).deactivate(
      habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    let historical = try #require(buckets(for: habit, in: context).first)

    try HabitActivityOperations(context: context).reactivate(
      habit,
      at: operationInstant,
      timeZone: timeZone("Asia/Tokyo")
    )

    let persistedBuckets = try buckets(for: habit, in: context)
    let current = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-01-02" }
    )
    let activityPeriods = try #require(habit.activityPeriods).sorted {
      $0.startedAt < $1.startedAt
    }
    #expect(habit.isActive)
    #expect(
      persistedBuckets.map(\.periodKey) == [
        "day:2024-01-01", "day:2024-01-02",
      ])
    #expect(historical.isExempt)
    #expect(current.startAt == operationInstant)
    #expect(current.endAt == (try instant("2024-01-02T15:00:00Z")))
    #expect(!current.isExempt)
    #expect(activityPeriods.count == 2)
    #expect(activityPeriods[0].endedAt == operationInstant)
    #expect(activityPeriods[1].startedAt == operationInstant)
    #expect(activityPeriods[1].endedAt == nil)
    #expect(!context.hasChanges)
  }

  @Test("reactivation state errors win before lifecycle mutation")
  func reactivationStateErrorsWinBeforeMutation() throws {
    let context = try makeContext()
    let active = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let inactiveOpen = Habit(
      name: "Open",
      cadence: .daily,
      target: 1,
      isActive: false
    )
    inactiveOpen.activityPeriods = [
      HabitActivityPeriod(startedAt: try instant("2024-01-01T00:00:00Z"))
    ]
    let missingClosed = Habit(
      name: "Missing",
      cadence: .daily,
      target: 1,
      isActive: false
    )
    let overlapping = Habit(
      name: "Overlap",
      cadence: .daily,
      target: 1,
      isActive: false
    )
    overlapping.activityPeriods = [
      HabitActivityPeriod(
        startedAt: try instant("2024-01-01T00:00:00Z"),
        endedAt: try instant("2024-01-03T00:00:00Z")
      ),
      HabitActivityPeriod(
        startedAt: try instant("2024-01-02T00:00:00Z"),
        endedAt: try instant("2024-01-04T00:00:00Z")
      ),
    ]
    let backward = Habit(
      name: "Backward",
      cadence: .daily,
      target: 1,
      isActive: false
    )
    backward.activityPeriods = [
      HabitActivityPeriod(
        startedAt: try instant("2024-01-01T00:00:00Z"),
        endedAt: try instant("2024-01-02T00:00:00Z")
      )
    ]
    let detached = Habit(
      name: "Detached",
      cadence: .daily,
      target: 1,
      isActive: false
    )
    detached.activityPeriods = [
      HabitActivityPeriod(
        startedAt: try instant("2024-01-01T00:00:00Z"),
        endedAt: try instant("2024-01-02T00:00:00Z")
      )
    ]
    context.insert(inactiveOpen)
    context.insert(missingClosed)
    context.insert(overlapping)
    context.insert(backward)
    try context.save()
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      try context.save()
    }

    try expectActivityError(.detachedHabit) {
      try operations.reactivate(
        detached,
        at: instant("2024-01-05T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    try expectActivityError(.alreadyActive) {
      try operations.reactivate(
        active,
        at: instant("2024-01-05T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    try expectActivityError(.unexpectedOpenActivityPeriod) {
      try operations.reactivate(
        inactiveOpen,
        at: instant("2024-01-05T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    try expectActivityError(.missingClosedActivityPeriod) {
      try operations.reactivate(
        missingClosed,
        at: instant("2024-01-05T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    try expectActivityError(.invalidActivityChronology) {
      try operations.reactivate(
        overlapping,
        at: instant("2024-01-05T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    try expectActivityError(.invalidActivityChronology) {
      try operations.reactivate(
        backward,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    #expect(lifecycleSaveCount == 0)
    #expect(active.isActive)
    #expect(!inactiveOpen.isActive)
    #expect(!missingClosed.isActive)
    #expect(!overlapping.isActive)
    #expect(!backward.isActive)
    #expect(!context.hasChanges)
  }

  @Test("reactivation refuses contradictory current bucket state")
  func reactivationRefusesContradictoryCurrentBuckets() throws {
    let nonExemptContext = try makeContext()
    let nonExemptHabit = try insertInactiveHabit(
      in: nonExemptContext,
      activityStart: "2024-01-01T00:00:00Z",
      activityEnd: "2024-01-01T12:00:00Z"
    )
    let nonExempt = HabitBucket(
      periodKey: "day:2024-01-01",
      startAt: try instant("2024-01-01T00:00:00Z"),
      endAt: try instant("2024-01-02T00:00:00Z"),
      cadence: .daily,
      habit: nonExemptHabit
    )
    nonExemptContext.insert(nonExempt)
    try nonExemptContext.save()
    var nonExemptSaveCount = 0
    let nonExemptOperations = HabitActivityOperations(
      context: nonExemptContext
    ) {
      nonExemptSaveCount += 1
      try nonExemptContext.save()
    }
    try expectActivityError(
      .unexpectedBucketPhase(key: "day:2024-01-01", phase: .open)
    ) {
      try nonExemptOperations.reactivate(
        nonExemptHabit,
        at: instant("2024-01-01T18:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let duplicateContext = try makeContext()
    let duplicateHabit = try insertInactiveHabit(
      in: duplicateContext,
      activityStart: "2024-01-01T00:00:00Z",
      activityEnd: "2024-01-01T12:00:00Z"
    )
    for _ in 0..<2 {
      duplicateContext.insert(
        HabitBucket(
          periodKey: "day:2024-01-01",
          startAt: try instant("2024-01-01T00:00:00Z"),
          endAt: try instant("2024-01-02T00:00:00Z"),
          cadence: .daily,
          isExempt: true,
          habit: duplicateHabit
        ))
    }
    try duplicateContext.save()
    var duplicateSaveCount = 0
    let duplicateOperations = HabitActivityOperations(context: duplicateContext) {
      duplicateSaveCount += 1
      try duplicateContext.save()
    }
    try expectActivityError(.duplicatePeriodKey("day:2024-01-01")) {
      try duplicateOperations.reactivate(
        duplicateHabit,
        at: instant("2024-01-01T18:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let mismatchContext = try makeContext()
    let mismatchHabit = try insertInactiveHabit(
      in: mismatchContext,
      activityStart: "2024-01-01T00:00:00Z",
      activityEnd: "2024-01-01T12:00:00Z"
    )
    let unrelatedCurrent = HabitBucket(
      periodKey: "day:2024-01-02",
      startAt: try instant("2024-01-02T00:00:00Z"),
      endAt: try instant("2024-01-03T00:00:00Z"),
      cadence: .daily,
      isExempt: true,
      habit: mismatchHabit
    )
    mismatchContext.insert(unrelatedCurrent)
    try mismatchContext.save()
    var mismatchSaveCount = 0
    let mismatchOperations = HabitActivityOperations(context: mismatchContext) {
      mismatchSaveCount += 1
      try mismatchContext.save()
    }
    try expectActivityError(
      .currentBucketActivityBoundaryMismatch("day:2024-01-02")
    ) {
      try mismatchOperations.reactivate(
        mismatchHabit,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let finalContext = try makeContext()
    let finalHabit = try insertInactiveHabit(
      in: finalContext,
      activityStart: "2024-01-02T00:00:00Z",
      activityEnd: "2024-01-02T02:00:00Z"
    )
    let finalCurrent = HabitBucket(
      periodKey: "day:2024-01-02",
      startAt: try instant("2024-01-02T00:00:00Z"),
      endAt: try instant("2024-01-03T00:00:00Z"),
      cadence: .daily,
      finalizedAt: try instant("2024-01-02T06:00:00Z"),
      verdict: .missed,
      targetSnapshot: 1,
      unitSnapshot: "times",
      habit: finalHabit
    )
    finalContext.insert(finalCurrent)
    try finalContext.save()
    var finalSaveCount = 0
    let finalOperations = HabitActivityOperations(context: finalContext) {
      finalSaveCount += 1
      try finalContext.save()
    }
    try expectActivityError(
      .unexpectedBucketPhase(key: "day:2024-01-02", phase: .final)
    ) {
      try finalOperations.reactivate(
        finalHabit,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    #expect(nonExemptSaveCount == 0)
    #expect(duplicateSaveCount == 0)
    #expect(mismatchSaveCount == 0)
    #expect(finalSaveCount == 0)
    #expect(!nonExemptHabit.isActive)
    #expect(!duplicateHabit.isActive)
    #expect(!mismatchHabit.isActive)
    #expect(!finalHabit.isActive)
    #expect(!nonExemptContext.hasChanges)
    #expect(!duplicateContext.hasChanges)
    #expect(!mismatchContext.hasChanges)
    #expect(!finalContext.hasChanges)
  }

  @Test("reactivation propagates unrestorable bucket evaluation errors")
  func reactivationPropagatesBucketEvaluationErrors() throws {
    let cadenceContext = try makeContext()
    let cadenceHabit = try insertInactiveHabit(
      in: cadenceContext,
      activityStart: "2024-01-01T00:00:00Z",
      activityEnd: "2024-01-01T12:00:00Z"
    )
    let cadenceMismatch = HabitBucket(
      periodKey: "day:2024-01-01",
      startAt: try instant("2024-01-01T00:00:00Z"),
      endAt: try instant("2024-01-02T00:00:00Z"),
      cadence: .weekly,
      isExempt: true,
      habit: cadenceHabit
    )
    cadenceContext.insert(cadenceMismatch)
    try cadenceContext.save()
    var cadenceSaveCount = 0
    let cadenceOperations = HabitActivityOperations(context: cadenceContext) {
      cadenceSaveCount += 1
      try cadenceContext.save()
    }
    do {
      try cadenceOperations.reactivate(
        cadenceHabit,
        at: instant("2024-01-01T18:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected cadence mismatch")
    } catch let error as BucketEvaluationError {
      #expect(error == .cadenceMismatch(habit: .daily, bucket: .weekly))
    }

    let malformedContext = try makeContext()
    let malformedHabit = try insertInactiveHabit(
      in: malformedContext,
      activityStart: "2024-01-01T00:00:00Z",
      activityEnd: "2024-01-01T12:00:00Z"
    )
    let malformed = HabitBucket(
      periodKey: "not-a-period",
      startAt: try instant("2024-01-01T00:00:00Z"),
      endAt: try instant("2024-01-02T00:00:00Z"),
      cadence: .daily,
      isExempt: true,
      habit: malformedHabit
    )
    malformedContext.insert(malformed)
    try malformedContext.save()
    var malformedSaveCount = 0
    let malformedOperations = HabitActivityOperations(context: malformedContext) {
      malformedSaveCount += 1
      try malformedContext.save()
    }
    do {
      try malformedOperations.reactivate(
        malformedHabit,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected malformed period key")
    } catch let error as BucketEvaluationError {
      #expect(error == .calendar(.malformedKey("not-a-period")))
    }

    let progressContext = try makeContext()
    let progressHabit = try insertInactiveHabit(
      in: progressContext,
      activityStart: "2024-01-01T00:00:00Z",
      activityEnd: "2024-01-01T12:00:00Z"
    )
    let progressBucket = HabitBucket(
      periodKey: "day:2024-01-01",
      startAt: try instant("2024-01-01T00:00:00Z"),
      endAt: try instant("2024-01-02T00:00:00Z"),
      cadence: .daily,
      isExempt: true,
      habit: progressHabit
    )
    let invalidEntry = LogEntry(
      timestamp: try instant("2024-01-01T10:00:00Z"),
      amount: 0,
      habit: progressHabit,
      bucket: progressBucket
    )
    progressContext.insert(progressBucket)
    progressContext.insert(invalidEntry)
    try progressContext.save()
    var progressSaveCount = 0
    let progressOperations = HabitActivityOperations(context: progressContext) {
      progressSaveCount += 1
      try progressContext.save()
    }
    do {
      try progressOperations.reactivate(
        progressHabit,
        at: instant("2024-01-01T18:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected invalid entry amount")
    } catch let error as BucketEvaluationError {
      #expect(error == .invalidEntryAmount(0))
    }

    #expect(cadenceSaveCount == 0)
    #expect(malformedSaveCount == 0)
    #expect(progressSaveCount == 0)
    #expect(!cadenceHabit.isActive)
    #expect(!malformedHabit.isActive)
    #expect(!progressHabit.isActive)
    #expect(!cadenceContext.hasChanges)
    #expect(!malformedContext.hasChanges)
    #expect(!progressContext.hasChanges)
  }

  @Test("reactivation restore failure rolls back bucket and activity insertion")
  func reactivationRestoreFailureRollsBackLifecycleMutation() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let entry = try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: instant("2024-01-01T10:00:00Z"),
      timeZone: timeZone("UTC")
    )
    try HabitActivityOperations(context: context).deactivate(
      habit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let exemptBucket = try #require(buckets(for: habit, in: context).first)
    exemptBucket.startAt = try instant("2023-12-31T23:00:00Z")
    exemptBucket.endAt = try instant("2024-01-01T23:00:00Z")
    try context.save()
    let bucketIdentifier = exemptBucket.persistentModelID
    let closedPeriod = try #require(habit.activityPeriods?.first)
    let closedPeriodIdentifier = closedPeriod.persistentModelID
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      throw SaveFailure.expected
    }

    do {
      try operations.reactivate(
        habit,
        at: instant("2024-01-01T18:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected save failure")
    } catch let error as SaveFailure {
      #expect(error == .expected)
    }

    let persistedBucket = try #require(buckets(for: habit, in: context).first)
    let persistedPeriods = try #require(habit.activityPeriods)
    #expect(lifecycleSaveCount == 1)
    #expect(!habit.isActive)
    #expect(persistedPeriods.count == 1)
    #expect(persistedPeriods[0].persistentModelID == closedPeriodIdentifier)
    #expect(persistedPeriods[0].endedAt == (try instant("2024-01-01T12:00:00Z")))
    #expect(persistedPeriods[0].habit?.persistentModelID == habit.persistentModelID)
    #expect(persistedBucket.persistentModelID == bucketIdentifier)
    #expect(persistedBucket.isExempt)
    #expect(persistedBucket.startAt == (try instant("2023-12-31T23:00:00Z")))
    #expect(persistedBucket.endAt == (try instant("2024-01-01T23:00:00Z")))
    #expect(
      persistedBucket.entries?.map(\.persistentModelID) == [
        entry.persistentModelID
      ])
    #expect(entry.habit?.persistentModelID == habit.persistentModelID)
    #expect(entry.bucket?.persistentModelID == bucketIdentifier)
    #expect(!context.hasChanges)
  }

  @Test("reactivation creation failure removes inserted bucket and activity")
  func reactivationCreationFailureRemovesInsertedModels() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let entry = try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: instant("2024-01-01T10:00:00Z"),
      timeZone: timeZone("UTC")
    )
    try HabitActivityOperations(context: context).deactivate(
      habit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let historicalBucket = try #require(buckets(for: habit, in: context).first)
    let historicalIdentifier = historicalBucket.persistentModelID
    let closedPeriod = try #require(habit.activityPeriods?.first)
    let closedPeriodIdentifier = closedPeriod.persistentModelID
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      throw SaveFailure.expected
    }

    do {
      try operations.reactivate(
        habit,
        at: instant("2024-01-03T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected save failure")
    } catch let error as SaveFailure {
      #expect(error == .expected)
    }

    let persistedBuckets = try buckets(for: habit, in: context)
    let persistedPeriods = try #require(habit.activityPeriods)
    #expect(lifecycleSaveCount == 1)
    #expect(!habit.isActive)
    #expect(persistedBuckets.map(\.persistentModelID) == [historicalIdentifier])
    #expect(persistedBuckets[0].periodKey == "day:2024-01-01")
    #expect(persistedBuckets[0].isExempt)
    #expect(persistedPeriods.count == 1)
    #expect(persistedPeriods[0].persistentModelID == closedPeriodIdentifier)
    #expect(persistedPeriods[0].endedAt == (try instant("2024-01-01T12:00:00Z")))
    #expect(entry.habit?.persistentModelID == habit.persistentModelID)
    #expect(entry.bucket?.persistentModelID == historicalIdentifier)
    #expect(
      try entries(in: context).map(\.persistentModelID) == [
        entry.persistentModelID
      ])
    #expect(!context.hasChanges)
  }

  @Test("repeated lifecycle cycles keep periods ordered and bucket keys unique")
  func repeatedLifecycleCyclesRemainCanonical() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operations = HabitActivityOperations(context: context)

    try operations.deactivate(
      habit,
      at: instant("2024-01-01T08:00:00Z"),
      timeZone: timeZone("UTC")
    )
    try operations.reactivate(
      habit,
      at: instant("2024-01-01T10:00:00Z"),
      timeZone: timeZone("UTC")
    )
    try operations.deactivate(
      habit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    try operations.reactivate(
      habit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )

    let activityPeriods = try #require(habit.activityPeriods).sorted {
      $0.startedAt < $1.startedAt
    }
    let persistedBuckets = try buckets(for: habit, in: context)
    #expect(habit.isActive)
    #expect(activityPeriods.count == 3)
    #expect(activityPeriods[0].startedAt == (try instant("2024-01-01T00:00:00Z")))
    #expect(activityPeriods[0].endedAt == (try instant("2024-01-01T08:00:00Z")))
    #expect(activityPeriods[1].startedAt == (try instant("2024-01-01T10:00:00Z")))
    #expect(activityPeriods[1].endedAt == (try instant("2024-01-01T12:00:00Z")))
    #expect(activityPeriods[2].startedAt == (try instant("2024-01-01T12:00:00Z")))
    #expect(activityPeriods[2].endedAt == nil)
    #expect(persistedBuckets.map(\.periodKey) == ["day:2024-01-01"])
    #expect(!persistedBuckets[0].isExempt)
    #expect(!context.hasChanges)
  }

  @Test("reactivation isolates habits sharing an ordinary UUID")
  func reactivationUsesPersistentHabitIdentity() throws {
    let context = try makeContext()
    let sharedID = UUID()
    let first = try insertInactiveHabit(
      in: context,
      activityStart: "2024-01-01T00:00:00Z",
      activityEnd: "2024-01-01T12:00:00Z",
      id: sharedID
    )
    let second = try insertInactiveHabit(
      in: context,
      activityStart: "2024-01-01T00:00:00Z",
      activityEnd: "2024-01-01T12:00:00Z",
      id: sharedID
    )
    let secondBucket = HabitBucket(
      periodKey: "day:2024-01-01",
      startAt: try instant("2024-01-01T00:00:00Z"),
      endAt: try instant("2024-01-02T00:00:00Z"),
      cadence: .daily,
      isExempt: true,
      habit: second
    )
    context.insert(secondBucket)
    try context.save()

    try HabitActivityOperations(context: context).reactivate(
      first,
      at: instant("2024-01-01T18:00:00Z"),
      timeZone: timeZone("UTC")
    )

    let firstBucket = try #require(buckets(for: first, in: context).first)
    #expect(first.isActive)
    #expect(!firstBucket.isExempt)
    #expect(firstBucket.habit?.persistentModelID == first.persistentModelID)
    #expect(!second.isActive)
    #expect(second.activityPeriods?.count == 1)
    #expect(secondBucket.isExempt)
    #expect(secondBucket.habit?.persistentModelID == second.persistentModelID)
    #expect(
      try buckets(for: second, in: context).map(\.persistentModelID) == [
        secondBucket.persistentModelID
      ])
    #expect(!context.hasChanges)
  }

  @Test("transition state errors win before lifecycle mutation")
  func transitionStateErrorsWinBeforeMutation() throws {
    let context = try makeContext()
    let operationInstant = try instant("2024-01-03T12:00:00Z")
    let detached = Habit(name: "Detached", cadence: .daily, target: 1)
    detached.activityPeriods = [
      HabitActivityPeriod(startedAt: try instant("2024-01-01T00:00:00Z"))
    ]
    let inactive = Habit(
      name: "Inactive",
      cadence: .daily,
      target: 1,
      isActive: false
    )
    inactive.activityPeriods = [
      HabitActivityPeriod(
        startedAt: try instant("2024-01-01T00:00:00Z"),
        endedAt: try instant("2024-01-02T00:00:00Z")
      )
    ]
    let missingOpen = Habit(name: "Missing", cadence: .daily, target: 1)
    let multipleOpen = Habit(name: "Multiple", cadence: .daily, target: 1)
    multipleOpen.activityPeriods = [
      HabitActivityPeriod(startedAt: try instant("2024-01-01T00:00:00Z")),
      HabitActivityPeriod(startedAt: try instant("2024-01-02T00:00:00Z")),
    ]
    context.insert(inactive)
    context.insert(missingOpen)
    context.insert(multipleOpen)
    try context.save()
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      try context.save()
    }

    try expectActivityError(.detachedHabit) {
      try operations.deactivate(
        detached,
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }
    try expectActivityError(.alreadyInactive) {
      try operations.deactivate(
        inactive,
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }
    try expectActivityError(.missingOpenActivityPeriod) {
      try operations.deactivate(
        missingOpen,
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }
    try expectActivityError(.multipleOpenActivityPeriods) {
      try operations.deactivate(
        multipleOpen,
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }
    #expect(lifecycleSaveCount == 0)
    #expect(
      inactive.activityPeriods?.first?.endedAt
        == (try instant(
          "2024-01-02T00:00:00Z"
        )))
    #expect(!context.hasChanges)
  }

  @Test("overlapping and backward activity histories are rejected")
  func invalidActivityHistoriesAreRejected() throws {
    let operationInstant = try instant("2024-01-05T12:00:00Z")

    let overlappingContext = try makeContext()
    let overlapping = Habit(name: "Overlap", cadence: .daily, target: 1)
    overlapping.activityPeriods = [
      HabitActivityPeriod(
        startedAt: try instant("2024-01-01T00:00:00Z"),
        endedAt: try instant("2024-01-04T00:00:00Z")
      ),
      HabitActivityPeriod(startedAt: try instant("2024-01-03T00:00:00Z")),
    ]
    overlappingContext.insert(overlapping)
    try overlappingContext.save()
    var overlappingSaveCount = 0
    let overlappingOperations = HabitActivityOperations(
      context: overlappingContext
    ) {
      overlappingSaveCount += 1
      try overlappingContext.save()
    }
    try expectActivityError(.invalidActivityChronology) {
      try overlappingOperations.deactivate(
        overlapping,
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }

    let backwardContext = try makeContext()
    let backward = Habit(name: "Backward", cadence: .daily, target: 1)
    backward.activityPeriods = [
      HabitActivityPeriod(
        startedAt: try instant("2024-01-03T00:00:00Z"),
        endedAt: try instant("2024-01-02T00:00:00Z")
      ),
      HabitActivityPeriod(startedAt: try instant("2024-01-04T00:00:00Z")),
    ]
    backwardContext.insert(backward)
    try backwardContext.save()
    var backwardSaveCount = 0
    let backwardOperations = HabitActivityOperations(context: backwardContext) {
      backwardSaveCount += 1
      try backwardContext.save()
    }
    try expectActivityError(.invalidActivityChronology) {
      try backwardOperations.deactivate(
        backward,
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }

    #expect(overlappingSaveCount == 0)
    #expect(backwardSaveCount == 0)
    #expect(overlapping.isActive)
    #expect(backward.isActive)
    #expect(!overlappingContext.hasChanges)
    #expect(!backwardContext.hasChanges)
  }

  @Test("duplicate keys and an exempt active current bucket are rejected")
  func duplicateAndContradictoryBucketsAreRejected() throws {
    let utc = try timeZone("UTC")
    let operationInstant = try instant("2024-01-01T12:00:00Z")

    let duplicateContext = try makeContext()
    let duplicateHabit = try insertHabit(
      in: duplicateContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    for _ in 0..<2 {
      duplicateContext.insert(
        HabitBucket(
          periodKey: "day:2024-01-01",
          startAt: try instant("2024-01-01T00:00:00Z"),
          endAt: try instant("2024-01-02T00:00:00Z"),
          cadence: .daily,
          habit: duplicateHabit
        ))
    }
    try duplicateContext.save()
    var duplicateSaveCount = 0
    let duplicateOperations = HabitActivityOperations(context: duplicateContext) {
      duplicateSaveCount += 1
      try duplicateContext.save()
    }
    try expectActivityError(.duplicatePeriodKey("day:2024-01-01")) {
      try duplicateOperations.deactivate(
        duplicateHabit,
        at: operationInstant,
        timeZone: utc
      )
    }

    let exemptContext = try makeContext()
    let exemptHabit = try insertHabit(
      in: exemptContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let exemptCurrent = HabitBucket(
      periodKey: "day:2024-01-01",
      startAt: try instant("2024-01-01T00:00:00Z"),
      endAt: try instant("2024-01-02T00:00:00Z"),
      cadence: .daily,
      isExempt: true,
      habit: exemptHabit
    )
    exemptContext.insert(exemptCurrent)
    try exemptContext.save()
    var exemptSaveCount = 0
    let exemptOperations = HabitActivityOperations(context: exemptContext) {
      exemptSaveCount += 1
      try exemptContext.save()
    }
    try expectActivityError(
      .unexpectedBucketPhase(key: "day:2024-01-01", phase: .exempt)
    ) {
      try exemptOperations.deactivate(
        exemptHabit,
        at: operationInstant,
        timeZone: utc
      )
    }

    #expect(duplicateSaveCount == 0)
    #expect(exemptSaveCount == 0)
    #expect(duplicateHabit.isActive)
    #expect(exemptHabit.isActive)
    #expect(exemptCurrent.isExempt)
    #expect(!duplicateContext.hasChanges)
    #expect(!exemptContext.hasChanges)
  }

  @Test("deactivation save failure retains reconciliation and rolls back lifecycle")
  func deactivationSaveFailureRollsBackOnlyLifecycleMutation() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operationInstant = try instant("2024-01-03T12:00:00Z")
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      throw SaveFailure.expected
    }

    do {
      try operations.deactivate(
        habit,
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected save failure")
    } catch let error as SaveFailure {
      #expect(error == .expected)
    }

    let activityPeriod = try #require(habit.activityPeriods?.first)
    let persistedBuckets = try buckets(for: habit, in: context)
    let final = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-01-01" }
    )
    let grace = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-01-02" }
    )
    let current = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-01-03" }
    )
    #expect(lifecycleSaveCount == 1)
    #expect(habit.isActive)
    #expect(activityPeriod.endedAt == nil)
    #expect(activityPeriod.habit?.persistentModelID == habit.persistentModelID)
    #expect(
      persistedBuckets.map(\.periodKey) == [
        "day:2024-01-01", "day:2024-01-02", "day:2024-01-03",
      ])
    #expect(!final.isExempt)
    #expect(final.finalizedAt == (try instant("2024-01-03T00:00:00Z")))
    #expect(final.verdictRawValue == BucketVerdict.missed.rawValue)
    #expect(!grace.isExempt)
    #expect(!current.isExempt)
    #expect(try entries(in: context).isEmpty)
    #expect(!context.hasChanges)
  }

  @Test("dependent evaluation errors propagate without lifecycle mutation")
  func dependentErrorsPropagateWithoutLifecycleMutation() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    habit.target = 0
    try context.save()
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      try context.save()
    }

    do {
      try operations.deactivate(
        habit,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected invalid requirement")
    } catch let error as BucketEvaluationError {
      #expect(error == .invalidRequirement(0))
    }

    #expect(lifecycleSaveCount == 0)
    #expect(habit.isActive)
    #expect(habit.activityPeriods?.first?.endedAt == nil)
    #expect(try buckets(for: habit, in: context).isEmpty)
    #expect(!context.hasChanges)
  }

  @Test("persistent identity isolates habits sharing an ordinary UUID")
  func persistentIdentityIsolatesHabitsWithSameUUID() throws {
    let context = try makeContext()
    let sharedID = UUID()
    let first = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z",
      id: sharedID
    )
    let second = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z",
      id: sharedID
    )
    let secondBucket = HabitBucket(
      periodKey: "day:2024-01-01",
      startAt: try instant("2024-01-01T00:00:00Z"),
      endAt: try instant("2024-01-02T00:00:00Z"),
      cadence: .daily,
      isExempt: true,
      habit: second
    )
    context.insert(secondBucket)
    try context.save()

    try HabitActivityOperations(context: context).deactivate(
      first,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )

    let firstBucket = try #require(buckets(for: first, in: context).first)
    #expect(!first.isActive)
    #expect(firstBucket.isExempt)
    #expect(second.isActive)
    #expect(second.activityPeriods?.first?.endedAt == nil)
    #expect(secondBucket.isExempt)
    #expect(
      try buckets(for: second, in: context).map(\.persistentModelID) == [
        secondBucket.persistentModelID
      ])
    #expect(!context.hasChanges)
  }

  @Test("deactivation at activation instant creates a zero-length interval")
  func deactivationAtActivationInstantCreatesZeroLengthInterval() throws {
    let context = try makeContext()
    let operationInstant = try instant("2024-01-01T12:00:00Z")
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T12:00:00Z"
    )

    try HabitActivityOperations(context: context).deactivate(
      habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    let bucket = try #require(buckets(for: habit, in: context).first)
    let activityPeriod = try #require(habit.activityPeriods?.first)
    #expect(!habit.isActive)
    #expect(activityPeriod.startedAt == operationInstant)
    #expect(activityPeriod.endedAt == operationInstant)
    #expect(bucket.periodKey == "day:2024-01-01")
    #expect(bucket.isExempt)
    #expect(!context.hasChanges)
  }

  @Test("future open buckets are refused without lifecycle mutation")
  func futureOpenBucketIsRefused() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let future = HabitBucket(
      periodKey: "day:2024-01-02",
      startAt: try instant("2024-01-02T00:00:00Z"),
      endAt: try instant("2024-01-03T00:00:00Z"),
      cadence: .daily,
      habit: habit
    )
    context.insert(future)
    try context.save()
    var lifecycleSaveCount = 0
    let operations = HabitActivityOperations(context: context) {
      lifecycleSaveCount += 1
      try context.save()
    }

    try expectActivityError(
      .unexpectedBucketPhase(key: "day:2024-01-02", phase: .open)
    ) {
      try operations.deactivate(
        habit,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    #expect(lifecycleSaveCount == 0)
    #expect(habit.isActive)
    #expect(habit.activityPeriods?.first?.endedAt == nil)
    #expect(!future.isExempt)
    #expect(!context.hasChanges)
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func insertHabit(
    in context: ModelContext,
    cadence: HabitCadence,
    target: Int,
    activityStart: String,
    id: UUID = UUID()
  ) throws -> Habit {
    let habit = Habit(
      id: id,
      name: "Habit",
      cadence: cadence,
      target: target
    )
    habit.activityPeriods = [
      HabitActivityPeriod(startedAt: try instant(activityStart))
    ]
    context.insert(habit)
    try context.save()
    return habit
  }

  private func insertInactiveHabit(
    in context: ModelContext,
    cadence: HabitCadence = .daily,
    target: Int = 1,
    activityStart: String,
    activityEnd: String,
    id: UUID = UUID()
  ) throws -> Habit {
    let habit = Habit(
      id: id,
      name: "Inactive",
      cadence: cadence,
      target: target,
      isActive: false
    )
    habit.activityPeriods = [
      HabitActivityPeriod(
        startedAt: try instant(activityStart),
        endedAt: try instant(activityEnd)
      )
    ]
    context.insert(habit)
    try context.save()
    return habit
  }

  private func buckets(for habit: Habit, in context: ModelContext) throws
    -> [HabitBucket]
  {
    let habitIdentifier = habit.persistentModelID
    return try context.fetch(FetchDescriptor<HabitBucket>())
      .filter { $0.habit?.persistentModelID == habitIdentifier }
      .sorted { $0.periodKey < $1.periodKey }
  }

  private func entries(in context: ModelContext) throws -> [LogEntry] {
    try context.fetch(FetchDescriptor<LogEntry>())
  }

  private func expectActivityError(
    _ expected: HabitActivityOperationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected HabitActivityOperationError: \(expected)")
    } catch let error as HabitActivityOperationError {
      #expect(error == expected)
    }
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private func timeZone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }
}

private enum SaveFailure: Error, Equatable {
  case expected
}
