import Foundation
import SwiftData

public enum JournalEntryQueryError: Error, Equatable, Sendable {
  case invalidWindow(start: LocalDate, end: LocalDate)
  case malformedDay(entryID: UUID, key: String)
  case duplicateDay(LocalDate, entryIDs: [UUID])
  case detachedEntry(UUID)
  case deletedEntry(UUID)
  case foreignContext(UUID)
  case persistenceFailure
}

@MainActor
public final class JournalEntryQuery {
  private let context: ModelContext
  private let fetchEntries: () throws -> [JournalEntry]

  public init(context: ModelContext) {
    self.context = context
    fetchEntries = { try context.fetch(FetchDescriptor<JournalEntry>()) }
  }

  init(
    context: ModelContext,
    fetch: @escaping () throws -> [JournalEntry]
  ) {
    self.context = context
    fetchEntries = fetch
  }

  public func entry(on day: LocalDate) throws -> JournalEntry? {
    try validatedEntries().first { $0.day == day }?.entry
  }

  public func entries() throws -> [JournalEntry] {
    try validatedEntries()
      .sorted(by: historyPrecedes)
      .map(\.entry)
  }

  public func writtenDays(
    from start: LocalDate,
    through end: LocalDate
  ) throws -> Set<LocalDate> {
    guard start <= end else {
      throw JournalEntryQueryError.invalidWindow(start: start, end: end)
    }
    return Set(
      try validatedEntries().lazy
        .map(\.day)
        .filter { start <= $0 && $0 <= end }
    )
  }

  private func validatedEntries() throws -> [ValidatedJournalEntry] {
    let entries: [JournalEntry]
    do {
      entries = try fetchEntries()
    } catch {
      throw JournalEntryQueryError.persistenceFailure
    }

    var validated: [ValidatedJournalEntry] = []
    validated.reserveCapacity(entries.count)
    for entry in entries.sorted(by: identityPrecedes) {
      try validateOwnership(of: entry)
      guard let day = LocalDate(rawValue: entry.dayKey) else {
        throw JournalEntryQueryError.malformedDay(entryID: entry.id, key: entry.dayKey)
      }
      validated.append(ValidatedJournalEntry(entry: entry, day: day))
    }

    let grouped = Dictionary(grouping: validated, by: { $0.day.rawValue })
    if let duplicate =
      grouped
      .filter({ $0.value.count > 1 })
      .sorted(by: { $0.key < $1.key })
      .first
    {
      let day = duplicate.value[0].day
      let ids = duplicate.value.map(\.entry.id).sorted(by: uuidPrecedes)
      throw JournalEntryQueryError.duplicateDay(day, entryIDs: ids)
    }
    return validated
  }

  private func validateOwnership(of entry: JournalEntry) throws {
    if entry.modelContext === context {
      guard !entry.isDeleted else {
        throw JournalEntryQueryError.deletedEntry(entry.id)
      }
      guard entry.persistentModelID.storeIdentifier != nil else {
        throw JournalEntryQueryError.detachedEntry(entry.id)
      }
      return
    }
    if entry.modelContext != nil {
      throw JournalEntryQueryError.foreignContext(entry.id)
    }
    if entry.persistentModelID.storeIdentifier != nil {
      throw JournalEntryQueryError.deletedEntry(entry.id)
    }
    throw JournalEntryQueryError.detachedEntry(entry.id)
  }

  private func identityPrecedes(_ lhs: JournalEntry, _ rhs: JournalEntry) -> Bool {
    uuidPrecedes(lhs.id, rhs.id)
  }

  private func historyPrecedes(
    _ lhs: ValidatedJournalEntry,
    _ rhs: ValidatedJournalEntry
  ) -> Bool {
    if lhs.day != rhs.day { return lhs.day > rhs.day }
    return uuidPrecedes(lhs.entry.id, rhs.entry.id)
  }

  private func uuidPrecedes(_ lhs: UUID, _ rhs: UUID) -> Bool {
    lhs.uuidString < rhs.uuidString
  }
}

private struct ValidatedJournalEntry {
  let entry: JournalEntry
  let day: LocalDate
}
