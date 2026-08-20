import Foundation
import SwiftData

public enum JournalEntryQueryError: Error, Equatable, Sendable {
  case invalidWindow(start: LocalDate, end: LocalDate)
  case malformedDay(entryID: UUID, key: String)
  case duplicateDay(LocalDate, entryIDs: [UUID])
  case detachedEntry(UUID)
  case deletedEntry
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

    let ownedEntries = try ownedEntries(from: entries)
    var validated: [ValidatedJournalEntry] = []
    var malformed: [MalformedJournalDay] = []
    validated.reserveCapacity(ownedEntries.count)
    malformed.reserveCapacity(ownedEntries.count)
    for entry in ownedEntries {
      if let day = LocalDate(rawValue: entry.dayKey) {
        validated.append(ValidatedJournalEntry(entry: entry, day: day))
      } else {
        malformed.append(MalformedJournalDay(entryID: entry.id, key: entry.dayKey))
      }
    }
    if let failure = malformed.sorted(by: malformedPrecedes).first {
      throw JournalEntryQueryError.malformedDay(entryID: failure.entryID, key: failure.key)
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

  private func ownedEntries(from entries: [JournalEntry]) throws -> [JournalEntry] {
    var owned: [JournalEntry] = []
    var detachedIDs: [UUID] = []
    var foreignIDs: [UUID] = []
    var containsDeleted = false
    owned.reserveCapacity(entries.count)

    for entry in entries {
      if entry.modelContext === context {
        if entry.isDeleted {
          containsDeleted = true
        } else if entry.persistentModelID.storeIdentifier == nil {
          detachedIDs.append(entry.id)
        } else {
          owned.append(entry)
        }
      } else if entry.modelContext != nil {
        foreignIDs.append(entry.id)
      } else if entry.persistentModelID.storeIdentifier != nil {
        containsDeleted = true
      } else {
        detachedIDs.append(entry.id)
      }
    }

    if containsDeleted {
      throw JournalEntryQueryError.deletedEntry
    }
    if let id = detachedIDs.sorted(by: uuidPrecedes).first {
      throw JournalEntryQueryError.detachedEntry(id)
    }
    if let id = foreignIDs.sorted(by: uuidPrecedes).first {
      throw JournalEntryQueryError.foreignContext(id)
    }
    return owned
  }

  private func malformedPrecedes(
    _ lhs: MalformedJournalDay,
    _ rhs: MalformedJournalDay
  ) -> Bool {
    if lhs.entryID != rhs.entryID {
      return uuidPrecedes(lhs.entryID, rhs.entryID)
    }
    return lhs.key < rhs.key
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

private struct MalformedJournalDay {
  let entryID: UUID
  let key: String
}

private struct ValidatedJournalEntry {
  let entry: JournalEntry
  let day: LocalDate
}
