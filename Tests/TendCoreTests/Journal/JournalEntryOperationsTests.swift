import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Journal entry operations")
struct JournalEntryOperationsTests {
  @Test("create persists Today and Yesterday verbatim with exact timestamps")
  func createPersistsEligibleDaysVerbatim() throws {
    let context = try makeContext()
    var saveCount = 0
    let operations = JournalEntryOperations(context: context) {
      saveCount += 1
      try context.save()
    }
    let operationInstant = try instant("2026-03-08T18:45:12Z")
    let zone = try timeZone("America/Los_Angeles")
    let today = try localDate("2026-03-08")
    let yesterday = try localDate("2026-03-07")

    let first = try operations.create(
      day: today,
      body: "  First line\nSecond line 🌱  ",
      at: operationInstant,
      timeZone: zone
    )
    let second = try operations.create(
      day: yesterday,
      body: "",
      at: operationInstant.addingTimeInterval(1),
      timeZone: zone
    )

    #expect(first.dayKey == "2026-03-08")
    #expect(first.body == "  First line\nSecond line 🌱  ")
    #expect(first.createdAt == operationInstant)
    #expect(first.editedAt == operationInstant)
    #expect(second.dayKey == "2026-03-07")
    #expect(second.body == "")
    #expect(second.createdAt == operationInstant.addingTimeInterval(1))
    #expect(second.editedAt == operationInstant.addingTimeInterval(1))
    #expect(Set([first.id, second.id]).count == 2)
    #expect(try context.fetch(FetchDescriptor<JournalEntry>()).count == 2)
    #expect(saveCount == 2)
    #expect(!context.hasChanges)
  }

  @Test("create rejects old future duplicate and pending duplicate days before save")
  func createRejectsIneligibleAndDuplicateDays() throws {
    let context = try makeContext()
    let operationInstant = try instant("2026-03-08T12:00:00Z")
    let zone = try timeZone("UTC")
    let today = try localDate("2026-03-08")
    let existing = try persistedEntry(day: today, in: context)
    var saveCount = 0
    let operations = JournalEntryOperations(context: context) { saveCount += 1 }

    try expectError(.ineligibleDay(try localDate("2026-03-06"))) {
      _ = try operations.create(
        day: localDate("2026-03-06"), body: "Old", at: operationInstant, timeZone: zone)
    }
    try expectError(.ineligibleDay(try localDate("2026-03-09"))) {
      _ = try operations.create(
        day: localDate("2026-03-09"), body: "Future", at: operationInstant, timeZone: zone)
    }
    try expectError(.duplicateDay(today)) {
      _ = try operations.create(day: today, body: "Duplicate", at: operationInstant, timeZone: zone)
    }

    let pendingDay = try localDate("2026-03-07")
    let pending = JournalEntry(
      day: pendingDay,
      body: "Pending",
      createdAt: operationInstant,
      editedAt: operationInstant
    )
    context.insert(pending)
    context.processPendingChanges()
    try expectError(.duplicateDay(pendingDay)) {
      _ = try operations.create(
        day: pendingDay, body: "Competing", at: operationInstant, timeZone: zone)
    }

    #expect(saveCount == 0)
    #expect(existing.body == "Body")
    #expect(try context.fetch(FetchDescriptor<JournalEntry>()).count == 2)
  }

  @Test("edit replaces old prose forever and a no-op is inert")
  func editReplacesOldProseAndNoOpIsInert() throws {
    let context = try makeContext()
    let createdAt = try instant("2024-01-01T12:00:00Z")
    let entry = try persistedEntry(
      day: localDate("2024-01-01"),
      body: "Original",
      createdAt: createdAt,
      editedAt: createdAt,
      in: context
    )
    var saveCount = 0
    let operations = JournalEntryOperations(context: context) {
      saveCount += 1
      try context.save()
    }
    let editInstant = try instant("2026-03-08T12:00:00Z")

    try operations.edit(entry, body: "", at: editInstant)
    #expect(entry.dayKey == "2024-01-01")
    #expect(entry.body == "")
    #expect(entry.createdAt == createdAt)
    #expect(entry.editedAt == editInstant)
    #expect(saveCount == 1)

    try operations.edit(entry, body: "", at: editInstant.addingTimeInterval(100))
    #expect(entry.createdAt == createdAt)
    #expect(entry.editedAt == editInstant)
    #expect(saveCount == 1)
    #expect(!context.hasChanges)
  }

  @Test("delete authorizes only Today and Yesterday without rewriting the stored day")
  func deleteAuthorizesOnlyEligibleDays() throws {
    let operationInstant = try instant("2026-03-08T12:00:00Z")
    let zone = try timeZone("UTC")

    for key in ["2026-03-08", "2026-03-07"] {
      let context = try makeContext()
      let entry = try persistedEntry(day: localDate(key), in: context)
      let operations = JournalEntryOperations(context: context)

      try operations.delete(entry, at: operationInstant, timeZone: zone)

      #expect(entry.dayKey == key)
      #expect(try context.fetch(FetchDescriptor<JournalEntry>()).isEmpty)
      #expect(!context.hasChanges)
    }

    for key in ["2026-03-06", "2026-03-09"] {
      let context = try makeContext()
      let day = try localDate(key)
      let entry = try persistedEntry(day: day, in: context)
      var saveCount = 0
      let operations = JournalEntryOperations(context: context) { saveCount += 1 }

      try expectError(.ineligibleDay(day)) {
        try operations.delete(entry, at: operationInstant, timeZone: zone)
      }

      #expect(entry.dayKey == key)
      #expect(try context.fetch(FetchDescriptor<JournalEntry>()).count == 1)
      #expect(saveCount == 0)
    }
  }

  @Test("malformed stored days fail edit and delete before mutation")
  func malformedDaysFailBeforeMutation() throws {
    let context = try makeContext()
    let entry = try persistedEntry(day: localDate("2026-03-08"), in: context)
    entry.dayKey = "today"
    try context.save()
    let original = facts(entry)
    var saveCount = 0
    let operations = JournalEntryOperations(context: context) { saveCount += 1 }

    try expectError(.malformedDay("today")) {
      try operations.edit(entry, body: "Changed", at: instant("2026-03-08T12:00:00Z"))
    }
    try expectError(.malformedDay("today")) {
      try operations.delete(
        entry,
        at: instant("2026-03-08T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    #expect(facts(entry) == original)
    #expect(saveCount == 0)
    #expect(!context.hasChanges)
  }

  @Test("detached deleted and foreign entries are rejected distinctly")
  func ownershipFailuresAreDistinct() throws {
    let context = try makeContext()
    let operations = JournalEntryOperations(context: context)
    let day = try localDate("2026-03-08")
    let detached = JournalEntry(
      day: day,
      body: "Detached",
      createdAt: Date(timeIntervalSince1970: 1),
      editedAt: Date(timeIntervalSince1970: 1)
    )

    try expectError(.detachedEntry) {
      try operations.edit(detached, body: "Changed", at: Date(timeIntervalSince1970: 2))
    }
    try expectError(.detachedEntry) {
      try operations.delete(
        detached,
        at: instant("2026-03-08T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let deleted = try persistedEntry(day: day, in: context)
    context.delete(deleted)
    try context.save()
    try expectError(.deletedEntry) {
      try operations.edit(deleted, body: "Changed", at: Date(timeIntervalSince1970: 3))
    }

    let foreignContext = try makeContext()
    let foreign = try persistedEntry(day: day, in: foreignContext)
    try expectError(.foreignContext) {
      try operations.edit(foreign, body: "Changed", at: Date(timeIntervalSince1970: 4))
    }
    try expectError(.foreignContext) {
      try operations.delete(
        foreign,
        at: instant("2026-03-08T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
  }

  @Test("create save failure removes only the inserted Journal entry")
  func createSaveFailureRestoresPriorContext() throws {
    let context = try makeContext()
    let existing = try persistedEntry(day: localDate("2026-03-07"), in: context)
    let habit = Habit(name: "Original", cadence: .daily, target: 1)
    context.insert(habit)
    try context.save()
    habit.name = "Pending unrelated edit"
    let operations = JournalEntryOperations(context: context) { throw TestSaveFailure.expected }

    try expectError(.persistenceFailure) {
      _ = try operations.create(
        day: localDate("2026-03-08"),
        body: "Unsaved",
        at: instant("2026-03-08T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let journals = try context.fetch(FetchDescriptor<JournalEntry>())
    #expect(journals.count == 1)
    #expect(journals.first === existing)
    #expect(existing.body == "Body")
    #expect(habit.name == "Pending unrelated edit")
    #expect(context.hasChanges)
  }

  @Test("edit save failure restores exact Journal facts and unrelated pending work")
  func editSaveFailureRestoresPriorState() throws {
    let context = try makeContext()
    let entry = try persistedEntry(day: localDate("2026-03-08"), in: context)
    let goal = Goal(name: "Original", kind: .accumulate, target: 1)
    context.insert(goal)
    try context.save()
    goal.name = "Pending goal edit"
    let original = facts(entry)
    let operations = JournalEntryOperations(context: context) { throw TestSaveFailure.expected }

    try expectError(.persistenceFailure) {
      try operations.edit(
        entry,
        body: "Unsaved edit",
        at: instant("2026-03-08T12:00:00Z")
      )
    }

    #expect(facts(entry) == original)
    #expect(goal.name == "Pending goal edit")
    #expect(context.hasChanges)
  }

  @Test("delete save failure restores the same Journal model and exact facts")
  func deleteSaveFailureRestoresSameModel() throws {
    let context = try makeContext()
    let entry = try persistedEntry(day: localDate("2026-03-08"), in: context)
    let original = facts(entry)
    let operations = JournalEntryOperations(context: context) { throw TestSaveFailure.expected }

    try expectError(.persistenceFailure) {
      try operations.delete(
        entry,
        at: instant("2026-03-08T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let fetched = try context.fetch(FetchDescriptor<JournalEntry>())
    #expect(fetched.count == 1)
    #expect(fetched.first === entry)
    #expect(facts(entry) == original)
    #expect(!entry.isDeleted)
    #expect(context.insertedModelsArray.isEmpty)
    #expect(context.changedModelsArray.isEmpty)
    #expect(context.deletedModelsArray.isEmpty)
  }

  @Test("DST extreme zones and zone changes use the explicit operation context")
  func eligibilityUsesExplicitTimeZone() throws {
    let cases = [
      ("2024-03-10T10:30:00Z", "America/Los_Angeles", "2024-03-10", "2024-03-09"),
      ("2024-11-03T09:30:00Z", "America/Los_Angeles", "2024-11-03", "2024-11-02"),
      ("2024-07-04T10:30:00Z", "Pacific/Kiritimati", "2024-07-05", "2024-07-04"),
      ("2024-07-04T10:30:00Z", "America/Adak", "2024-07-04", "2024-07-03"),
    ]

    for (instantValue, zoneValue, todayValue, yesterdayValue) in cases {
      let context = try makeContext()
      let operations = JournalEntryOperations(context: context)
      let operationInstant = try instant(instantValue)
      let zone = try timeZone(zoneValue)

      let today = try operations.create(
        day: localDate(todayValue), body: "Today", at: operationInstant, timeZone: zone)
      let yesterday = try operations.create(
        day: localDate(yesterdayValue), body: "Yesterday", at: operationInstant, timeZone: zone)

      #expect(today.dayKey == todayValue)
      #expect(yesterday.dayKey == yesterdayValue)
    }

    let instant = try instant("2024-07-04T10:30:00Z")
    let day = try localDate("2024-07-05")
    let utcContext = try makeContext()
    let utcEntry = try persistedEntry(day: day, in: utcContext)
    try expectError(.ineligibleDay(day)) {
      try JournalEntryOperations(context: utcContext).delete(
        utcEntry, at: instant, timeZone: timeZone("UTC"))
    }
    #expect(utcEntry.dayKey == "2024-07-05")

    let kiritimatiContext = try makeContext()
    let kiritimatiEntry = try persistedEntry(day: day, in: kiritimatiContext)
    try JournalEntryOperations(context: kiritimatiContext).delete(
      kiritimatiEntry,
      at: instant,
      timeZone: timeZone("Pacific/Kiritimati")
    )
    #expect(kiritimatiEntry.dayKey == "2024-07-05")
  }

  @Test("invalid instants fail before insert edit or delete")
  func invalidInstantsFailBeforeMutation() throws {
    let context = try makeContext()
    let day = try localDate("2026-03-08")
    let entry = try persistedEntry(day: day, in: context)
    let original = facts(entry)
    var saveCount = 0
    let operations = JournalEntryOperations(context: context) { saveCount += 1 }
    let invalid = Date(timeIntervalSinceReferenceDate: .nan)

    try expectError(.invalidInstant) {
      _ = try operations.create(day: day, body: "Bad", at: invalid, timeZone: timeZone("UTC"))
    }
    try expectError(.invalidInstant) {
      try operations.edit(entry, body: "Bad", at: invalid)
    }
    try expectError(.invalidInstant) {
      try operations.delete(entry, at: invalid, timeZone: timeZone("UTC"))
    }

    #expect(facts(entry) == original)
    #expect(saveCount == 0)
  }

  @Test("Journal mutations leave Habit LogEntry and Goal facts unchanged")
  func mutationsDoNotTouchOtherDomains() throws {
    let context = try makeContext()
    let instant = try instant("2026-03-08T12:00:00Z")
    let habit = Habit(
      id: uuid("d1000000-0000-0000-0000-000000000001"),
      name: "Read",
      cadence: .daily,
      target: 2,
      createdAt: instant,
      bestStreak: 3
    )
    let log = LogEntry(
      id: uuid("d2000000-0000-0000-0000-000000000001"),
      timestamp: instant,
      amount: 1,
      habit: habit
    )
    habit.entries = [log]
    let goal = Goal(
      id: uuid("d3000000-0000-0000-0000-000000000001"),
      name: "Finish",
      kind: .accumulate,
      target: 10,
      createdAt: instant
    )
    context.insert(habit)
    context.insert(goal)
    try context.save()
    let expected = OtherDomainFacts(habit: habit, log: log, goal: goal)
    let operations = JournalEntryOperations(context: context)

    let journal = try operations.create(
      day: localDate("2026-03-08"), body: "Created", at: instant, timeZone: timeZone("UTC"))
    try operations.edit(journal, body: "Edited", at: instant.addingTimeInterval(1))
    try operations.delete(journal, at: instant.addingTimeInterval(2), timeZone: timeZone("UTC"))

    #expect(OtherDomainFacts(habit: habit, log: log, goal: goal) == expected)
    #expect(try context.fetch(FetchDescriptor<Habit>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<Goal>()).count == 1)
  }

  private struct EntryFacts: Equatable {
    let id: UUID
    let dayKey: String
    let body: String
    let createdAt: Date
    let editedAt: Date
  }

  private struct OtherDomainFacts: Equatable {
    let habitID: UUID
    let habitName: String
    let habitBestStreak: Int
    let logID: UUID
    let logTimestamp: Date
    let logAmount: Int
    let goalID: UUID
    let goalName: String
    let goalTarget: Int

    init(habit: Habit, log: LogEntry, goal: Goal) {
      habitID = habit.id
      habitName = habit.name
      habitBestStreak = habit.bestStreak
      logID = log.id
      logTimestamp = log.timestamp
      logAmount = log.amount
      goalID = goal.id
      goalName = goal.name
      goalTarget = goal.target
    }
  }

  private enum TestSaveFailure: Error {
    case expected
  }

  private func facts(_ entry: JournalEntry) -> EntryFacts {
    EntryFacts(
      id: entry.id,
      dayKey: entry.dayKey,
      body: entry.body,
      createdAt: entry.createdAt,
      editedAt: entry.editedAt
    )
  }

  private func persistedEntry(
    day: LocalDate,
    body: String = "Body",
    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    editedAt: Date = Date(timeIntervalSince1970: 1_700_000_100),
    in context: ModelContext
  ) throws -> JournalEntry {
    let entry = JournalEntry(
      day: day,
      body: body,
      createdAt: createdAt,
      editedAt: editedAt
    )
    context.insert(entry)
    try context.save()
    return entry
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func expectError(
    _ expected: JournalEntryOperationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected JournalEntryOperationError \(expected)")
    } catch let error as JournalEntryOperationError {
      #expect(error == expected)
    } catch {
      Issue.record("Expected JournalEntryOperationError, got \(error)")
    }
  }

  private func localDate(_ value: String) throws -> LocalDate {
    try LocalDate(validating: value)
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private func timeZone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }

  private func uuid(_ rawValue: String) -> UUID {
    UUID(uuidString: rawValue)!
  }
}
