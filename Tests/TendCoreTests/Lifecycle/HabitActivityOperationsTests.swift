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
