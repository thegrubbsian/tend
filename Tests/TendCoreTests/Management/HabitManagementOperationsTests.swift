import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Habit management operations")
struct HabitManagementOperationsTests {
  @Test("daily creation normalizes fields and persists a complete current graph")
  func dailyCreationNormalizesAndPersistsCurrentGraph() throws {
    let context = try makeContext()
    let createdAt = try instant("2024-03-10T09:30:00Z")
    let reminder = try #require(ReminderTime(hour: 9, minute: 0))
    let fields = HabitEditableFields(
      name: "  Morning   walk  ",
      target: 8_000,
      unit: "  steps  ",
      pinnedWeekdays: .wednesday,
      reminderTime: reminder
    )

    let habit = try HabitManagementOperations(context: context).create(
      fields: fields,
      cadence: .daily,
      at: createdAt,
      timeZone: timeZone("America/Los_Angeles")
    )

    #expect(habit.name == "Morning   walk")
    #expect(habit.cadenceRawValue == HabitCadence.daily.rawValue)
    #expect(habit.target == 8_000)
    #expect(habit.unit == "steps")
    #expect(habit.pinnedWeekdaysRawValue == PinnedWeekdays.none.rawValue)
    #expect(habit.reminderMinuteOfDay == reminder.rawValue)
    #expect(habit.isActive)
    #expect(habit.createdAt == createdAt)
    #expect(habit.bestStreak == 0)

    let activity = try #require(habit.activityPeriods?.only)
    #expect(activity.startedAt == createdAt)
    #expect(activity.endedAt == nil)
    #expect(activity.habit?.persistentModelID == habit.persistentModelID)

    let bucket = try #require(habit.buckets?.only)
    #expect(bucket.periodKey == "day:2024-03-10")
    #expect(bucket.startAt == (try instant("2024-03-10T08:00:00Z")))
    #expect(bucket.endAt == (try instant("2024-03-11T07:00:00Z")))
    #expect(bucket.cadenceRawValue == HabitCadence.daily.rawValue)
    #expect(!bucket.isExempt)
    #expect(bucket.finalizedAt == nil)
    #expect(bucket.verdictRawValue == nil)
    #expect(bucket.targetSnapshot == nil)
    #expect(bucket.unitSnapshot == nil)
    #expect(bucket.habit?.persistentModelID == habit.persistentModelID)

    #expect(try context.fetch(FetchDescriptor<Habit>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<HabitActivityPeriod>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<HabitBucket>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<LogEntry>()).isEmpty)
    #expect(!context.hasChanges)
  }

  @Test("weekly creation preserves pins and uses Monday boundaries")
  func weeklyCreationPreservesPinsAndUsesMondayBoundaries() throws {
    let context = try makeContext()
    let createdAt = try instant("2024-01-04T18:00:00Z")
    let pinned = try #require(
      PinnedWeekdays(
        rawValue: PinnedWeekdays.monday.rawValue
          | PinnedWeekdays.wednesday.rawValue
      ))
    let reminder = try #require(ReminderTime(hour: 23, minute: 59))

    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(
        name: "Publish",
        target: Int.max,
        unit: "posts",
        pinnedWeekdays: pinned,
        reminderTime: reminder
      ),
      cadence: .weekly,
      at: createdAt,
      timeZone: timeZone("UTC")
    )

    #expect(habit.pinnedWeekdaysRawValue == pinned.rawValue)
    #expect(habit.reminderMinuteOfDay == reminder.rawValue)
    #expect(habit.target == Int.max)
    let bucket = try #require(habit.buckets?.only)
    #expect(bucket.periodKey == "week:2024-01-01")
    #expect(bucket.startAt == (try instant("2024-01-01T00:00:00Z")))
    #expect(bucket.endAt == (try instant("2024-01-08T00:00:00Z")))
    #expect(!context.hasChanges)
  }

  @Test("invalid creation fields are rejected before context mutation")
  func invalidCreationFieldsAreRejectedBeforeMutation() throws {
    let context = try makeContext()
    let operations = HabitManagementOperations(context: context)
    let invalidCases: [(HabitEditableFields, HabitManagementOperationError)] = [
      (
        HabitEditableFields(name: " \n ", target: 1),
        .emptyName
      ),
      (
        HabitEditableFields(name: "Read", target: 0),
        .invalidTarget(0)
      ),
      (
        HabitEditableFields(name: "Read", target: -1),
        .invalidTarget(-1)
      ),
      (
        HabitEditableFields(name: "Read", target: .min),
        .invalidTarget(.min)
      ),
      (
        HabitEditableFields(name: "Read", target: 1, unit: "\t "),
        .emptyUnit
      ),
    ]

    for (fields, expected) in invalidCases {
      try expectManagementError(expected) {
        _ = try operations.create(
          fields: fields,
          cadence: .daily,
          at: instant("2024-01-01T12:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }
      #expect(try context.fetch(FetchDescriptor<Habit>()).isEmpty)
      #expect(try context.fetch(FetchDescriptor<HabitActivityPeriod>()).isEmpty)
      #expect(try context.fetch(FetchDescriptor<HabitBucket>()).isEmpty)
      #expect(!context.hasChanges)
    }
  }

  @Test("creation save failure rolls back the complete inserted graph")
  func creationSaveFailureRollsBackCompleteGraph() throws {
    let context = try makeContext()
    var saveCount = 0
    let operations = HabitManagementOperations(context: context) {
      saveCount += 1
      throw SaveFailure.expected
    }

    do {
      _ = try operations.create(
        fields: HabitEditableFields(name: "Read", target: 1),
        cadence: .daily,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected creation save failure")
    } catch let error as SaveFailure {
      #expect(error == .expected)
    }

    #expect(saveCount == 1)
    #expect(try context.fetch(FetchDescriptor<Habit>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<HabitActivityPeriod>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<HabitBucket>()).isEmpty)
    #expect(!context.hasChanges)
  }

  @Test("active update changes every editable field without changing cadence")
  func activeUpdateChangesEditableFieldsWithoutChangingCadence() throws {
    let context = try makeContext()
    let operations = HabitManagementOperations(context: context)
    let createdAt = try instant("2024-01-01T12:00:00Z")
    let habit = try operations.create(
      fields: HabitEditableFields(
        name: "Read",
        target: 1,
        pinnedWeekdays: .monday
      ),
      cadence: .daily,
      at: createdAt,
      timeZone: timeZone("UTC")
    )
    let reminder = try #require(ReminderTime(hour: 6, minute: 30))

    try operations.update(
      habit,
      fields: HabitEditableFields(
        name: "  Read   books  ",
        target: 25,
        unit: "  pages  ",
        pinnedWeekdays: .friday,
        reminderTime: reminder
      ),
      at: instant("2024-01-01T18:00:00Z"),
      timeZone: timeZone("UTC")
    )

    #expect(habit.name == "Read   books")
    #expect(habit.cadenceRawValue == HabitCadence.daily.rawValue)
    #expect(habit.target == 25)
    #expect(habit.unit == "pages")
    #expect(habit.pinnedWeekdaysRawValue == PinnedWeekdays.none.rawValue)
    #expect(habit.reminderMinuteOfDay == reminder.rawValue)
    #expect(habit.isActive)
    #expect(habit.createdAt == createdAt)
    #expect(habit.activityPeriods?.count == 1)
    #expect(habit.buckets?.count == 1)
    #expect(!context.hasChanges)
  }

  @Test("inactive update preserves cadence pins and the closed activity graph")
  func inactiveUpdatePreservesCadencePinsAndClosedGraph() throws {
    let context = try makeContext()
    let operations = HabitManagementOperations(context: context)
    let habit = try operations.create(
      fields: HabitEditableFields(name: "Publish", target: 1, unit: "post"),
      cadence: .weekly,
      at: instant("2024-01-04T18:00:00Z"),
      timeZone: timeZone("UTC")
    )
    try HabitActivityOperations(context: context).deactivate(
      habit,
      at: instant("2024-01-04T20:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let bucketIdentifiers = try context.fetch(FetchDescriptor<HabitBucket>())
      .map(\.persistentModelID)
    let activityIdentifiers =
      try context.fetch(FetchDescriptor<HabitActivityPeriod>())
      .map(\.persistentModelID)
    let reminder = try #require(ReminderTime(hour: 8, minute: 15))

    try operations.update(
      habit,
      fields: HabitEditableFields(
        name: "Publish weekly",
        target: 2,
        unit: "posts",
        pinnedWeekdays: .tuesday,
        reminderTime: reminder
      ),
      at: instant("2024-02-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )

    #expect(!habit.isActive)
    #expect(habit.cadenceRawValue == HabitCadence.weekly.rawValue)
    #expect(habit.name == "Publish weekly")
    #expect(habit.target == 2)
    #expect(habit.unit == "posts")
    #expect(habit.pinnedWeekdaysRawValue == PinnedWeekdays.tuesday.rawValue)
    #expect(habit.reminderMinuteOfDay == reminder.rawValue)
    #expect(
      try context.fetch(FetchDescriptor<HabitBucket>())
        .map(\.persistentModelID) == bucketIdentifiers
    )
    #expect(
      try context.fetch(FetchDescriptor<HabitActivityPeriod>())
        .map(\.persistentModelID) == activityIdentifiers
    )
    #expect(!context.hasChanges)
  }

  @Test("update save failure restores editable fields after reconciliation")
  func updateSaveFailureRestoresEditableFields() throws {
    let context = try makeContext()
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Read", target: 1),
      cadence: .daily,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    var saveCount = 0
    let operations = HabitManagementOperations(context: context) {
      saveCount += 1
      throw SaveFailure.expected
    }

    do {
      try operations.update(
        habit,
        fields: HabitEditableFields(
          name: "Changed",
          target: 2,
          unit: "pages",
          pinnedWeekdays: .monday,
          reminderTime: try reminderTime(hour: 9, minute: 30)
        ),
        at: instant("2024-01-01T18:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected update save failure")
    } catch let error as SaveFailure {
      #expect(error == .expected)
    }

    #expect(saveCount == 1)
    #expect(habit.name == "Read")
    #expect(habit.cadenceRawValue == HabitCadence.daily.rawValue)
    #expect(habit.target == 1)
    #expect(habit.unit == "times")
    #expect(habit.pinnedWeekdaysRawValue == PinnedWeekdays.none.rawValue)
    #expect(habit.reminderMinuteOfDay == nil)
    #expect(habit.isActive)
    #expect(habit.activityPeriods?.count == 1)
    #expect(habit.buckets?.count == 1)
    #expect(!context.hasChanges)
  }

  @Test("active update finalizes elapsed history before changing requirement")
  func activeUpdateFinalizesElapsedHistoryBeforeRequirementChange() throws {
    let context = try makeContext()
    let operations = HabitManagementOperations(context: context)
    let habit = try operations.create(
      fields: HabitEditableFields(name: "Read", target: 1),
      cadence: .daily,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    _ = try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: instant("2024-01-01T13:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let updateInstant = try instant("2024-01-03T12:00:00Z")

    try operations.update(
      habit,
      fields: HabitEditableFields(
        name: "Read",
        target: 5,
        unit: "pages"
      ),
      at: updateInstant,
      timeZone: timeZone("UTC")
    )

    let buckets = try context.fetch(FetchDescriptor<HabitBucket>())
      .sorted { $0.periodKey < $1.periodKey }
    #expect(
      buckets.map(\.periodKey) == [
        "day:2024-01-01", "day:2024-01-02", "day:2024-01-03",
      ])
    try #require(buckets.count == 3)
    let final = buckets[0]
    let grace = buckets[1]
    let current = buckets[2]
    #expect(final.finalizedAt == (try instant("2024-01-03T00:00:00Z")))
    #expect(final.targetSnapshot == 1)
    #expect(final.unitSnapshot == "times")
    #expect(final.verdictRawValue == BucketVerdict.met.rawValue)

    let evaluator = BucketEvaluator()
    let finalEvaluation = try evaluator.evaluate(
      habit: habit,
      bucket: final,
      at: updateInstant,
      timeZone: timeZone("UTC")
    )
    #expect(finalEvaluation.target == 1)
    #expect(finalEvaluation.unit == "times")
    #expect(finalEvaluation.phase == .final)
    #expect(finalEvaluation.standing == .met)
    let graceEvaluation = try evaluator.evaluate(
      habit: habit,
      bucket: grace,
      at: updateInstant,
      timeZone: timeZone("UTC")
    )
    #expect(graceEvaluation.target == 5)
    #expect(graceEvaluation.unit == "pages")
    #expect(graceEvaluation.phase == .grace)
    let currentEvaluation = try evaluator.evaluate(
      habit: habit,
      bucket: current,
      at: updateInstant,
      timeZone: timeZone("UTC")
    )
    #expect(currentEvaluation.target == 5)
    #expect(currentEvaluation.unit == "pages")
    #expect(currentEvaluation.phase == .open)
    #expect(!context.hasChanges)
  }

  @Test("failed edit retains separately committed reconciliation")
  func failedEditRetainsCommittedReconciliation() throws {
    let context = try makeContext()
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Read", target: 1),
      cadence: .daily,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    var saveCount = 0
    let operations = HabitManagementOperations(context: context) {
      saveCount += 1
      throw SaveFailure.expected
    }

    do {
      try operations.update(
        habit,
        fields: HabitEditableFields(
          name: "Changed",
          target: 5,
          unit: "pages"
        ),
        at: instant("2024-01-03T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected update save failure")
    } catch let error as SaveFailure {
      #expect(error == .expected)
    }

    #expect(saveCount == 1)
    #expect(habit.name == "Read")
    #expect(habit.target == 1)
    #expect(habit.unit == "times")
    let buckets = try context.fetch(FetchDescriptor<HabitBucket>())
      .sorted { $0.periodKey < $1.periodKey }
    #expect(
      buckets.map(\.periodKey) == [
        "day:2024-01-01", "day:2024-01-02", "day:2024-01-03",
      ])
    try #require(buckets.count == 3)
    #expect(buckets[0].targetSnapshot == 1)
    #expect(buckets[0].unitSnapshot == "times")
    #expect(!context.hasChanges)
  }

  @Test("update rejects detached and foreign habits before mutation")
  func updateRejectsDetachedAndForeignHabits() throws {
    let context = try makeContext()
    let operations = HabitManagementOperations(context: context)
    let detached = Habit(name: "Detached", cadence: .daily, target: 1)

    try expectManagementError(.detachedHabit) {
      try operations.update(
        detached,
        fields: HabitEditableFields(name: "Changed", target: 2),
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    #expect(detached.name == "Detached")
    #expect(detached.target == 1)

    let foreignContext = try makeContext()
    let foreignHabit = try HabitManagementOperations(context: foreignContext)
      .create(
        fields: HabitEditableFields(name: "Foreign", target: 1),
        cadence: .daily,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    try expectManagementError(.foreignContext) {
      try operations.update(
        foreignHabit,
        fields: HabitEditableFields(name: "Changed", target: 2),
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    #expect(foreignHabit.name == "Foreign")
    #expect(foreignHabit.target == 1)
    #expect(!context.hasChanges)
    #expect(!foreignContext.hasChanges)
  }

  @Test("delete cascades the complete habit graph and rejects a second delete")
  func deleteCascadesCompleteGraphAndRejectsSecondDelete() throws {
    let context = try makeContext()
    let operations = HabitManagementOperations(context: context)
    let habit = try operations.create(
      fields: HabitEditableFields(name: "Read", target: 1),
      cadence: .daily,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    _ = try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: instant("2024-01-01T13:00:00Z"),
      timeZone: timeZone("UTC")
    )

    try operations.delete(habit)

    #expect(try context.fetch(FetchDescriptor<Habit>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<HabitActivityPeriod>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<HabitBucket>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<LogEntry>()).isEmpty)
    #expect(!context.hasChanges)
    try expectManagementError(.deletedHabit) {
      try operations.delete(habit)
    }
  }

  @Test("delete cascades an inactive habit graph")
  func deleteCascadesInactiveHabitGraph() throws {
    let context = try makeContext()
    let operations = HabitManagementOperations(context: context)
    let utc = try timeZone("UTC")
    let habit = try operations.create(
      fields: HabitEditableFields(name: "Read", target: 1),
      cadence: .daily,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: utc
    )
    _ = try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: instant("2024-01-01T13:00:00Z"),
      timeZone: utc
    )
    try HabitActivityOperations(context: context).deactivate(
      habit,
      at: instant("2024-01-01T14:00:00Z"),
      timeZone: utc
    )
    #expect(!habit.isActive)

    try operations.delete(habit)

    #expect(try context.fetch(FetchDescriptor<Habit>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<HabitActivityPeriod>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<HabitBucket>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<LogEntry>()).isEmpty)
    #expect(!context.hasChanges)
  }

  @Test("delete rejects a habit owned by another context")
  func deleteRejectsForeignHabit() throws {
    let context = try makeContext()
    let foreignContext = try makeContext()
    let foreignHabit = try HabitManagementOperations(context: foreignContext)
      .create(
        fields: HabitEditableFields(name: "Foreign", target: 1),
        cadence: .daily,
        at: instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )

    try expectManagementError(.foreignContext) {
      try HabitManagementOperations(context: context).delete(foreignHabit)
    }

    #expect(try foreignContext.fetch(FetchDescriptor<Habit>()).count == 1)
    #expect(
      try foreignContext.fetch(FetchDescriptor<HabitActivityPeriod>()).count
        == 1
    )
    #expect(try foreignContext.fetch(FetchDescriptor<HabitBucket>()).count == 1)
    #expect(!context.hasChanges)
    #expect(!foreignContext.hasChanges)
  }

  @Test("delete save failure restores the complete habit graph")
  func deleteSaveFailureRestoresCompleteGraph() throws {
    let context = try makeContext()
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Read", target: 1),
      cadence: .daily,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    _ = try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: instant("2024-01-01T13:00:00Z"),
      timeZone: timeZone("UTC")
    )
    var saveCount = 0
    let operations = HabitManagementOperations(context: context) {
      saveCount += 1
      throw SaveFailure.expected
    }

    do {
      try operations.delete(habit)
      Issue.record("Expected delete save failure")
    } catch let error as SaveFailure {
      #expect(error == .expected)
    }

    #expect(saveCount == 1)
    #expect(try context.fetch(FetchDescriptor<Habit>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<HabitActivityPeriod>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<HabitBucket>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 1)
    #expect(!context.hasChanges)
  }

  @Test("extreme valid fields persist and can be edited at activity start")
  func extremeValidFieldsPersistAndEditAtActivityStart() throws {
    let context = try makeContext()
    let operations = HabitManagementOperations(context: context)
    let start = try instant("2024-01-01T12:00:00Z")
    let reminder = try reminderTime(hour: 23, minute: 59)
    let habit = try operations.create(
      fields: HabitEditableFields(
        name: "Count",
        target: .max,
        unit: "items",
        pinnedWeekdays: .none,
        reminderTime: reminder
      ),
      cadence: .weekly,
      at: start,
      timeZone: timeZone("UTC")
    )

    #expect(habit.target == .max)
    #expect(habit.pinnedWeekdaysRawValue == PinnedWeekdays.none.rawValue)
    #expect(habit.reminderMinuteOfDay == reminder.rawValue)
    try operations.update(
      habit,
      fields: HabitEditableFields(
        name: "Count once",
        target: 1,
        unit: "item",
        pinnedWeekdays: .sunday,
        reminderTime: reminder
      ),
      at: start,
      timeZone: timeZone("UTC")
    )

    #expect(habit.name == "Count once")
    #expect(habit.target == 1)
    #expect(habit.pinnedWeekdaysRawValue == PinnedWeekdays.sunday.rawValue)
    #expect(habit.buckets?.count == 1)
    #expect(!context.hasChanges)
  }

  @Test("update at exact grace expiry freezes the old requirement")
  func updateAtExactGraceExpiryFreezesOldRequirement() throws {
    let context = try makeContext()
    let operations = HabitManagementOperations(context: context)
    let habit = try operations.create(
      fields: HabitEditableFields(name: "Read", target: 1),
      cadence: .daily,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    let graceExpiry = try instant("2024-01-03T00:00:00Z")

    try operations.update(
      habit,
      fields: HabitEditableFields(
        name: "Read",
        target: 2,
        unit: "pages"
      ),
      at: graceExpiry,
      timeZone: timeZone("UTC")
    )

    let buckets = try context.fetch(FetchDescriptor<HabitBucket>())
      .sorted { $0.periodKey < $1.periodKey }
    try #require(buckets.count == 3)
    #expect(buckets[0].periodKey == "day:2024-01-01")
    #expect(buckets[0].finalizedAt == graceExpiry)
    #expect(buckets[0].targetSnapshot == 1)
    #expect(buckets[0].unitSnapshot == "times")
    #expect(buckets[0].verdictRawValue == BucketVerdict.missed.rawValue)
    #expect(habit.target == 2)
    #expect(habit.unit == "pages")
    #expect(!context.hasChanges)
  }

  @Test("update rejects an unsupported persisted cadence without mutation")
  func updateRejectsUnsupportedPersistedCadence() throws {
    let context = try makeContext()
    let operations = HabitManagementOperations(context: context)
    let habit = try operations.create(
      fields: HabitEditableFields(name: "Read", target: 1),
      cadence: .daily,
      at: instant("2024-01-01T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    habit.cadenceRawValue = "monthly"
    try context.save()

    do {
      try operations.update(
        habit,
        fields: HabitEditableFields(name: "Changed", target: 2),
        at: instant("2024-01-01T13:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected unsupported cadence error")
    } catch let error as BucketEvaluationError {
      #expect(error == .unsupportedCadence("monthly"))
    }

    #expect(habit.name == "Read")
    #expect(habit.target == 1)
    #expect(habit.cadenceRawValue == "monthly")
    #expect(!context.hasChanges)
  }

  private func expectManagementError(
    _ expected: HabitManagementOperationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected HabitManagementOperationError: \(expected)")
    } catch let error as HabitManagementOperationError {
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

  private func reminderTime(hour: Int, minute: Int) throws -> ReminderTime {
    try #require(ReminderTime(hour: hour, minute: minute))
  }
}

private extension Collection {
  var only: Element? {
    count == 1 ? first : nil
  }
}

private enum SaveFailure: Error, Equatable {
  case expected
}
