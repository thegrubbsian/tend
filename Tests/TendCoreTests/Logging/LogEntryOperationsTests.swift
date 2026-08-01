import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Log entry operations")
struct LogEntryOperationsTests {
  @Test("current append persists one daily entry with exact relationships and timestamp")
  func currentAppendPersistsOneDailyEntry() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 2,
      activityStart: "2024-01-01T08:00:00Z"
    )
    let operationInstant = try instant("2024-01-01T12:30:00Z")
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: context) {
      mutationSaveCount += 1
      try context.save()
    }

    let entry = try operations.append(
      amount: 1,
      to: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    let persistedEntries = try entries(in: context)
    let bucket = try #require(try buckets(for: habit, in: context).first)
    let evaluation = try BucketEvaluator().evaluate(
      habit: habit,
      bucket: bucket,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    #expect(mutationSaveCount == 1)
    #expect(persistedEntries.count == 1)
    #expect(persistedEntries[0].persistentModelID == entry.persistentModelID)
    #expect(entry.amount == 1)
    #expect(entry.timestamp == operationInstant)
    #expect(entry.habit?.persistentModelID == habit.persistentModelID)
    #expect(entry.bucket?.persistentModelID == bucket.persistentModelID)
    #expect(habit.entries?.map(\.persistentModelID) == [entry.persistentModelID])
    #expect(bucket.entries?.map(\.persistentModelID) == [entry.persistentModelID])
    #expect(evaluation.progress == 1)
    #expect(evaluation.standing == .pendingUnmet)
  }

  @Test("explicit daily grace append keeps the later operation timestamp")
  func explicitDailyGraceAppendKeepsOperationTimestamp() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 30,
      unit: "min",
      activityStart: "2024-01-01T08:00:00Z"
    )
    let operationInstant = try instant("2024-01-02T12:00:00Z")
    let entry = try LogEntryOperations(context: context).append(
      amount: 30,
      to: habit,
      destination: .periodKey("day:2024-01-01"),
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    let bucket = try #require(
      try buckets(for: habit, in: context).first {
        $0.periodKey == "day:2024-01-01"
      })
    let evaluation = try BucketEvaluator().evaluate(
      habit: habit,
      bucket: bucket,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    #expect(entry.timestamp == operationInstant)
    #expect(entry.timestamp >= bucket.endAt)
    #expect(entry.bucket?.periodKey == "day:2024-01-01")
    #expect(evaluation.phase == .grace)
    #expect(evaluation.progress == 30)
    #expect(evaluation.standing == .pendingMet)
  }

  @Test("weekly current and Monday grace appends stay in weekly buckets")
  func weeklyAppendsStayInWeeklyBuckets() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .weekly,
      target: 2,
      unit: "times",
      activityStart: "2024-01-01T08:00:00Z"
    )
    let operations = LogEntryOperations(context: context)

    let current = try operations.append(
      amount: 1,
      to: habit,
      at: instant("2024-01-08T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let grace = try operations.append(
      amount: 1,
      to: habit,
      destination: .periodKey("week:2024-01-01"),
      at: instant("2024-01-08T13:00:00Z"),
      timeZone: timeZone("UTC")
    )

    let persistedBuckets = try buckets(for: habit, in: context)
    #expect(persistedBuckets.map(\.periodKey) == ["week:2024-01-01", "week:2024-01-08"])
    #expect(current.bucket?.periodKey == "week:2024-01-08")
    #expect(grace.bucket?.periodKey == "week:2024-01-01")
    #expect(persistedBuckets.allSatisfy { $0.cadenceRawValue == HabitCadence.weekly.rawValue })
  }

  @Test("repeated append creates distinct entries and may exceed the target")
  func repeatedAppendCreatesDistinctEntriesAboveTarget() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 2,
      activityStart: "2024-01-01T08:00:00Z"
    )
    let operations = LogEntryOperations(context: context)
    let operationInstant = try instant("2024-01-01T12:00:00Z")

    let first = try operations.append(
      amount: 2,
      to: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    let second = try operations.append(
      amount: 3,
      to: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    let bucket = try #require(try buckets(for: habit, in: context).first)
    let evaluation = try BucketEvaluator().evaluate(
      habit: habit,
      bucket: bucket,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    #expect(first.persistentModelID != second.persistentModelID)
    #expect(try entries(in: context).count == 2)
    #expect(evaluation.progress == 5)
    #expect(evaluation.standing == .pendingMet)
  }

  @Test("invalid amounts win before habit state and never mutate")
  func invalidAmountsWinBeforeHabitState() throws {
    for amount in [0, -1] {
      let context = try makeContext()
      let habit = Habit(
        name: "Inactive",
        cadence: .daily,
        target: 1,
        isActive: false
      )
      var mutationSaveCount = 0
      let operations = LogEntryOperations(context: context) {
        mutationSaveCount += 1
        try context.save()
      }

      try expectOperationError(.invalidAmount(amount)) {
        try operations.append(
          amount: amount,
          to: habit,
          at: instant("2024-01-01T12:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }

      #expect(mutationSaveCount == 0)
      #expect(try entries(in: context).isEmpty)
      #expect(!context.hasChanges)
    }
  }

  @Test("inactive and detached habits are rejected before reconciliation")
  func inactiveAndDetachedHabitsAreRejectedBeforeReconciliation() throws {
    let inactiveContext = try makeContext()
    let inactive = try insertHabit(
      in: inactiveContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z",
      isActive: false
    )
    var inactiveSaveCount = 0
    let inactiveOperations = LogEntryOperations(context: inactiveContext) {
      inactiveSaveCount += 1
      try inactiveContext.save()
    }

    try expectOperationError(.inactiveHabit) {
      try inactiveOperations.append(
        amount: 1,
        to: inactive,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    #expect(inactiveSaveCount == 0)
    #expect(try buckets(for: inactive, in: inactiveContext).isEmpty)

    let detachedContext = try makeContext()
    let detached = Habit(name: "Detached", cadence: .daily, target: 1)
    detached.activityPeriods = [
      HabitActivityPeriod(startedAt: try instant("2024-01-01T00:00:00Z"))
    ]
    var detachedSaveCount = 0
    let detachedOperations = LogEntryOperations(context: detachedContext) {
      detachedSaveCount += 1
      try detachedContext.save()
    }

    try expectOperationError(.detachedHabit) {
      try detachedOperations.append(
        amount: 1,
        to: detached,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    #expect(detachedSaveCount == 0)
    #expect(try entries(in: detachedContext).isEmpty)
    #expect(!detachedContext.hasChanges)
  }

  @Test("append rejects checked progress overflow without mutation")
  func appendRejectsCheckedProgressOverflow() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operationInstant = try instant("2024-01-01T12:00:00Z")
    try BucketReconciler(context: context).reconcile(
      habit: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    let bucket = try #require(try buckets(for: habit, in: context).first)
    let existing = LogEntry(
      timestamp: operationInstant,
      amount: Int.max,
      habit: habit,
      bucket: bucket
    )
    context.insert(existing)
    try context.save()
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: context) {
      mutationSaveCount += 1
      try context.save()
    }

    try expectOperationError(.progressOverflow) {
      try operations.append(
        amount: 1,
        to: habit,
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }

    #expect(mutationSaveCount == 0)
    #expect(try entries(in: context).map(\.persistentModelID) == [existing.persistentModelID])
    #expect(!context.hasChanges)
  }

  @Test("explicit destinations preserve calendar and cadence errors")
  func explicitDestinationsPreserveCalendarAndCadenceErrors() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operations = LogEntryOperations(context: context)
    let operationInstant = try instant("2024-01-01T12:00:00Z")

    try expectEvaluationError(.calendar(.malformedKey("not-a-key"))) {
      try operations.append(
        amount: 1,
        to: habit,
        destination: .periodKey("not-a-key"),
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }
    try expectEvaluationError(
      .periodCadenceMismatch(key: "week:2024-01-01", cadence: .daily)
    ) {
      try operations.append(
        amount: 1,
        to: habit,
        destination: .periodKey("week:2024-01-01"),
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }
    try expectOperationError(.destinationUnavailable("day:2023-12-31")) {
      try operations.append(
        amount: 1,
        to: habit,
        destination: .periodKey("day:2023-12-31"),
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }
    #expect(try entries(in: context).isEmpty)
    #expect(!context.hasChanges)
  }

  @Test("future open and exempt destinations are not editable")
  func futureOpenAndExemptDestinationsAreNotEditable() throws {
    let futureContext = try makeContext()
    let futureHabit = try insertHabit(
      in: futureContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let utc = try timeZone("UTC")
    let futurePeriod = try CalendarBucketSchedule(timeZone: utc).period(
      forKey: "day:2024-01-02"
    )
    let futureBucket = HabitBucket(
      periodKey: futurePeriod.key,
      startAt: futurePeriod.start,
      endAt: futurePeriod.end,
      cadence: .daily,
      habit: futureHabit
    )
    futureHabit.buckets = [futureBucket]
    futureContext.insert(futureBucket)
    try futureContext.save()

    try expectOperationError(
      .destinationNotEditable(key: futurePeriod.key, phase: .open)
    ) {
      try LogEntryOperations(context: futureContext).append(
        amount: 1,
        to: futureHabit,
        destination: .periodKey(futurePeriod.key),
        at: instant("2024-01-01T12:00:00Z"),
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
    let operationInstant = try instant("2024-01-01T12:00:00Z")
    try BucketReconciler(context: exemptContext).reconcile(
      habit: exemptHabit,
      at: operationInstant,
      timeZone: utc
    )
    let exemptBucket = try #require(
      try buckets(for: exemptHabit, in: exemptContext).first
    )
    exemptBucket.isExempt = true
    try exemptContext.save()

    try expectOperationError(
      .destinationNotEditable(key: exemptBucket.periodKey, phase: .exempt)
    ) {
      try LogEntryOperations(context: exemptContext).append(
        amount: 1,
        to: exemptHabit,
        at: operationInstant,
        timeZone: utc
      )
    }
    #expect(try entries(in: futureContext).isEmpty)
    #expect(try entries(in: exemptContext).isEmpty)
  }

  @Test("exact boundaries select the new current bucket and fossilize expired grace")
  func exactBoundariesSelectCurrentAndFossilizeGrace() throws {
    let currentContext = try makeContext()
    let currentHabit = try insertHabit(
      in: currentContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let boundary = try instant("2024-01-02T00:00:00Z")
    let entry = try LogEntryOperations(context: currentContext).append(
      amount: 1,
      to: currentHabit,
      at: boundary,
      timeZone: timeZone("UTC")
    )
    #expect(entry.bucket?.periodKey == "day:2024-01-02")

    let graceContext = try makeContext()
    let graceHabit = try insertHabit(
      in: graceContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: graceContext) {
      mutationSaveCount += 1
      try graceContext.save()
    }
    let graceBoundary = try instant("2024-01-03T00:00:00Z")

    try expectOperationError(
      .destinationNotEditable(key: "day:2024-01-01", phase: .final)
    ) {
      try operations.append(
        amount: 1,
        to: graceHabit,
        destination: .periodKey("day:2024-01-01"),
        at: graceBoundary,
        timeZone: timeZone("UTC")
      )
    }

    let persistedBuckets = try buckets(for: graceHabit, in: graceContext)
    let final = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-01-01" }
    )
    #expect(mutationSaveCount == 0)
    #expect(final.finalizedAt == graceBoundary)
    #expect(
      persistedBuckets.map(\.periodKey) == [
        "day:2024-01-01", "day:2024-01-02", "day:2024-01-03",
      ])
    #expect(!graceContext.hasChanges)
  }

  @Test("same UUID habits cannot select each other's grace bucket")
  func sameUUIDHabitsCannotSelectForeignGraceBucket() throws {
    let context = try makeContext()
    let sharedID = UUID()
    let first = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-02T00:00:00Z",
      id: sharedID
    )
    let second = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z",
      id: sharedID
    )
    let operationInstant = try instant("2024-01-02T12:00:00Z")
    try BucketReconciler(context: context).reconcile(
      habit: second,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    try expectOperationError(.destinationUnavailable("day:2024-01-01")) {
      try LogEntryOperations(context: context).append(
        amount: 1,
        to: first,
        destination: .periodKey("day:2024-01-01"),
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }
    #expect(try entries(in: context).isEmpty)
  }

  @Test("append save failure rolls back only the entry mutation")
  func appendSaveFailureRollsBackOnlyEntryMutation() throws {
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
      throw SaveFailure.expected
    }

    do {
      try operations.append(
        amount: 1,
        to: habit,
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected save failure")
    } catch let error as SaveFailure {
      #expect(error == .expected)
    }

    let persistedBuckets = try buckets(for: habit, in: context)
    let final = try #require(
      persistedBuckets.first { $0.periodKey == "day:2024-01-01" }
    )
    #expect(mutationSaveCount == 1)
    #expect(persistedBuckets.count == 3)
    #expect(final.finalizedAt == (try instant("2024-01-03T00:00:00Z")))
    #expect(try entries(in: context).isEmpty)
    #expect(habit.entries?.isEmpty == true)
    #expect(persistedBuckets.allSatisfy { $0.entries?.isEmpty == true })
    #expect(!context.hasChanges)
  }

  @Test("delete removes only the selected current entry and updates progress")
  func deleteRemovesOnlySelectedCurrentEntry() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 3,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operationInstant = try instant("2024-01-01T12:00:00Z")
    let setup = LogEntryOperations(context: context)
    let selected = try setup.append(
      amount: 2,
      to: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    let retained = try setup.append(
      amount: 1,
      to: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    let bucket = try #require(selected.bucket)
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: context) {
      mutationSaveCount += 1
      try context.save()
    }

    try operations.delete(
      selected,
      from: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    let persistedEntries = try entries(in: context)
    let evaluation = try BucketEvaluator().evaluate(
      habit: habit,
      bucket: bucket,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    #expect(mutationSaveCount == 1)
    #expect(persistedEntries.map(\.persistentModelID) == [retained.persistentModelID])
    #expect(habit.entries?.map(\.persistentModelID) == [retained.persistentModelID])
    #expect(bucket.entries?.map(\.persistentModelID) == [retained.persistentModelID])
    #expect(evaluation.progress == 1)
    #expect(evaluation.standing == .pendingUnmet)
  }

  @Test("delete may remove the last editable entry")
  func deleteMayRemoveLastEditableEntry() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operationInstant = try instant("2024-01-01T12:00:00Z")
    let operations = LogEntryOperations(context: context)
    let entry = try operations.append(
      amount: 1,
      to: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    let bucket = try #require(entry.bucket)

    try operations.delete(
      entry,
      from: habit,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    let evaluation = try BucketEvaluator().evaluate(
      habit: habit,
      bucket: bucket,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    #expect(try entries(in: context).isEmpty)
    #expect(habit.entries?.isEmpty == true)
    #expect(bucket.entries?.isEmpty == true)
    #expect(evaluation.progress == 0)
    #expect(evaluation.standing == .pendingUnmet)
  }

  @Test("daily and weekly grace entries remain deletable")
  func dailyAndWeeklyGraceEntriesRemainDeletable() throws {
    let dailyContext = try makeContext()
    let dailyHabit = try insertHabit(
      in: dailyContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let dailyOperations = LogEntryOperations(context: dailyContext)
    let dailyEntry = try dailyOperations.append(
      amount: 1,
      to: dailyHabit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    try dailyOperations.delete(
      dailyEntry,
      from: dailyHabit,
      at: instant("2024-01-02T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    #expect(try entries(in: dailyContext).isEmpty)

    let weeklyContext = try makeContext()
    let weeklyHabit = try insertHabit(
      in: weeklyContext,
      cadence: .weekly,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let weeklyOperations = LogEntryOperations(context: weeklyContext)
    let weeklyEntry = try weeklyOperations.append(
      amount: 1,
      to: weeklyHabit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    try weeklyOperations.delete(
      weeklyEntry,
      from: weeklyHabit,
      at: instant("2024-01-08T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    #expect(try entries(in: weeklyContext).isEmpty)
    #expect(
      try buckets(for: weeklyHabit, in: weeklyContext).map(\.periodKey) == [
        "week:2024-01-01", "week:2024-01-08",
      ])
  }

  @Test("delete validates habit and entry persistence before relationships")
  func deleteValidatesPersistenceBeforeRelationships() throws {
    let inactiveContext = try makeContext()
    let inactiveHabit = try insertHabit(
      in: inactiveContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z",
      isActive: false
    )
    var inactiveSaveCount = 0
    let inactiveOperations = LogEntryOperations(context: inactiveContext) {
      inactiveSaveCount += 1
      try inactiveContext.save()
    }
    try expectOperationError(.inactiveHabit) {
      try inactiveOperations.delete(
        LogEntry(timestamp: Date(), amount: 1),
        from: inactiveHabit,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    #expect(inactiveSaveCount == 0)

    let detachedContext = try makeContext()
    let detachedHabit = try insertHabit(
      in: detachedContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    try expectOperationError(.detachedEntry) {
      try LogEntryOperations(context: detachedContext).delete(
        LogEntry(timestamp: Date(), amount: 1),
        from: detachedHabit,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let missingContext = try makeContext()
    let missingHabit = try insertHabit(
      in: missingContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let missingBoth = LogEntry(timestamp: Date(), amount: 1)
    missingContext.insert(missingBoth)
    try missingContext.save()
    try expectOperationError(.missingEntryHabit) {
      try LogEntryOperations(context: missingContext).delete(
        missingBoth,
        from: missingHabit,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let missingBucket = LogEntry(
      timestamp: Date(),
      amount: 1,
      habit: missingHabit
    )
    missingContext.insert(missingBucket)
    try missingContext.save()
    try expectOperationError(.missingEntryBucket) {
      try LogEntryOperations(context: missingContext).delete(
        missingBucket,
        from: missingHabit,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    #expect(!inactiveContext.hasChanges)
    #expect(!detachedContext.hasChanges)
    #expect(!missingContext.hasChanges)
  }

  @Test("delete compares persistent relationships rather than habit UUIDs")
  func deleteComparesPersistentRelationshipsRatherThanHabitUUIDs() throws {
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
    let operationInstant = try instant("2024-01-01T12:00:00Z")
    let foreignEntry = try LogEntryOperations(context: context).append(
      amount: 1,
      to: second,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )

    try expectOperationError(.foreignEntryHabit) {
      try LogEntryOperations(context: context).delete(
        foreignEntry,
        from: first,
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }
    #expect(
      try entries(in: context).map(\.persistentModelID) == [
        foreignEntry.persistentModelID
      ])
  }

  @Test("delete rejects a bucket from another aggregate")
  func deleteRejectsBucketFromAnotherAggregate() throws {
    let context = try makeContext()
    let first = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let second = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operationInstant = try instant("2024-01-01T12:00:00Z")
    try BucketReconciler(context: context).reconcile(
      habit: second,
      at: operationInstant,
      timeZone: timeZone("UTC")
    )
    let foreignBucket = try #require(try buckets(for: second, in: context).first)
    let entry = LogEntry(
      timestamp: operationInstant,
      amount: 1,
      habit: first,
      bucket: foreignBucket
    )
    context.insert(entry)
    try context.save()

    try expectOperationError(.foreignEntryBucket) {
      try LogEntryOperations(context: context).delete(
        entry,
        from: first,
        at: operationInstant,
        timeZone: timeZone("UTC")
      )
    }
    #expect(
      try entries(in: context).map(\.persistentModelID) == [
        entry.persistentModelID
      ])
    #expect(!context.hasChanges)
  }

  @Test("final exempt and future entries are not deletable")
  func finalExemptAndFutureEntriesAreNotDeletable() throws {
    let utc = try timeZone("UTC")

    let finalContext = try makeContext()
    let finalHabit = try insertHabit(
      in: finalContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let finalOperations = LogEntryOperations(context: finalContext)
    let finalEntry = try finalOperations.append(
      amount: 1,
      to: finalHabit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: utc
    )
    try expectOperationError(
      .destinationNotEditable(key: "day:2024-01-01", phase: .final)
    ) {
      try finalOperations.delete(
        finalEntry,
        from: finalHabit,
        at: instant("2024-01-03T00:00:00Z"),
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
    let exemptOperations = LogEntryOperations(context: exemptContext)
    let exemptEntry = try exemptOperations.append(
      amount: 1,
      to: exemptHabit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: utc
    )
    let exemptBucket = try #require(exemptEntry.bucket)
    exemptBucket.isExempt = true
    try exemptContext.save()
    try expectOperationError(
      .destinationNotEditable(key: "day:2024-01-01", phase: .exempt)
    ) {
      try exemptOperations.delete(
        exemptEntry,
        from: exemptHabit,
        at: instant("2024-01-01T13:00:00Z"),
        timeZone: utc
      )
    }

    let futureContext = try makeContext()
    let futureHabit = try insertHabit(
      in: futureContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let futurePeriod = try CalendarBucketSchedule(timeZone: utc).period(
      forKey: "day:2024-01-02"
    )
    let futureBucket = HabitBucket(
      periodKey: futurePeriod.key,
      startAt: futurePeriod.start,
      endAt: futurePeriod.end,
      cadence: .daily,
      habit: futureHabit
    )
    let futureEntry = LogEntry(
      timestamp: try instant("2024-01-01T12:00:00Z"),
      amount: 1,
      habit: futureHabit,
      bucket: futureBucket
    )
    futureHabit.buckets = [futureBucket]
    futureHabit.entries = [futureEntry]
    futureContext.insert(futureBucket)
    futureContext.insert(futureEntry)
    try futureContext.save()
    try expectOperationError(
      .destinationNotEditable(key: futurePeriod.key, phase: .open)
    ) {
      try LogEntryOperations(context: futureContext).delete(
        futureEntry,
        from: futureHabit,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: utc
      )
    }

    #expect(try entries(in: finalContext).count == 1)
    #expect(try entries(in: exemptContext).count == 1)
    #expect(try entries(in: futureContext).count == 1)
  }

  @Test("delete save failure restores the entry after committed reconciliation")
  func deleteSaveFailureRestoresEntryAfterReconciliation() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let utc = try timeZone("UTC")
    let currentPeriod = try CalendarBucketSchedule(timeZone: utc).period(
      forKey: "day:2024-01-03"
    )
    let bucket = HabitBucket(
      periodKey: currentPeriod.key,
      startAt: currentPeriod.start,
      endAt: currentPeriod.end,
      cadence: .daily,
      habit: habit
    )
    let entry = LogEntry(
      timestamp: try instant("2024-01-03T12:00:00Z"),
      amount: 1,
      habit: habit,
      bucket: bucket
    )
    habit.buckets = [bucket]
    habit.entries = [entry]
    context.insert(bucket)
    context.insert(entry)
    try context.save()
    var mutationSaveCount = 0
    let operations = LogEntryOperations(context: context) {
      mutationSaveCount += 1
      throw SaveFailure.expected
    }

    do {
      try operations.delete(
        entry,
        from: habit,
        at: instant("2024-01-03T12:00:00Z"),
        timeZone: utc
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
    #expect(
      try entries(in: context).map(\.persistentModelID) == [
        entry.persistentModelID
      ])
    #expect(habit.entries?.map(\.persistentModelID) == [entry.persistentModelID])
    #expect(bucket.entries?.map(\.persistentModelID) == [entry.persistentModelID])
    #expect(!context.hasChanges)
  }

  @Test("delete distinguishes detached buckets from missing bucket ownership")
  func deleteDistinguishesDetachedBucketsFromMissingOwnership() throws {
    let utc = try timeZone("UTC")
    let operationInstant = try instant("2024-01-01T12:00:00Z")

    let missingContext = try makeContext()
    let missingHabit = try insertHabit(
      in: missingContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let period = try CalendarBucketSchedule(timeZone: utc).period(
      forKey: "day:2024-01-01"
    )
    let ownerlessBucket = HabitBucket(
      periodKey: period.key,
      startAt: period.start,
      endAt: period.end,
      cadence: .daily
    )
    let ownerlessEntry = LogEntry(
      timestamp: operationInstant,
      amount: 1,
      habit: missingHabit,
      bucket: ownerlessBucket
    )
    missingContext.insert(ownerlessBucket)
    missingContext.insert(ownerlessEntry)
    try missingContext.save()

    try expectOperationError(.missingBucketHabit) {
      try LogEntryOperations(context: missingContext).delete(
        ownerlessEntry,
        from: missingHabit,
        at: operationInstant,
        timeZone: utc
      )
    }

    let detachedContext = try makeContext()
    let detachedHabit = try insertHabit(
      in: detachedContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let detachedEntry = LogEntry(
      timestamp: operationInstant,
      amount: 1,
      habit: detachedHabit
    )
    detachedContext.insert(detachedEntry)
    try detachedContext.save()
    let detachedBucket = HabitBucket(
      periodKey: period.key,
      startAt: period.start,
      endAt: period.end,
      cadence: .daily,
      habit: detachedHabit
    )
    detachedEntry.bucket = detachedBucket

    try expectOperationError(.detachedEntryBucket) {
      try LogEntryOperations(context: detachedContext).delete(
        detachedEntry,
        from: detachedHabit,
        at: operationInstant,
        timeZone: utc
      )
    }
    #expect(try entries(in: missingContext).count == 1)
    #expect(try entries(in: detachedContext).count == 1)
  }

  @Test("logging preserves reconciliation and evaluation dependency errors")
  func loggingPreservesDependencyErrors() throws {
    let utc = try timeZone("UTC")
    let operationInstant = try instant("2024-01-01T12:00:00Z")

    let activityContext = try makeContext()
    let missingActivity = Habit(name: "Missing", cadence: .daily, target: 1)
    activityContext.insert(missingActivity)
    try activityContext.save()
    try expectReconciliationError(.missingOpenActivityPeriod) {
      try LogEntryOperations(context: activityContext).append(
        amount: 1,
        to: missingActivity,
        at: operationInstant,
        timeZone: utc
      )
    }

    let duplicateContext = try makeContext()
    let duplicateHabit = try insertHabit(
      in: duplicateContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let period = try CalendarBucketSchedule(timeZone: utc).period(
      forKey: "day:2024-01-01"
    )
    let first = HabitBucket(
      periodKey: period.key,
      startAt: period.start,
      endAt: period.end,
      cadence: .daily,
      habit: duplicateHabit
    )
    let second = HabitBucket(
      periodKey: period.key,
      startAt: period.start,
      endAt: period.end,
      cadence: .daily,
      habit: duplicateHabit
    )
    duplicateHabit.buckets = [first, second]
    duplicateContext.insert(first)
    duplicateContext.insert(second)
    try duplicateContext.save()
    try expectReconciliationError(.duplicatePeriodKey(period.key)) {
      try LogEntryOperations(context: duplicateContext).append(
        amount: 1,
        to: duplicateHabit,
        at: operationInstant,
        timeZone: utc
      )
    }

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
    try expectEvaluationError(.invalidEntryAmount(-2)) {
      try LogEntryOperations(context: invalidContext).append(
        amount: 1,
        to: invalidHabit,
        at: operationInstant,
        timeZone: utc
      )
    }

    let finalityContext = try makeContext()
    let finalityHabit = try insertHabit(
      in: finalityContext,
      cadence: .daily,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let partial = HabitBucket(
      periodKey: period.key,
      startAt: period.start,
      endAt: period.end,
      cadence: .daily,
      finalizedAt: operationInstant,
      habit: finalityHabit
    )
    finalityHabit.buckets = [partial]
    finalityContext.insert(partial)
    try finalityContext.save()
    try expectEvaluationError(.partialFinality) {
      try LogEntryOperations(context: finalityContext).append(
        amount: 1,
        to: finalityHabit,
        at: operationInstant,
        timeZone: utc
      )
    }

    #expect(try entries(in: activityContext).isEmpty)
    #expect(try entries(in: duplicateContext).isEmpty)
    #expect(
      try entries(in: invalidContext).map(\.persistentModelID) == [
        invalidEntry.persistentModelID
      ])
    #expect(try entries(in: finalityContext).isEmpty)
  }

  @Test("weekly grace ends exactly at Tuesday midnight")
  func weeklyGraceEndsAtTuesdayMidnight() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      cadence: .weekly,
      target: 1,
      activityStart: "2024-01-01T00:00:00Z"
    )
    let operations = LogEntryOperations(context: context)
    let entry = try operations.append(
      amount: 1,
      to: habit,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )

    try expectOperationError(
      .destinationNotEditable(key: "week:2024-01-01", phase: .final)
    ) {
      try operations.delete(
        entry,
        from: habit,
        at: instant("2024-01-09T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    #expect(
      try entries(in: context).map(\.persistentModelID) == [
        entry.persistentModelID
      ])
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func insertHabit(
    in context: ModelContext,
    cadence: HabitCadence,
    target: Int,
    unit: String = "times",
    activityStart: String,
    isActive: Bool = true,
    id: UUID = UUID()
  ) throws -> Habit {
    let habit = Habit(
      id: id,
      name: "Habit",
      cadence: cadence,
      target: target,
      unit: unit,
      isActive: isActive
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
    try context.fetch(FetchDescriptor<LogEntry>()).sorted {
      $0.persistentModelID < $1.persistentModelID
    }
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
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
  private func expectReconciliationError(
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

  private func timeZone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }
}

private enum SaveFailure: Error, Equatable {
  case expected
}
