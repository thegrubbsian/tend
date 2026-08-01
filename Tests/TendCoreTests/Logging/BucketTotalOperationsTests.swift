import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Bucket total operations")
struct BucketTotalOperationsTests {
  @Test("greater daily total appends one delta with operation facts")
  func greaterDailyTotalAppendsOneDelta() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 5,
      unit: "steps",
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operationInstant = try instant("2024-01-01T12:30:00Z")
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: context) {
      mutationSaveCount += 1
      try context.save()
    }

    let entry = try #require(
      try operations.setTotal(
        7,
        for: habit,
        at: operationInstant,
        timeZone: timeZone("UTC")
      ))

    let bucket = try #require(try buckets(for: habit, in: context).first)
    let evaluation = try BucketEvaluator().evaluate(
      habit: habit,
      bucket: bucket,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    #expect(mutationSaveCount == 1)
    #expect(try entries(in: context).map(\.persistentModelID) == [entry.persistentModelID])
    #expect(entry.amount == 7)
    #expect(entry.timestamp == operationInstant)
    #expect(entry.habit?.persistentModelID == habit.persistentModelID)
    #expect(entry.bucket?.persistentModelID == bucket.persistentModelID)
    #expect(habit.entries?.map(\.persistentModelID) == [entry.persistentModelID])
    #expect(bucket.entries?.map(\.persistentModelID) == [entry.persistentModelID])
    #expect(evaluation.progress == 7)
    #expect(evaluation.standing == .pendingMet)
  }

  @Test("set total uses the checked sum of multiple existing entries")
  func setTotalUsesCheckedSumOfMultipleEntries() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 4,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operationInstant = try instant("2024-01-01T12:00:00Z")
    let setup = LogEntryOperations(context: context)
    let first = try setup.append(
      amount: 1,
      to: habit,
      at: instant("2024-01-01T09:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let second = try setup.append(
      amount: 2,
      to: habit,
      at: instant("2024-01-01T10:00:00Z"),
      timeZone: timeZone("UTC")
    )
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: context) {
      mutationSaveCount += 1
      try context.save()
    }

    let delta = try #require(
      try operations.setTotal(
        6,
        for: habit,
        at: operationInstant,
        timeZone: timeZone("UTC")
      ))

    let bucket = try #require(delta.bucket)
    let evaluation = try BucketEvaluator().evaluate(
      habit: habit,
      bucket: bucket,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    #expect(mutationSaveCount == 1)
    #expect(delta.amount == 3)
    #expect(delta.timestamp == operationInstant)
    #expect(
      try entries(in: context).map(\.persistentModelID).sorted()
        == [
          first.persistentModelID, second.persistentModelID, delta.persistentModelID,
        ].sorted())
    #expect(evaluation.progress == 6)
    #expect(evaluation.standing == .pendingMet)
  }

  @Test("equal totals preserve entries and skip the mutation save")
  func equalTotalsPreserveEntriesAndSkipMutationSave() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 5,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operationInstant = try instant("2024-01-01T12:00:00Z")
    let existing = try LogEntryOperations(context: context).append(
      amount: 3,
      to: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: context) {
      mutationSaveCount += 1
      try context.save()
    }

    let result = try operations.setTotal(
      3,
      for: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    #expect(result == nil)
    #expect(mutationSaveCount == 0)
    #expect(
      try entries(in: context).map(\.persistentModelID) == [
        existing.persistentModelID
      ])
    #expect(!context.hasChanges)
  }

  @Test("zero total on an empty bucket is a no-op after reconciliation")
  func zeroTotalOnEmptyBucketIsNoOpAfterReconciliation() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operationInstant = try instant("2024-01-03T12:00:00Z")
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: context) {
      mutationSaveCount += 1
      try context.save()
    }

    let result = try operations.setTotal(
      0,
      for: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    let persistedBuckets = try buckets(for: habit, in: context)
    #expect(result == nil)
    #expect(mutationSaveCount == 0)
    #expect(
      persistedBuckets.map(\.periodKey) == [
        "day:2024-01-01", "day:2024-01-02", "day:2024-01-03",
      ])
    #expect(persistedBuckets[0].finalizedAt == (try instant("2024-01-03T00:00:00Z")))
    #expect(try entries(in: context).isEmpty)
    #expect(!context.hasChanges)
  }

  @Test("lower and negative totals are distinct typed failures")
  func lowerAndNegativeTotalsAreDistinctTypedFailures() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 5,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operationInstant = try instant("2024-01-01T12:00:00Z")
    let existing = try LogEntryOperations(context: context).append(
      amount: 4,
      to: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: context) {
      mutationSaveCount += 1
      try context.save()
    }

    for requested in [2, 0] {
      try expectOperationError(
        .totalBelowProgress(current: 4, requested: requested)
      ) {
        try operations.setTotal(
          requested,
          for: habit,
          at: operationInstant,
          timeZone: timeZone("UTC")
        )
      }
    }

    let detachedInactive = Habit(
      name: "Inactive",
      cadence: .daily,
      target: 1,
      isActive: false
    )
    try expectOperationError(.invalidTotal(-1)) {
      try operations.setTotal(
        -1,
        for: detachedInactive,
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }
    #expect(mutationSaveCount == 0)
    #expect(
      try entries(in: context).map(\.persistentModelID) == [
        existing.persistentModelID
      ])
    #expect(!context.hasChanges)
  }

  @Test("daily grace set total appends one above-target difference")
  func dailyGraceSetTotalAppendsAboveTargetDifference() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 30,
      unit: "min",
      activityStart: "2024-01-01T00:00:00Z"
    )
    let setup = LogEntryOperations(context: context)
    let existing = try setup.append(
      amount: 10,
      to: habit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let operationInstant = try instant("2024-01-02T12:00:00Z")
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: context) {
      mutationSaveCount += 1
      try context.save()
    }

    let delta = try #require(
      try operations.setTotal(
        35,
        for: habit,
        destination: .periodKey("day:2024-01-01"),
        at: operationInstant,
        timeZone: timeZone("UTC")
      ))

    let bucket = try #require(delta.bucket)
    let evaluation = try BucketEvaluator().evaluate(
      habit: habit,
      bucket: bucket,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    #expect(mutationSaveCount == 1)
    #expect(delta.amount == 25)
    #expect(delta.timestamp == operationInstant)
    #expect(delta.timestamp >= bucket.endAt)
    #expect(
      bucket.entries?.map(\.persistentModelID).sorted()
        == [
          existing.persistentModelID, delta.persistentModelID,
        ].sorted())
    #expect(evaluation.phase == .grace)
    #expect(evaluation.progress == 35)
    #expect(evaluation.standing == .pendingMet)
  }

  @Test("weekly totals use whole current and Monday grace buckets")
  func weeklyTotalsUseWholeSelectedBuckets() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .weekly,
      target: 5,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let setup = LogEntryOperations(context: context)
    try setup.append(
      amount: 1,
      to: habit,
      at: instant("2024-01-04T18:00:00Z"),
      timeZone: timeZone("UTC")
    )
    try setup.append(
      amount: 2,
      to: habit,
      at: instant("2024-01-07T18:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let monday = try instant("2024-01-08T12:00:00Z")
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: context) {
      mutationSaveCount += 1
      try context.save()
    }

    let graceDelta = try #require(
      try operations.setTotal(
        5,
        for: habit,
        destination: .periodKey("week:2024-01-01"),
        at: monday,
        timeZone: timeZone("UTC")
      ))
    let currentDelta = try #require(
      try operations.setTotal(
        3,
        for: habit,
        at: monday,
        timeZone: timeZone("UTC")
      ))

    let persistedBuckets = try buckets(for: habit, in: context)
    let graceBucket = try #require(
      persistedBuckets.first { $0.periodKey == "week:2024-01-01" }
    )
    let currentBucket = try #require(
      persistedBuckets.first { $0.periodKey == "week:2024-01-08" }
    )
    #expect(mutationSaveCount == 2)
    #expect(
      persistedBuckets.map(\.periodKey) == [
        "week:2024-01-01", "week:2024-01-08",
      ])
    #expect(
      persistedBuckets.allSatisfy {
        $0.cadenceRawValue == HabitCadence.weekly.rawValue
      })
    #expect(graceBucket.entries?.map(\.amount).sorted() == [1, 2, 2])
    #expect(currentBucket.entries?.map(\.amount) == [3])
    #expect(graceDelta.amount == 2)
    #expect(graceDelta.timestamp == monday)
    #expect(currentDelta.amount == 3)
  }

  @Test("Int max total appends a representable checked difference")
  func intMaxTotalAppendsRepresentableDifference() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operationInstant = try instant("2024-01-01T12:00:00Z")
    try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    let delta = try #require(
      try LogEntryOperations(context: context).setTotal(
        Int.max,
        for: habit,
        at: operationInstant,
        timeZone: timeZone("UTC")
      ))

    let bucket = try #require(delta.bucket)
    let evaluation = try BucketEvaluator().evaluate(
      habit: habit,
      bucket: bucket,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    #expect(delta.amount == Int.max - 1)
    #expect(evaluation.progress == Int.max)
  }

  @Test("invalid and overflowing persisted progress propagate without mutation")
  func invalidAndOverflowingProgressPropagateWithoutMutation() throws {
    let utc = try timeZone("UTC")
    let operationInstant = try instant("2024-01-01T12:00:00Z")

    let invalidContext = try makeContext()
    let invalidHabit = try insertHabit(
      in: invalidContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    try BucketReconciler(context: invalidContext).reconcile(
      habit: invalidHabit,
      at: operationInstant,
      timeZone: utc
    )
    let invalidBucket = try #require(
      try buckets(for: invalidHabit, in: invalidContext).first
    )
    let invalidEntry = LogEntry(
      timestamp: operationInstant,
      amount: -2,
      habit: invalidHabit,
      bucket: invalidBucket
    )
    invalidContext.insert(invalidEntry)
    try invalidContext.save()
    var invalidSaveCount = 0
    let invalidOperations = LogEntryOperations(context: invalidContext) {
      invalidSaveCount += 1
      try invalidContext.save()
    }
    try expectEvaluationError(.invalidEntryAmount(-2)) {
      try invalidOperations.setTotal(
        3,
        for: invalidHabit,
        at: operationInstant,
        timeZone: utc
      )
    }

    let overflowContext = try makeContext()
    let overflowHabit = try insertHabit(
      in: overflowContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    try BucketReconciler(context: overflowContext).reconcile(
      habit: overflowHabit,
      at: operationInstant,
      timeZone: utc
    )
    let overflowBucket = try #require(
      try buckets(for: overflowHabit, in: overflowContext).first
    )
    for amount in [Int.max, 1] {
      overflowContext.insert(
        LogEntry(
          timestamp: operationInstant,
          amount: amount,
          habit: overflowHabit,
          bucket: overflowBucket
        ))
    }
    try overflowContext.save()
    var overflowSaveCount = 0
    let overflowOperations = LogEntryOperations(context: overflowContext) {
      overflowSaveCount += 1
      try overflowContext.save()
    }
    try expectEvaluationError(.progressOverflow) {
      try overflowOperations.setTotal(
        Int.max,
        for: overflowHabit,
        at: operationInstant,
        timeZone: utc
      )
    }

    #expect(invalidSaveCount == 0)
    #expect(overflowSaveCount == 0)
    #expect(try entries(in: invalidContext).count == 1)
    #expect(try entries(in: overflowContext).count == 2)
    #expect(!invalidContext.hasChanges)
    #expect(!overflowContext.hasChanges)
  }

  @Test("set total rejects fossilized grace after reconciliation")
  func setTotalRejectsFossilizedGraceAfterReconciliation() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let existing = try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: context) {
      mutationSaveCount += 1
      try context.save()
    }
    let graceBoundary = try instant("2024-01-03T00:00:00Z")

    try expectOperationError(
      .destinationNotEditable(key: "day:2024-01-01", phase: .final)
    ) {
      try operations.setTotal(
        2,
        for: habit,
        destination: .periodKey("day:2024-01-01"),
        at: graceBoundary,
        timeZone: timeZone("UTC")
      )
    }

    let final = try #require(
      try buckets(for: habit, in: context).first {
        $0.periodKey == "day:2024-01-01"
      })
    #expect(mutationSaveCount == 0)
    #expect(final.finalizedAt == graceBoundary)
    #expect(
      try entries(in: context).map(\.persistentModelID) == [
        existing.persistentModelID
      ])
    #expect(!context.hasChanges)
  }

  @Test("positive delta save failure rolls back only the entry")
  func positiveDeltaSaveFailureRollsBackOnlyEntry() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 5,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operationInstant = try instant("2024-01-03T12:00:00Z")
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: context) {
      mutationSaveCount += 1
      throw SaveFailure.expected
    }

    do {
      try operations.setTotal(
        5,
        for: habit,
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected save failure")
    } catch let error as SaveFailure {
      #expect(error == .expected)
    }

    let persistedBuckets = try buckets(for: habit, in: context)
    #expect(mutationSaveCount == 1)
    #expect(
      persistedBuckets.map(\.periodKey) == [
        "day:2024-01-01", "day:2024-01-02", "day:2024-01-03",
      ])
    #expect(persistedBuckets[0].finalizedAt == (try instant("2024-01-03T00:00:00Z")))
    #expect(try entries(in: context).isEmpty)
    #expect(habit.entries?.isEmpty == true)
    #expect(persistedBuckets.allSatisfy { $0.entries?.isEmpty == true })
    #expect(!context.hasChanges)
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func insertHabit(
    in context: ModelContext,
    cadence: HabitCadence,
    target: Int,
    unit: String = "times",
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
    let habitIdentifier = habit.persistentModelID
    return try context.fetch(FetchDescriptor<HabitBucket>())
      .filter { $0.habit?.persistentModelID == habitIdentifier }
      .sorted { $0.periodKey < $1.periodKey }
  }

  private func entries(in context: ModelContext) throws -> [LogEntry] {
    try context.fetch(FetchDescriptor<LogEntry>())
  }
  private func expectOperationError(
    _ expected: LogEntryOperationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected LogEntryOperationError: \(expected)")
    } catch let error as LogEntryOperationError {
      #expect(error == expected)
    }
  }
  private func expectEvaluationError(
    _ expected: BucketEvaluationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected BucketEvaluationError: \(expected)")
    } catch let error as BucketEvaluationError {
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
