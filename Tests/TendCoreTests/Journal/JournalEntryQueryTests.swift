import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Journal entry query")
struct JournalEntryQueryTests {
  @Test("empty stores return absence empty history and empty written days")
  func emptyStoreReturnsAbsenceAndEmptyCollections() throws {
    let context = try makeContext()
    let query = JournalEntryQuery(context: context)
    let day = try localDate("2026-03-08")

    #expect(try query.entry(on: day) == nil)
    #expect(try query.entries().isEmpty)
    #expect(try query.writtenDays(from: day, through: day).isEmpty)
    #expect(!context.hasChanges)
  }

  @Test("lookup and history use exact identity and deterministic reverse day order")
  func lookupAndHistoryAreDeterministic() throws {
    let context = try makeContext()
    let fixtures = try [
      entry(
        id: "a3000000-0000-0000-0000-000000000003",
        day: "2026-03-07",
        body: "Old"
      ),
      entry(
        id: "a3000000-0000-0000-0000-000000000001",
        day: "2026-03-09",
        body: "Newest"
      ),
      entry(
        id: "a3000000-0000-0000-0000-000000000002",
        day: "2026-03-08",
        body: "Middle"
      ),
    ]
    for fixture in fixtures.reversed() {
      context.insert(fixture)
    }
    try context.save()
    let query = JournalEntryQuery(context: context)

    let hit = try query.entry(on: localDate("2026-03-08"))
    #expect(hit === fixtures[2])
    #expect(try query.entry(on: localDate("2026-03-06")) == nil)
    let expectedIDs = [fixtures[1].id, fixtures[2].id, fixtures[0].id]
    for _ in 0..<5 {
      #expect(try query.entries().map(\.id) == expectedIDs)
    }
    #expect(fixtures.map(\.body) == ["Old", "Newest", "Middle"])
  }

  @Test("written-day windows are inclusive across leap and year boundaries")
  func writtenDayWindowsAreInclusive() throws {
    let context = try makeContext()
    let keys = ["2023-12-31", "2024-01-01", "2024-02-29", "2024-03-01"]
    for (index, key) in keys.enumerated() {
      context.insert(
        try entry(
          id: "a4000000-0000-0000-0000-00000000000\(index + 1)",
          day: key,
          body: key
        ))
    }
    try context.save()
    let query = JournalEntryQuery(context: context)

    #expect(
      try query.writtenDays(
        from: localDate("2023-12-31"), through: localDate("2024-01-01")
      ) == Set([localDate("2023-12-31"), localDate("2024-01-01")])
    )
    #expect(
      try query.writtenDays(
        from: localDate("2024-02-29"), through: localDate("2024-02-29")
      ) == Set([localDate("2024-02-29")])
    )
    #expect(
      try query.writtenDays(
        from: localDate("2024-01-02"), through: localDate("2024-02-28")
      ).isEmpty
    )
  }

  @Test("duplicate days fail with stable sorted conflicting identities")
  func duplicateDaysFailDeterministically() throws {
    let context = try makeContext()
    let day = try localDate("2026-03-08")
    let higher = JournalEntry(
      id: uuid("b1000000-0000-0000-0000-000000000002"),
      day: day,
      body: "Higher",
      createdAt: Date(timeIntervalSince1970: 2),
      editedAt: Date(timeIntervalSince1970: 2)
    )
    let lower = JournalEntry(
      id: uuid("b1000000-0000-0000-0000-000000000001"),
      day: day,
      body: "Lower",
      createdAt: Date(timeIntervalSince1970: 1),
      editedAt: Date(timeIntervalSince1970: 1)
    )
    context.insert(higher)
    context.insert(lower)
    try context.save()
    let query = JournalEntryQuery(context: context)
    let expected = JournalEntryQueryError.duplicateDay(
      day,
      entryIDs: [lower.id, higher.id]
    )

    for _ in 0..<3 {
      try expectError(expected) { _ = try query.entry(on: day) }
      try expectError(expected) { _ = try query.entries() }
      try expectError(expected) {
        _ = try query.writtenDays(from: day, through: day)
      }
    }
  }

  @Test("malformed persisted days fail with exact stable identity and key")
  func malformedDaysFailTruthfully() throws {
    let context = try makeContext()
    let malformed = try entry(
      id: "b2000000-0000-0000-0000-000000000001",
      day: "2026-03-08",
      body: "Imported"
    )
    malformed.dayKey = "today"
    context.insert(malformed)
    try context.save()
    let query = JournalEntryQuery(context: context)
    let expected = JournalEntryQueryError.malformedDay(
      entryID: malformed.id,
      key: "today"
    )

    try expectError(expected) { _ = try query.entries() }
    try expectError(expected) {
      _ = try query.entry(on: localDate("2026-03-08"))
    }
  }

  @Test("inverted windows fail while the full supported range does not overflow")
  func windowsValidateOrderWithoutIterationOverflow() throws {
    let context = try makeContext()
    let minimum = try localDate("0001-01-01")
    let maximum = try localDate("9999-12-31")
    let first = JournalEntry(
      id: uuid("b3000000-0000-0000-0000-000000000001"),
      day: minimum,
      body: "First",
      createdAt: Date(timeIntervalSince1970: 1),
      editedAt: Date(timeIntervalSince1970: 1)
    )
    let last = JournalEntry(
      id: uuid("b3000000-0000-0000-0000-000000000002"),
      day: maximum,
      body: "Last",
      createdAt: Date(timeIntervalSince1970: 2),
      editedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(first)
    context.insert(last)
    try context.save()
    let query = JournalEntryQuery(context: context)

    try expectError(.invalidWindow(start: maximum, end: minimum)) {
      _ = try query.writtenDays(from: maximum, through: minimum)
    }
    #expect(
      try query.writtenDays(from: minimum, through: maximum) == Set([minimum, maximum])
    )
  }

  @Test("detached deleted foreign and persistence failures stay distinct")
  func ownershipAndFetchFailuresAreDistinct() throws {
    let context = try makeContext()
    let day = try localDate("2026-03-08")
    let detached = JournalEntry(
      id: uuid("b4000000-0000-0000-0000-000000000001"),
      day: day,
      body: "Detached",
      createdAt: Date(timeIntervalSince1970: 1),
      editedAt: Date(timeIntervalSince1970: 1)
    )
    let detachedQuery = JournalEntryQuery(context: context) { [detached] }
    try expectError(.detachedEntry(detached.id)) { _ = try detachedQuery.entries() }

    let deleted = try persistedEntry(
      id: "b4000000-0000-0000-0000-000000000002", day: day, in: context)
    context.delete(deleted)
    context.processPendingChanges()
    let deletedQuery = JournalEntryQuery(context: context) { [deleted] }
    try expectError(.deletedEntry(deleted.id)) { _ = try deletedQuery.entries() }
    context.rollback()

    let foreignContext = try makeContext()
    let foreign = try persistedEntry(
      id: "b4000000-0000-0000-0000-000000000003", day: day, in: foreignContext)
    let foreignQuery = JournalEntryQuery(context: context) { [foreign] }
    try expectError(.foreignContext(foreign.id)) { _ = try foreignQuery.entries() }

    let failedQuery = JournalEntryQuery(context: context) { throw TestFetchFailure.expected }
    try expectError(.persistenceFailure) { _ = try failedQuery.entries() }
  }

  @Test("queries perform no writes and preserve unrelated pending work and timestamps")
  func queriesAreReadOnlyAndOperationLocal() throws {
    let context = try makeContext()
    let day = try localDate("2026-03-08")
    let journal = try persistedEntry(
      id: "b5000000-0000-0000-0000-000000000001",
      day: day,
      in: context
    )
    let habit = Habit(name: "Pending", cadence: .daily, target: 1)
    context.insert(habit)
    context.processPendingChanges()
    let expectedJournal = JournalFacts(journal)
    let expectedInserted = context.insertedModelsArray.map(\.persistentModelID)
    let query = JournalEntryQuery(context: context)

    #expect(try query.entry(on: day) === journal)
    #expect(try query.entries().map(\.id) == [journal.id])
    #expect(try query.writtenDays(from: day, through: day) == Set([day]))

    #expect(JournalFacts(journal) == expectedJournal)
    #expect(context.insertedModelsArray.map(\.persistentModelID) == expectedInserted)
    #expect(context.changedModelsArray.isEmpty)
    #expect(context.deletedModelsArray.isEmpty)
    #expect(context.hasChanges)
  }

  private struct JournalFacts: Equatable {
    let id: UUID
    let dayKey: String
    let body: String
    let createdAt: Date
    let editedAt: Date

    init(_ entry: JournalEntry) {
      id = entry.id
      dayKey = entry.dayKey
      body = entry.body
      createdAt = entry.createdAt
      editedAt = entry.editedAt
    }
  }

  private enum TestFetchFailure: Error {
    case expected
  }

  private func entry(id: String, day: String, body: String) throws -> JournalEntry {
    JournalEntry(
      id: uuid(id),
      day: try localDate(day),
      body: body,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      editedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
  }

  private func persistedEntry(
    id: String,
    day: LocalDate,
    in context: ModelContext
  ) throws -> JournalEntry {
    let entry = JournalEntry(
      id: uuid(id),
      day: day,
      body: "Body",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      editedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
    context.insert(entry)
    try context.save()
    return entry
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func expectError(
    _ expected: JournalEntryQueryError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected JournalEntryQueryError \(expected)")
    } catch let error as JournalEntryQueryError {
      #expect(error == expected)
    } catch {
      Issue.record("Expected JournalEntryQueryError, got \(error)")
    }
  }

  private func localDate(_ value: String) throws -> LocalDate {
    try LocalDate(validating: value)
  }

  private func uuid(_ rawValue: String) -> UUID {
    UUID(uuidString: rawValue)!
  }
}
