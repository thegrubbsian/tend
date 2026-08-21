import Foundation
import SwiftData
import Testing

@testable import Tend
@testable import TendCore

@MainActor
@Suite("Journal editor model")
struct JournalEditorModelTests {
  @Test("opening and cancelling blank or whitespace prose creates nothing")
  func blankNewEntryIsInert() async throws {
    let fixture = try JournalEditorFixture()
    let probe = EditorOperationProbe()
    let model = fixture.model(operations: probe.operations)

    #expect(model.body.isEmpty)
    #expect(model.status == .idle)
    #expect(model.entryID == nil)
    #expect(await fixture.clock.pendingCount == 0)

    model.updateBody("  \n\t", isComposing: false)

    #expect(model.status == .idle)
    #expect(await fixture.clock.pendingCount == 0)
    #expect(await model.flush())
    #expect(probe.createCalls.isEmpty)
    #expect(probe.editCalls.isEmpty)
  }

  @Test("a 500 millisecond debounce coalesces revisions and creates the latest prose once")
  func debounceCoalescesFirstCreate() async throws {
    let fixture = try JournalEditorFixture()
    let probe = EditorOperationProbe()
    var savedIDs: [UUID] = []
    let model = fixture.model(
      operations: probe.operations,
      onSaved: { savedIDs.append($0.id) }
    )

    model.updateBody("First", isComposing: false)
    await fixture.clock.waitForPendingCount(1)
    model.updateBody("Final body", isComposing: false)
    await fixture.clock.waitForPendingCount(2)

    #expect(model.status == .pending)
    #expect(await fixture.clock.requestedDurations == [.milliseconds(500), .milliseconds(500)])

    await fixture.clock.resumeNext()
    await yieldUntil { probe.createCalls.count == 0 }
    #expect(probe.createCalls.isEmpty)

    await fixture.clock.resumeNext()
    await yieldUntil { probe.createCalls.count == 1 }

    let call = try #require(probe.createCalls.first)
    #expect(call.day == fixture.today)
    #expect(call.body == "Final body")
    #expect(call.instant == fixture.now)
    #expect(call.timeZone.identifier == fixture.timeZone.identifier)
    #expect(model.body == "Final body")
    #expect(model.status == .saved)
    #expect(model.entryID == probe.storedEntry?.id)
    #expect(savedIDs == [probe.storedEntry?.id].compactMap { $0 })
  }

  @Test("an existing entry persists every later body including empty content")
  func existingEntryCanBeCleared() async throws {
    let fixture = try JournalEditorFixture()
    let entry = fixture.entry(day: fixture.today, body: "Existing")
    let probe = EditorOperationProbe(storedEntry: entry)
    let model = fixture.model(entry: entry, operations: probe.operations)

    model.updateBody("", isComposing: false)
    await fixture.clock.waitForPendingCount(1)
    await fixture.clock.resumeNext()
    await yieldUntil { probe.editCalls.count == 1 }

    let call = try #require(probe.editCalls.first)
    #expect(call.entry === entry)
    #expect(call.body.isEmpty)
    #expect(call.instant == fixture.now)
    #expect(entry.body.isEmpty)
    #expect(entry.editedAt == fixture.now)
    #expect(model.status == .saved)
    #expect(probe.createCalls.isEmpty)
    #expect(probe.deleteCalls.isEmpty)
  }

  @Test("marked text remains pending and cannot flush until composition commits")
  func markedTextNeverPersistsPartially() async throws {
    let fixture = try JournalEditorFixture()
    let probe = EditorOperationProbe()
    let model = fixture.model(operations: probe.operations)

    model.updateBody("に", isComposing: true)

    #expect(model.body == "に")
    #expect(model.status == .pending)
    #expect(model.isComposing)
    #expect(await fixture.clock.pendingCount == 0)
    #expect(!(await model.flush()))
    #expect(probe.createCalls.isEmpty)

    model.updateBody("日本", isComposing: false)
    await fixture.clock.waitForPendingCount(1)
    await fixture.clock.resumeNext()
    await yieldUntil { probe.createCalls.count == 1 }

    #expect(probe.createCalls.first?.body == "日本")
    #expect(model.status == .saved)
  }

  @Test("an immediate lifecycle flush cancels debounce and a stale wake cannot write twice")
  func immediateFlushSupersedesDebounce() async throws {
    let fixture = try JournalEditorFixture()
    let probe = EditorOperationProbe()
    let model = fixture.model(operations: probe.operations)

    model.updateBody("Leave now", isComposing: false)
    await fixture.clock.waitForPendingCount(1)

    #expect(await model.flush())
    #expect(probe.createCalls.count == 1)
    #expect(model.status == .saved)

    await fixture.clock.resumeNext()
    await yieldUntil { probe.createCalls.count == 1 }

    #expect(probe.createCalls.count == 1)
    #expect(probe.editCalls.isEmpty)
  }

  @Test("a failed navigation flush vetoes departure and Retry writes the same revision")
  func failedFlushRetainsDraftAndRetries() async throws {
    let fixture = try JournalEditorFixture()
    let probe = EditorOperationProbe()
    probe.saveFailuresRemaining = 1
    let model = fixture.model(operations: probe.operations)

    model.updateBody("Keep this draft", isComposing: false)
    await fixture.clock.waitForPendingCount(1)
    let revision = model.revision

    #expect(!(await model.flush()))
    let failure = try #require(model.status.failure)
    #expect(failure.operation == .save)
    #expect(failure.message == "This entry could not be saved.")
    #expect(failure.retryTitle == "Try again")
    #expect(model.body == "Keep this draft")
    #expect(model.revision == revision)
    #expect(model.entryID == nil)

    model.retry()

    #expect(model.revision == revision)
    #expect(probe.createCalls.map(\.body) == ["Keep this draft", "Keep this draft"])
    #expect(model.status == .saved)
    #expect(model.entryID != nil)

    await fixture.clock.resumeAll()
  }

  @Test("a concurrent same-day entry is edited instead of creating a duplicate")
  func duplicatePreventionResolvesExistingDay() async throws {
    let fixture = try JournalEditorFixture()
    let concurrent = fixture.entry(day: fixture.today, body: "Other writer")
    let probe = EditorOperationProbe(storedEntry: concurrent)
    let model = fixture.model(operations: probe.operations)

    model.updateBody("My final prose", isComposing: false)
    #expect(await model.flush())

    #expect(probe.findCalls == [fixture.today])
    #expect(probe.createCalls.isEmpty)
    #expect(probe.editCalls.count == 1)
    #expect(probe.editCalls.first?.entry === concurrent)
    #expect(concurrent.body == "My final prose")
    #expect(model.entryID == concurrent.id)
  }

  @Test("old entries remain editable but expose no new-entry scope or deletion")
  func oldEntriesRemainEditableForever() async throws {
    let fixture = try JournalEditorFixture()
    let oldDay = fixture.day("2020-01-02")
    let entry = fixture.entry(day: oldDay, body: "Old prose")
    let probe = EditorOperationProbe(storedEntry: entry)
    let model = fixture.model(day: oldDay, entry: entry, operations: probe.operations)

    #expect(model.scopeOptions.isEmpty)
    #expect(!model.canDelete)

    model.updateBody("Revised old prose", isComposing: false)
    #expect(await model.flush())

    #expect(probe.editCalls.first?.body == "Revised old prose")
    model.requestDeletion()
    #expect(!model.isDeletionConfirmationPresented)
    #expect(probe.deleteCalls.isEmpty)
  }

  @Test("Today and Yesterday are the only legal new-entry scope options")
  func scopeOptionsFollowExplicitLocalDay() throws {
    let fixture = try JournalEditorFixture()
    let todayModel = fixture.model(operations: EditorOperationProbe().operations)
    let yesterdayModel = fixture.model(
      day: fixture.yesterday,
      operations: EditorOperationProbe().operations
    )
    let oldModel = fixture.model(
      day: fixture.day("2026-03-01"),
      operations: EditorOperationProbe().operations
    )

    #expect(todayModel.scopeOptions.map(\.day) == [fixture.today, fixture.yesterday])
    #expect(todayModel.scopeOptions.map(\.label) == ["Today", "Yesterday"])
    #expect(todayModel.scopeOptions.map(\.isSelected) == [true, false])
    #expect(yesterdayModel.scopeOptions.map(\.isSelected) == [false, true])
    #expect(oldModel.scopeOptions.isEmpty)
  }

  @Test("legal deletion confirms, retains failure context, retries, and then exits")
  func deletionFailureRetriesSameEntry() throws {
    let fixture = try JournalEditorFixture()
    let entry = fixture.entry(day: fixture.today, body: "Delete me")
    let probe = EditorOperationProbe(storedEntry: entry)
    probe.deleteFailuresRemaining = 1
    var deletedIDs: [UUID] = []
    let model = fixture.model(
      entry: entry,
      operations: probe.operations,
      onDeleted: { deletedIDs.append(entry.id) }
    )

    #expect(model.canDelete)
    model.requestDeletion()
    #expect(model.isDeletionConfirmationPresented)
    model.confirmDeletion()

    #expect(!model.isDeletionConfirmationPresented)
    #expect(model.entryID == entry.id)
    #expect(model.body == "Delete me")
    let failure = try #require(model.status.failure)
    #expect(failure.operation == .delete)
    #expect(failure.message == "This entry could not be deleted.")
    #expect(deletedIDs.isEmpty)

    model.retry()

    #expect(probe.deleteCalls.count == 2)
    #expect(probe.deleteCalls.allSatisfy { $0.entry === entry })
    #expect(probe.deleteCalls.map(\.instant) == [fixture.now, fixture.now])
    #expect(model.entryID == nil)
    #expect(model.status == .idle)
    #expect(deletedIDs == [entry.id])
  }

  @Test("a failed delete resumes autosave without hiding its retry")
  func failedDeleteKeepsPendingRevisionAlive() async throws {
    let fixture = try JournalEditorFixture()
    let entry = fixture.entry(day: fixture.today, body: "Saved body")
    let probe = EditorOperationProbe(storedEntry: entry)
    probe.deleteFailuresRemaining = 1
    let model = fixture.model(entry: entry, operations: probe.operations)

    model.updateBody("Unsaved body", isComposing: false)
    await fixture.clock.waitForPendingCount(1)
    model.requestDeletion()
    model.confirmDeletion()
    await fixture.clock.waitForPendingCount(2)

    #expect(model.status.failure?.operation == .delete)
    #expect(await fixture.clock.pendingCount == 2)

    await fixture.clock.resumeNext()
    await fixture.clock.resumeNext()
    await yieldUntil { probe.editCalls.count == 1 }

    #expect(entry.body == "Unsaved body")
    #expect(model.status.failure?.operation == .delete)
    #expect(probe.deleteCalls.count == 1)
    await fixture.clock.resumeAll()
  }

  @Test("reverting an edit does not hide a retained delete failure")
  func revertedEditKeepsDeleteRetryVisible() async throws {
    let fixture = try JournalEditorFixture()
    let entry = fixture.entry(day: fixture.today, body: "Saved body")
    let probe = EditorOperationProbe(storedEntry: entry)
    probe.deleteFailuresRemaining = 1
    let model = fixture.model(entry: entry, operations: probe.operations)

    model.requestDeletion()
    model.confirmDeletion()
    #expect(model.status.failure?.operation == .delete)

    model.updateBody("Changed", isComposing: false)
    await fixture.clock.waitForPendingCount(1)
    model.updateBody("Saved body", isComposing: false)

    #expect(model.status.failure?.operation == .delete)
    #expect(probe.editCalls.isEmpty)
    await fixture.clock.resumeAll()
  }

  @Test("a delete retry retires when Yesterday becomes too old")
  func deleteRetryExpiresAtLocalMidnight() throws {
    let fixture = try JournalEditorFixture()
    let entry = fixture.entry(day: fixture.yesterday, body: "Yesterday")
    let probe = EditorOperationProbe(storedEntry: entry)
    probe.deleteFailuresRemaining = 1
    let model = fixture.model(
      day: fixture.yesterday,
      entry: entry,
      operations: probe.operations
    )

    model.requestDeletion()
    model.confirmDeletion()
    #expect(model.status.failure?.operation == .delete)

    fixture.now = fixture.now.addingTimeInterval(24 * 60 * 60)
    model.retry()

    #expect(probe.deleteCalls.count == 1)
    #expect(model.status.failure == nil)
    #expect(model.status == .saved)
    #expect(model.entryID == entry.id)
  }

  @Test("background flush failure preserves unsaved prose for the next active scene")
  func backgroundFailureKeepsUnsavedBody() async throws {
    let fixture = try JournalEditorFixture()
    let entry = fixture.entry(day: fixture.today, body: "Saved")
    let probe = EditorOperationProbe(storedEntry: entry)
    probe.saveFailuresRemaining = 1
    let model = fixture.model(entry: entry, operations: probe.operations)

    model.updateBody("Unsaved in background", isComposing: false)
    await fixture.clock.waitForPendingCount(1)

    #expect(!model.flushForLifecycle())
    #expect(model.body == "Unsaved in background")
    #expect(entry.body == "Saved")
    #expect(model.status.failure?.operation == .save)

    await fixture.clock.resumeAll()
  }

  @Test("live operations preserve exact timestamps and propagate the saved first line")
  func liveBoundaryUpdatesDurableOverview() async throws {
    let fixture = try JournalEditorFixture()
    let model = JournalEditorModel(
      day: fixture.today,
      entry: nil,
      context: fixture.context,
      now: { fixture.now },
      timeZone: { fixture.timeZone },
      sleep: fixture.sleep
    )

    model.updateBody("First line\nMore", isComposing: false)
    #expect(await model.flush())

    let persisted = try #require(
      try JournalEntryQuery(context: fixture.context).entry(on: fixture.today)
    )
    #expect(persisted.body == "First line\nMore")
    #expect(persisted.createdAt == fixture.now)
    #expect(persisted.editedAt == fixture.now)
    #expect(!fixture.context.hasChanges)

    let overview = JournalOverviewModel(context: fixture.context)
    overview.refresh(
      at: fixture.now,
      calendar: fixture.calendar,
      timeZone: fixture.timeZone,
      locale: fixture.locale
    )
    #expect(overview.presentation?.today.writtenEntry?.id == persisted.id)
    #expect(overview.presentation?.today.writtenEntry?.title == "First line")

    await fixture.clock.resumeAll()
  }
}

private enum EditorProbeError: Error {
  case expected
}

@MainActor
private final class EditorOperationProbe {
  struct CreateCall {
    let day: LocalDate
    let body: String
    let instant: Date
    let timeZone: TimeZone
  }

  struct EditCall {
    let entry: JournalEntry
    let body: String
    let instant: Date
  }

  struct DeleteCall {
    let entry: JournalEntry
    let instant: Date
    let timeZone: TimeZone
  }

  var storedEntry: JournalEntry?
  var saveFailuresRemaining = 0
  var deleteFailuresRemaining = 0
  private(set) var findCalls: [LocalDate] = []
  private(set) var createCalls: [CreateCall] = []
  private(set) var editCalls: [EditCall] = []
  private(set) var deleteCalls: [DeleteCall] = []

  init(storedEntry: JournalEntry? = nil) {
    self.storedEntry = storedEntry
  }

  var operations: JournalEditorOperations {
    JournalEditorOperations(
      findEntry: { [self] day in
        findCalls.append(day)
        return storedEntry?.dayKey == day.rawValue ? storedEntry : nil
      },
      create: { [self] day, body, instant, timeZone in
        createCalls.append(
          CreateCall(day: day, body: body, instant: instant, timeZone: timeZone)
        )
        if saveFailuresRemaining > 0 {
          saveFailuresRemaining -= 1
          throw EditorProbeError.expected
        }
        let entry = JournalEntry(
          id: UUID(uuidString: "b1000000-0000-0000-0000-000000000001")!,
          day: day,
          body: body,
          createdAt: instant,
          editedAt: instant
        )
        storedEntry = entry
        return entry
      },
      edit: { [self] entry, body, instant in
        editCalls.append(EditCall(entry: entry, body: body, instant: instant))
        if saveFailuresRemaining > 0 {
          saveFailuresRemaining -= 1
          throw EditorProbeError.expected
        }
        entry.body = body
        entry.editedAt = instant
      },
      delete: { [self] entry, instant, timeZone in
        deleteCalls.append(DeleteCall(entry: entry, instant: instant, timeZone: timeZone))
        if deleteFailuresRemaining > 0 {
          deleteFailuresRemaining -= 1
          throw EditorProbeError.expected
        }
        storedEntry = nil
      }
    )
  }
}

private actor ManualJournalEditorClock {
  private struct Waiter {
    let continuation: CheckedContinuation<Void, Never>
  }

  private var waiters: [Waiter] = []
  private(set) var requestedDurations: [Duration] = []

  var pendingCount: Int { waiters.count }

  func sleep(_ duration: Duration) async throws {
    requestedDurations.append(duration)
    await withCheckedContinuation { continuation in
      waiters.append(Waiter(continuation: continuation))
    }
  }

  func waitForPendingCount(_ expected: Int) async {
    while waiters.count < expected {
      await Task.yield()
    }
  }

  func resumeNext() {
    guard !waiters.isEmpty else { return }
    waiters.removeFirst().continuation.resume()
  }

  func resumeAll() {
    let pending = waiters
    waiters.removeAll()
    for waiter in pending {
      waiter.continuation.resume()
    }
  }
}

@MainActor
private final class JournalEditorFixture {
  let context: ModelContext
  let clock = ManualJournalEditorClock()
  let timeZone: TimeZone
  let locale = Locale(identifier: "en_US")
  var now: Date
  let today: LocalDate
  let yesterday: LocalDate
  var calendar: Calendar

  init() throws {
    context = ModelContext(try TendModelContainer.inMemory())
    timeZone = try #require(TimeZone(identifier: "UTC"))
    now = try #require(ISO8601DateFormatter().date(from: "2026-03-08T12:00:00Z"))
    today = try LocalDate(validating: "2026-03-08")
    yesterday = try LocalDate(validating: "2026-03-07")
    calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    calendar.timeZone = timeZone
  }

  var sleep: JournalEditorModel.Sleep {
    { [clock] duration in
      try await clock.sleep(duration)
    }
  }

  func model(
    day: LocalDate? = nil,
    entry: JournalEntry? = nil,
    operations: JournalEditorOperations,
    onSaved: @escaping @MainActor (JournalEntry) -> Void = { _ in },
    onDeleted: @escaping @MainActor () -> Void = {}
  ) -> JournalEditorModel {
    JournalEditorModel(
      day: day ?? today,
      entry: entry,
      operations: operations,
      now: { self.now },
      timeZone: { self.timeZone },
      sleep: sleep,
      onSaved: onSaved,
      onDeleted: onDeleted
    )
  }

  func entry(day: LocalDate, body: String) -> JournalEntry {
    JournalEntry(
      id: UUID(),
      day: day,
      body: body,
      createdAt: now.addingTimeInterval(-60),
      editedAt: now.addingTimeInterval(-60)
    )
  }

  func day(_ value: String) -> LocalDate {
    guard let day = LocalDate(rawValue: value) else {
      preconditionFailure("Invalid editor fixture day: \(value)")
    }
    return day
  }
}

@MainActor
private func yieldUntil(_ condition: @MainActor () -> Bool) async {
  for _ in 0..<1_000 {
    if condition() { return }
    await Task.yield()
  }
  Issue.record("Condition did not become true")
}
