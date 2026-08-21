import Foundation
import Observation
import SwiftData
import TendCore

struct JournalEditorFailure: Equatable, Sendable {
  enum Operation: Equatable, Sendable {
    case save
    case delete
  }

  let operation: Operation
  let message: String
  let retryTitle: String
}

enum JournalEditorStatus: Equatable, Sendable {
  case idle
  case pending
  case saved
  case failed(JournalEditorFailure)

  var failure: JournalEditorFailure? {
    guard case .failed(let failure) = self else { return nil }
    return failure
  }
}

struct JournalEditorScopeOption: Equatable, Identifiable, Sendable {
  let day: LocalDate
  let label: String
  let isSelected: Bool

  var id: LocalDate { day }
}

@MainActor
struct JournalEditorOperations {
  typealias FindEntry = (_ day: LocalDate) throws -> JournalEntry?
  typealias Create = (
    _ day: LocalDate,
    _ body: String,
    _ instant: Date,
    _ timeZone: TimeZone
  ) throws -> JournalEntry
  typealias Edit = (
    _ entry: JournalEntry,
    _ body: String,
    _ instant: Date
  ) throws -> Void
  typealias Delete = (
    _ entry: JournalEntry,
    _ instant: Date,
    _ timeZone: TimeZone
  ) throws -> Void

  let findEntry: FindEntry
  let create: Create
  let edit: Edit
  let delete: Delete

  static func live(context: ModelContext) -> Self {
    let query = JournalEntryQuery(context: context)
    let operations = JournalEntryOperations(context: context)
    return Self(
      findEntry: query.entry,
      create: { day, body, instant, timeZone in
        try operations.create(
          day: day,
          body: body,
          at: instant,
          timeZone: timeZone
        )
      },
      edit: { entry, body, instant in
        try operations.edit(entry, body: body, at: instant)
      },
      delete: { entry, instant, timeZone in
        try operations.delete(entry, at: instant, timeZone: timeZone)
      }
    )
  }
}

@MainActor
@Observable
final class JournalEditorModel {
  typealias Sleep = @Sendable (Duration) async throws -> Void

  let day: LocalDate
  private(set) var body: String
  private(set) var status: JournalEditorStatus = .idle
  private(set) var isComposing = false
  private(set) var isDeletionConfirmationPresented = false
  private(set) var revision: UInt64 = 0

  var entryID: UUID? { entry?.id }

  var scopeOptions: [JournalEditorScopeOption] {
    guard !isDeleted, let today = currentLocalDay() else { return [] }
    let days = [today, try? today.previous()].compactMap { $0 }
    guard days.contains(day) else { return [] }
    return days.enumerated().map { index, optionDay in
      JournalEditorScopeOption(
        day: optionDay,
        label: String(
          localized: index == 0 ? "Today" : "Yesterday",
          locale: locale()
        ),
        isSelected: optionDay == day
      )
    }
  }

  var canDelete: Bool {
    guard !isDeleted, entry != nil, let today = currentLocalDay() else { return false }
    if day == today { return true }
    return (try? today.previous()) == day
  }

  @ObservationIgnored private var entry: JournalEntry?
  @ObservationIgnored private var persistedBody: String
  @ObservationIgnored private let operations: JournalEditorOperations
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private let timeZone: () -> TimeZone
  @ObservationIgnored private let locale: () -> Locale
  @ObservationIgnored private let sleep: Sleep
  @ObservationIgnored private let onSaved: @MainActor (JournalEntry) -> Void
  @ObservationIgnored private let onDeleted: @MainActor () -> Void
  @ObservationIgnored private var debounceTask: Task<Void, Never>?
  @ObservationIgnored private var retryAction: RetryAction?
  @ObservationIgnored private var deletionFailure: JournalEditorFailure?
  @ObservationIgnored private var isDeleted = false

  convenience init(
    day: LocalDate,
    entry: JournalEntry?,
    context: ModelContext,
    now: @escaping () -> Date = Date.init,
    timeZone: @escaping () -> TimeZone = { TimeZone.current },
    locale: @escaping () -> Locale = { Locale.current },
    sleep: @escaping Sleep = { duration in
      try await Task.sleep(for: duration)
    },
    onSaved: @escaping @MainActor (JournalEntry) -> Void = { _ in },
    onDeleted: @escaping @MainActor () -> Void = {}
  ) {
    self.init(
      day: day,
      entry: entry,
      operations: .live(context: context),
      now: now,
      timeZone: timeZone,
      locale: locale,
      sleep: sleep,
      onSaved: onSaved,
      onDeleted: onDeleted
    )
  }

  init(
    day: LocalDate,
    entry: JournalEntry?,
    operations: JournalEditorOperations,
    now: @escaping () -> Date = Date.init,
    timeZone: @escaping () -> TimeZone = { TimeZone.current },
    locale: @escaping () -> Locale = { Locale.current },
    sleep: @escaping Sleep = { duration in
      try await Task.sleep(for: duration)
    },
    onSaved: @escaping @MainActor (JournalEntry) -> Void = { _ in },
    onDeleted: @escaping @MainActor () -> Void = {}
  ) {
    precondition(entry == nil || entry?.dayKey == day.rawValue)
    self.day = day
    body = entry?.body ?? ""
    self.entry = entry
    persistedBody = entry?.body ?? ""
    self.operations = operations
    self.now = now
    self.timeZone = timeZone
    self.locale = locale
    self.sleep = sleep
    self.onSaved = onSaved
    self.onDeleted = onDeleted
  }

  deinit {
    debounceTask?.cancel()
  }

  func updateBody(_ replacement: String, isComposing: Bool) {
    guard !isDeleted else { return }
    let bodyChanged = replacement != body
    let compositionChanged = isComposing != self.isComposing
    guard bodyChanged || compositionChanged else { return }

    body = replacement
    self.isComposing = isComposing
    revision &+= 1
    retryAction = nil
    cancelDebounce()

    guard hasUnsavedChanges else {
      status = entry == nil ? .idle : .saved
      return
    }
    status = .pending
    guard !isComposing else { return }
    scheduleDebounce(for: revision)
  }

  @discardableResult
  func flush() async -> Bool {
    flushPendingRevision()
  }

  @discardableResult
  func flushForLifecycle() -> Bool {
    flushPendingRevision()
  }

  private func flushPendingRevision() -> Bool {
    cancelDebounce()
    guard !isComposing else {
      status = .pending
      return false
    }
    guard hasUnsavedChanges else { return true }
    persist(revision: revision)
    return !hasUnsavedChanges && status.failure?.operation != .save
  }

  func retry() {
    if let retryAction {
      switch retryAction {
      case .save(let revision):
        guard !isComposing else { return }
        persist(revision: revision)
      }
      return
    }
    guard deletionFailure != nil else { return }
    guard canDelete else {
      retireExpiredDeletionRetry()
      return
    }
    performDeletion()
  }

  func requestDeletion() {
    guard canDelete else { return }
    isDeletionConfirmationPresented = true
  }

  func cancelDeletion() {
    isDeletionConfirmationPresented = false
  }

  func confirmDeletion() {
    guard isDeletionConfirmationPresented else { return }
    isDeletionConfirmationPresented = false
    performDeletion()
  }

  func stop() {
    cancelDebounce()
  }

  private var hasUnsavedChanges: Bool {
    guard !isDeleted else { return false }
    if entry == nil {
      return !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return body != persistedBody
  }

  private func scheduleDebounce(for requestedRevision: UInt64) {
    debounceTask = Task { [weak self, sleep] in
      do {
        try await sleep(.milliseconds(500))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      self?.persist(revision: requestedRevision)
    }
  }

  private func cancelDebounce() {
    debounceTask?.cancel()
    debounceTask = nil
  }

  private func persist(revision requestedRevision: UInt64) {
    guard
      requestedRevision == revision,
      !isComposing,
      hasUnsavedChanges
    else { return }
    cancelDebounce()

    do {
      let savedEntry: JournalEntry
      let instant = now()
      if let entry {
        try operations.edit(entry, body, instant)
        savedEntry = entry
      } else if let existing = try operations.findEntry(day) {
        guard existing.dayKey == day.rawValue else {
          throw EditorConfigurationError.unexpectedEntryDay
        }
        entry = existing
        persistedBody = existing.body
        if existing.body != body {
          try operations.edit(existing, body, instant)
        }
        savedEntry = existing
      } else {
        let created = try operations.create(day, body, instant, timeZone())
        guard created.dayKey == day.rawValue else {
          throw EditorConfigurationError.unexpectedEntryDay
        }
        entry = created
        savedEntry = created
      }

      persistedBody = body
      retryAction = nil
      status = deletionFailure.map(JournalEditorStatus.failed) ?? .saved
      onSaved(savedEntry)
    } catch {
      retryAction = .save(requestedRevision)
      status = .failed(failure(for: .save))
    }
  }

  private func performDeletion() {
    guard canDelete, let entry else { return }
    cancelDebounce()
    do {
      try operations.delete(entry, now(), timeZone())
      self.entry = nil
      persistedBody = body
      isDeleted = true
      retryAction = nil
      deletionFailure = nil
      status = .idle
      onDeleted()
    } catch {
      let failure = failure(for: .delete)
      deletionFailure = failure
      status = .failed(failure)
      if hasUnsavedChanges, !isComposing {
        scheduleDebounce(for: revision)
      }
    }
  }

  private func retireExpiredDeletionRetry() {
    deletionFailure = nil
    if hasUnsavedChanges {
      status = .pending
      if !isComposing {
        scheduleDebounce(for: revision)
      }
    } else {
      status = entry == nil ? .idle : .saved
    }
  }

  private func failure(
    for operation: JournalEditorFailure.Operation
  ) -> JournalEditorFailure {
    let message =
      switch operation {
      case .save:
        String(localized: "This entry could not be saved.", locale: locale())
      case .delete:
        String(localized: "This entry could not be deleted.", locale: locale())
      }
    return JournalEditorFailure(
      operation: operation,
      message: message,
      retryTitle: String(localized: "Try again", locale: locale())
    )
  }

  private func currentLocalDay() -> LocalDate? {
    let instant = now()
    guard instant.timeIntervalSinceReferenceDate.isFinite else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone()
    let components = calendar.dateComponents([.era, .year, .month, .day], from: instant)
    guard
      components.era == 1,
      let year = components.year,
      let month = components.month,
      let day = components.day
    else { return nil }
    return LocalDate(year: year, month: month, day: day)
  }
}

extension JournalEditorModel {
  fileprivate enum RetryAction {
    case save(UInt64)
  }

  fileprivate enum EditorConfigurationError: Error {
    case unexpectedEntryDay
  }
}
