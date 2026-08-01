import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Bucket reconciler")
struct BucketReconcilerTests {
  @Test("daily catch-up creates every period from a mid-day activation")
  func dailyCatchUpCreatesEveryPeriodFromMidDayActivation() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 2,
      unit: "times",
      activityStart: "2024-01-01T12:00:00Z"
    )
    var saveCount = 0
    let reconciler = BucketReconciler(context: context) {
      saveCount += 1
      try context.save()
    }

    try reconciler.reconcile(
      habit: habit,
      at: instant("2024-01-04T12:00:00Z"),
      timeZone: timeZone("UTC")
    )

    let buckets = try buckets(for: habit, in: context)
    #expect(
      buckets.map(\.periodKey) == [
        "day:2024-01-01",
        "day:2024-01-02",
        "day:2024-01-03",
        "day:2024-01-04",
      ])
    #expect(saveCount == 1)
    #expect(buckets[0].verdictRawValue == BucketVerdict.missed.rawValue)
    #expect(buckets[0].finalizedAt == (try instant("2024-01-03T00:00:00Z")))
    #expect(buckets[0].targetSnapshot == 2)
    #expect(buckets[0].unitSnapshot == "times")
    #expect(buckets[1].verdictRawValue == BucketVerdict.missed.rawValue)
    #expect(buckets[1].finalizedAt == (try instant("2024-01-04T00:00:00Z")))
    #expect(buckets[2].finalizedAt == nil)
    #expect(buckets[3].finalizedAt == nil)
  }

  @Test("weekly catch-up creates every Monday-start period")
  func weeklyCatchUpCreatesEveryMondayStartPeriod() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .weekly,
      target: 1,
      unit: "post",
      activityStart: "2024-01-03T12:00:00Z"
    )

    try BucketReconciler(context: context).reconcile(
      habit: habit,
      at: instant("2024-01-22T12:00:00Z"),
      timeZone: timeZone("UTC")
    )

    let buckets = try buckets(for: habit, in: context)
    #expect(
      buckets.map(\.periodKey) == [
        "week:2024-01-01",
        "week:2024-01-08",
        "week:2024-01-15",
        "week:2024-01-22",
      ])
    #expect(buckets[0].finalizedAt == (try instant("2024-01-09T00:00:00Z")))
    #expect(buckets[1].finalizedAt == (try instant("2024-01-16T00:00:00Z")))
    #expect(buckets[2].finalizedAt == nil)
    #expect(buckets[3].finalizedAt == nil)
  }

  @Test("inactive habits are a complete no-op")
  func inactiveHabitsAreACompleteNoOp() throws {
    let context = try makeContext()
    let habit = Habit(
      name: "Rest",
      cadence: .daily,
      target: 1,
      isActive: false
    )
    let bucket = HabitBucket(
      periodKey: "day:2024-01-01",
      startAt: Date(timeIntervalSince1970: 10),
      endAt: Date(timeIntervalSince1970: 20),
      cadence: .daily
    )
    habit.buckets = [bucket]
    context.insert(habit)
    try context.save()
    let before = BucketSnapshot(bucket)
    var saveCount = 0

    try BucketReconciler(context: context) {
      saveCount += 1
      try context.save()
    }.reconcile(
      habit: habit,
      at: instant("2024-02-01T00:00:00Z"),
      timeZone: timeZone("UTC")
    )

    #expect(saveCount == 0)
    #expect(BucketSnapshot(bucket) == before)
    #expect(try buckets(for: habit, in: context).count == 1)
  }

  @Test("active habits require exactly one open activity period")
  func activeHabitsRequireExactlyOneOpenActivityPeriod() throws {
    let missingContext = try makeContext()
    let missing = Habit(name: "Read", cadence: .daily, target: 1)
    missingContext.insert(missing)
    try missingContext.save()

    try expectError(.missingOpenActivityPeriod) {
      try BucketReconciler(context: missingContext).reconcile(
        habit: missing,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    #expect(try buckets(for: missing, in: missingContext).isEmpty)

    let multipleContext = try makeContext()
    let multiple = Habit(name: "Read", cadence: .daily, target: 1)
    multiple.activityPeriods = [
      HabitActivityPeriod(
        startedAt: try instant("2024-01-01T00:00:00Z")
      ),
      HabitActivityPeriod(
        startedAt: try instant("2024-01-02T00:00:00Z")
      ),
    ]
    multipleContext.insert(multiple)
    try multipleContext.save()

    try expectError(.multipleOpenActivityPeriods) {
      try BucketReconciler(context: multipleContext).reconcile(
        habit: multiple,
        at: instant("2024-01-03T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    #expect(try buckets(for: multiple, in: multipleContext).isEmpty)
  }

  @Test("reconciliation is idempotent and skips the second save")
  func reconciliationIsIdempotentAndSkipsSecondSave() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      unit: "times",
      activityStart: "2024-01-01T12:00:00Z"
    )
    var saveCount = 0
    let reconciler = BucketReconciler(context: context) {
      saveCount += 1
      try context.save()
    }
    let evaluationInstant = try instant("2024-01-04T12:00:00Z")
    let utc = try timeZone("UTC")

    try reconciler.reconcile(habit: habit, at: evaluationInstant, timeZone: utc)
    let first = try buckets(for: habit, in: context).map(BucketSnapshot.init)
    try reconciler.reconcile(habit: habit, at: evaluationInstant, timeZone: utc)
    let second = try buckets(for: habit, in: context).map(BucketSnapshot.init)

    #expect(saveCount == 1)
    #expect(first == second)
  }

  @Test("time-zone refresh skips final and exempt records")
  func timeZoneRefreshSkipsFinalAndExemptRecords() throws {
    let context = try makeContext()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1, unit: "times")
    let activity = HabitActivityPeriod(
      startedAt: try instant("2024-03-10T12:00:00Z")
    )
    let mutable = HabitBucket(
      periodKey: "day:2024-03-10",
      startAt: Date(timeIntervalSince1970: 10),
      endAt: Date(timeIntervalSince1970: 20),
      cadence: .daily
    )
    let final = HabitBucket(
      periodKey: "day:2024-03-09",
      startAt: Date(timeIntervalSince1970: 30),
      endAt: Date(timeIntervalSince1970: 40),
      cadence: .daily,
      finalizedAt: Date(timeIntervalSince1970: 50),
      verdict: .met,
      targetSnapshot: 1,
      unitSnapshot: "old"
    )
    let exempt = HabitBucket(
      periodKey: "day:2024-03-08",
      startAt: Date(timeIntervalSince1970: 60),
      endAt: Date(timeIntervalSince1970: 70),
      cadence: .daily,
      isExempt: true
    )
    habit.activityPeriods = [activity]
    habit.buckets = [mutable, final, exempt]
    context.insert(habit)
    try context.save()
    let finalBefore = BucketSnapshot(final)
    let exemptBefore = BucketSnapshot(exempt)

    try BucketReconciler(context: context).reconcile(
      habit: habit,
      at: instant("2024-03-10T20:00:00Z"),
      timeZone: timeZone("America/Los_Angeles")
    )

    #expect(mutable.startAt == (try instant("2024-03-10T08:00:00Z")))
    #expect(mutable.endAt == (try instant("2024-03-11T07:00:00Z")))
    #expect(BucketSnapshot(final) == finalBefore)
    #expect(BucketSnapshot(exempt) == exemptBefore)
  }

  @Test("a time-zone key change adds the new key without renaming history")
  func timeZoneKeyChangeAddsNewKeyWithoutRenamingHistory() throws {
    let context = try makeContext()
    let habit = Habit(name: "Read", cadence: .daily, target: 1)
    let activity = HabitActivityPeriod(
      startedAt: try instant("2024-01-01T23:30:00Z")
    )
    let existing = HabitBucket(
      periodKey: "day:2024-01-01",
      startAt: try instant("2024-01-01T00:00:00Z"),
      endAt: try instant("2024-01-02T00:00:00Z"),
      cadence: .daily
    )
    habit.activityPeriods = [activity]
    habit.buckets = [existing]
    context.insert(habit)
    try context.save()

    try BucketReconciler(context: context).reconcile(
      habit: habit,
      at: instant("2024-01-01T23:45:00Z"),
      timeZone: timeZone("Asia/Tokyo")
    )

    let buckets = try buckets(for: habit, in: context)
    #expect(buckets.map(\.periodKey) == ["day:2024-01-01", "day:2024-01-02"])
    #expect(buckets[0].id == existing.id)
    #expect(buckets[1].startAt == (try instant("2024-01-01T15:00:00Z")))
  }

  @Test("duplicate keys are rejected before any mutation")
  func duplicateKeysAreRejectedBeforeAnyMutation() throws {
    let context = try makeContext()
    let habit = Habit(name: "Read", cadence: .daily, target: 1)
    let activity = HabitActivityPeriod(
      startedAt: try instant("2024-01-01T00:00:00Z")
    )
    let first = HabitBucket(
      periodKey: "day:2024-01-01",
      startAt: Date(timeIntervalSince1970: 10),
      endAt: Date(timeIntervalSince1970: 20),
      cadence: .daily
    )
    let second = HabitBucket(
      periodKey: "day:2024-01-01",
      startAt: Date(timeIntervalSince1970: 30),
      endAt: Date(timeIntervalSince1970: 40),
      cadence: .daily
    )
    habit.activityPeriods = [activity]
    habit.buckets = [first, second]
    context.insert(habit)
    try context.save()
    let before = [BucketSnapshot(first), BucketSnapshot(second)]
    var saveCount = 0

    try expectError(.duplicatePeriodKey("day:2024-01-01")) {
      try BucketReconciler(context: context) {
        saveCount += 1
        try context.save()
      }.reconcile(
        habit: habit,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    #expect(saveCount == 0)
    #expect([BucketSnapshot(first), BucketSnapshot(second)] == before)
    #expect(try buckets(for: habit, in: context).count == 2)
  }

  @Test("invalid persisted state prevents every planned mutation")
  func invalidPersistedStatePreventsEveryPlannedMutation() throws {
    let context = try makeContext()
    let habit = Habit(name: "Read", cadence: .daily, target: 1)
    let activity = HabitActivityPeriod(
      startedAt: try instant("2024-01-01T00:00:00Z")
    )
    let valid = HabitBucket(
      periodKey: "day:2024-01-01",
      startAt: Date(timeIntervalSince1970: 10),
      endAt: Date(timeIntervalSince1970: 20),
      cadence: .daily
    )
    let invalid = HabitBucket(
      periodKey: "day:2024-01-02",
      startAt: Date(timeIntervalSince1970: 30),
      endAt: Date(timeIntervalSince1970: 40),
      cadence: .daily
    )
    invalid.finalizedAt = try instant("2024-01-04T00:00:00Z")
    habit.activityPeriods = [activity]
    habit.buckets = [valid, invalid]
    context.insert(habit)
    try context.save()
    let validBefore = BucketSnapshot(valid)
    let invalidBefore = BucketSnapshot(invalid)

    do {
      try BucketReconciler(context: context).reconcile(
        habit: habit,
        at: instant("2024-01-04T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected partial finality failure")
    } catch let error as BucketEvaluationError {
      #expect(error == .partialFinality)
    }

    #expect(BucketSnapshot(valid) == validBefore)
    #expect(BucketSnapshot(invalid) == invalidBefore)
    #expect(try buckets(for: habit, in: context).count == 2)
  }

  @Test("save failure rolls back creations and existing updates")
  func saveFailureRollsBackCreationsAndExistingUpdates() throws {
    let context = try makeContext()
    let habit = Habit(name: "Read", cadence: .daily, target: 1)
    let activity = HabitActivityPeriod(
      startedAt: try instant("2024-01-01T00:00:00Z")
    )
    let existing = HabitBucket(
      periodKey: "day:2024-01-01",
      startAt: Date(timeIntervalSince1970: 10),
      endAt: Date(timeIntervalSince1970: 20),
      cadence: .daily
    )
    habit.activityPeriods = [activity]
    habit.buckets = [existing]
    context.insert(habit)
    try context.save()
    let before = BucketSnapshot(existing)

    do {
      try BucketReconciler(context: context) {
        throw SaveFailure.expected
      }.reconcile(
        habit: habit,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected save failure")
    } catch let error as SaveFailure {
      #expect(error == .expected)
    }

    let remaining = try buckets(for: habit, in: context)
    #expect(remaining.count == 1)
    #expect(BucketSnapshot(remaining[0]) == before)
    #expect(habit.buckets?.count == 1)
    #expect(!context.hasChanges)
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func insertHabit(
    in context: ModelContext,
    cadence: HabitCadence,
    target: Int,
    unit: String,
    activityStart: String
  ) throws -> Habit {
    let habit = Habit(
      name: "Habit",
      cadence: cadence,
      target: target,
      unit: unit
    )
    habit.activityPeriods = [
      HabitActivityPeriod(startedAt: try instant(activityStart))
    ]
    context.insert(habit)
    try context.save()
    return habit
  }

  private func buckets(for habit: Habit, in context: ModelContext) throws
    -> [HabitBucket]
  {
    let habitID = habit.id
    return try context.fetch(FetchDescriptor<HabitBucket>())
      .filter { $0.habit?.id == habitID }
      .sorted { $0.periodKey < $1.periodKey }
  }

  private func expectError(
    _ expected: BucketReconciliationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected BucketReconciliationError: \(expected)")
    } catch let error as BucketReconciliationError {
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

private struct BucketSnapshot: Equatable {
  let id: UUID
  let periodKey: String
  let startAt: Date
  let endAt: Date
  let cadenceRawValue: String
  let isExempt: Bool
  let finalizedAt: Date?
  let verdictRawValue: String?
  let targetSnapshot: Int?
  let unitSnapshot: String?
  let habitID: UUID?
  let entryIDs: [UUID]

  init(_ bucket: HabitBucket) {
    id = bucket.id
    periodKey = bucket.periodKey
    startAt = bucket.startAt
    endAt = bucket.endAt
    cadenceRawValue = bucket.cadenceRawValue
    isExempt = bucket.isExempt
    finalizedAt = bucket.finalizedAt
    verdictRawValue = bucket.verdictRawValue
    targetSnapshot = bucket.targetSnapshot
    unitSnapshot = bucket.unitSnapshot
    habitID = bucket.habit?.id
    entryIDs = (bucket.entries ?? []).map(\.id).sorted {
      $0.uuidString < $1.uuidString
    }
  }
}
