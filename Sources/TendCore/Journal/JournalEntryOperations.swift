import Foundation
import SwiftData

public enum JournalEntryOperationError: Error, Equatable, Sendable {
  case invalidInstant
  case ineligibleDay(LocalDate)
  case duplicateDay(LocalDate)
  case malformedDay(String)
  case detachedEntry
  case deletedEntry
  case foreignContext
  case persistenceFailure
}

@MainActor
public final class JournalEntryOperations {
  private let context: ModelContext
  private let saveContext: () throws -> Void

  public init(context: ModelContext) {
    self.context = context
    saveContext = { try context.save() }
  }

  init(context: ModelContext, save: @escaping () throws -> Void) {
    self.context = context
    saveContext = save
  }

  @discardableResult
  public func create(
    day: LocalDate,
    body: String,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> JournalEntry {
    try authorizeExistenceChange(on: day, at: instant, timeZone: timeZone)
    context.processPendingChanges()
    let entries = try fetchedEntries()
    guard !entries.contains(where: { $0.dayKey == day.rawValue }) else {
      throw JournalEntryOperationError.duplicateDay(day)
    }

    let entry = JournalEntry(
      day: day,
      body: body,
      createdAt: instant,
      editedAt: instant
    )
    context.insert(entry)

    do {
      try saveContext()
      return entry
    } catch {
      context.delete(entry)
      context.processPendingChanges()
      throw JournalEntryOperationError.persistenceFailure
    }
  }

  public func edit(
    _ entry: JournalEntry,
    body: String,
    at instant: Date
  ) throws {
    try validateOwnership(of: entry)
    _ = try parsedDay(entry.dayKey)
    try validate(instant)
    guard body != entry.body else { return }

    let priorBody = entry.body
    let priorEditedAt = entry.editedAt
    entry.body = body
    entry.editedAt = instant

    do {
      try saveContext()
    } catch {
      entry.body = priorBody
      entry.editedAt = priorEditedAt
      context.processPendingChanges()
      throw JournalEntryOperationError.persistenceFailure
    }
  }

  public func delete(
    _ entry: JournalEntry,
    at instant: Date,
    timeZone: TimeZone
  ) throws {
    try validateOwnership(of: entry)
    let day = try parsedDay(entry.dayKey)
    try authorizeExistenceChange(on: day, at: instant, timeZone: timeZone)
    let prior = JournalEntryFacts(entry)
    context.delete(entry)
    context.processPendingChanges()

    do {
      try saveContext()
    } catch {
      context.insert(entry)
      prior.restore(entry)
      context.processPendingChanges()
      throw JournalEntryOperationError.persistenceFailure
    }
  }

  private func fetchedEntries() throws -> [JournalEntry] {
    do {
      return try context.fetch(FetchDescriptor<JournalEntry>())
    } catch {
      throw JournalEntryOperationError.persistenceFailure
    }
  }

  private func validateOwnership(of entry: JournalEntry) throws {
    if entry.modelContext === context {
      guard !entry.isDeleted else {
        throw JournalEntryOperationError.deletedEntry
      }
      guard entry.persistentModelID.storeIdentifier != nil else {
        throw JournalEntryOperationError.detachedEntry
      }
      return
    }
    if entry.modelContext != nil {
      throw JournalEntryOperationError.foreignContext
    }
    if entry.persistentModelID.storeIdentifier != nil {
      throw JournalEntryOperationError.deletedEntry
    }
    throw JournalEntryOperationError.detachedEntry
  }

  private func parsedDay(_ key: String) throws -> LocalDate {
    guard let day = LocalDate(rawValue: key) else {
      throw JournalEntryOperationError.malformedDay(key)
    }
    return day
  }

  private func authorizeExistenceChange(
    on day: LocalDate,
    at instant: Date,
    timeZone: TimeZone
  ) throws {
    let today = try localDay(at: instant, timeZone: timeZone)
    if day == today { return }
    if let yesterday = try? today.previous(), day == yesterday { return }
    throw JournalEntryOperationError.ineligibleDay(day)
  }

  private func localDay(at instant: Date, timeZone: TimeZone) throws -> LocalDate {
    try validate(instant)
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.era, .year, .month, .day], from: instant)
    guard
      components.era == 1,
      let year = components.year,
      let month = components.month,
      let day = components.day,
      let localDate = LocalDate(year: year, month: month, day: day)
    else {
      throw JournalEntryOperationError.invalidInstant
    }
    return localDate
  }

  private func validate(_ instant: Date) throws {
    guard instant.timeIntervalSinceReferenceDate.isFinite else {
      throw JournalEntryOperationError.invalidInstant
    }
  }
}

private struct JournalEntryFacts {
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

  func restore(_ entry: JournalEntry) {
    if entry.id != id { entry.id = id }
    if entry.dayKey != dayKey { entry.dayKey = dayKey }
    if entry.body != body { entry.body = body }
    if entry.createdAt != createdAt { entry.createdAt = createdAt }
    if entry.editedAt != editedAt { entry.editedAt = editedAt }
  }
}
