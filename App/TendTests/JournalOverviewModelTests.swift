import Foundation
import SwiftData
import Testing

@testable import Tend
@testable import TendCore

@MainActor
@Suite("Journal overview model")
struct JournalOverviewModelTests {
  @Test("empty Journal exposes an unwritten Today and a navigable current month")
  func emptyJournalProjectsCurrentMonth() throws {
    let fixture = try JournalOverviewFixture()
    let model = JournalOverviewModel(context: fixture.context)

    model.refresh(
      at: try fixture.instant("2026-03-08T12:00:00Z"),
      calendar: fixture.calendar,
      timeZone: fixture.timeZone,
      locale: fixture.locale
    )

    let presentation = try #require(model.presentation)
    let today = try #require(presentation.today.unwrittenDay)
    #expect(today == fixture.day("2026-03-08"))
    #expect(presentation.pastEntries.isEmpty)
    #expect(presentation.month.earliestMonth == fixture.day("2026-03-01"))
    #expect(presentation.month.selectedMonth == fixture.day("2026-03-01"))
    #expect(presentation.month.latestMonth == fixture.day("2026-03-01"))
    #expect(presentation.month.cells.count == 31)
    #expect(presentation.month.leadingFillerCount == 6)
    #expect(presentation.month.trailingFillerCount == 5)
    #expect(
      presentation.month.cells.first(where: { $0.isToday })?.day
        == fixture.day("2026-03-08")
    )
    #expect(!model.canSelectPreviousMonth)
    #expect(!model.canSelectNextMonth)
    #expect(model.loadFailure == nil)
  }

  @Test("today and past rows derive current first lines in reverse local-day order")
  func projectsTodayAndPastEntries() throws {
    let fixture = try JournalOverviewFixture()
    let today = try fixture.insert(
      id: "a1000000-0000-0000-0000-000000000001",
      day: "2026-03-08",
      body: "Today in the garden\nSecond line"
    )
    let yesterday = try fixture.insert(
      id: "a1000000-0000-0000-0000-000000000002",
      day: "2026-03-07",
      body: "  Walked outside  \nDetails"
    )
    let empty = try fixture.insert(
      id: "a1000000-0000-0000-0000-000000000003",
      day: "2026-02-28",
      body: ""
    )
    let model = JournalOverviewModel(context: fixture.context)

    try fixture.refresh(model, at: "2026-03-08T12:00:00Z")

    let presentation = try #require(model.presentation)
    let todayRow = try #require(presentation.today.writtenEntry)
    #expect(todayRow.id == today.id)
    #expect(todayRow.day == fixture.day("2026-03-08"))
    #expect(todayRow.title == "Today in the garden")
    #expect(presentation.pastEntries.map(\.id) == [yesterday.id, empty.id])
    #expect(
      presentation.pastEntries.map(\.day) == [
        fixture.day("2026-03-07"),
        fixture.day("2026-02-28"),
      ])
    #expect(presentation.pastEntries.map(\.title) == ["Walked outside", "No text"])

    model.selectPreviousMonth()
    #expect(
      model.presentation?.month.cells.first(where: {
        $0.day == fixture.day("2026-02-28")
      })?.state
        == .written(entryID: empty.id)
    )
  }

  @Test("entry graph fingerprints refresh changed first lines without duplicate queries")
  func refreshesOnlyForChangedEntryGraph() throws {
    let fixture = try JournalOverviewFixture()
    let entry = try fixture.insert(
      id: "a2000000-0000-0000-0000-000000000001",
      day: "2026-03-07",
      body: "Before\nDetails"
    )
    let query = JournalEntryQuery(context: fixture.context)
    var queryCount = 0
    let model = JournalOverviewModel(
      operations: JournalOverviewOperations(loadEntries: {
        queryCount += 1
        return try query.entries()
      })
    )
    let instant = try fixture.instant("2026-03-08T12:00:00Z")

    model.refresh(
      at: instant,
      calendar: fixture.calendar,
      timeZone: fixture.timeZone,
      locale: fixture.locale
    )
    model.refreshIfEntryGraphChanged(
      [entry],
      at: instant,
      calendar: fixture.calendar,
      timeZone: fixture.timeZone,
      locale: fixture.locale
    )
    #expect(queryCount == 1)

    entry.body = "After\nDetails"
    entry.editedAt = try fixture.instant("2026-03-08T12:01:00Z")
    try fixture.context.save()
    model.refreshIfEntryGraphChanged(
      [entry],
      at: instant,
      calendar: fixture.calendar,
      timeZone: fixture.timeZone,
      locale: fixture.locale
    )

    #expect(queryCount == 2)
    #expect(model.presentation?.pastEntries.first?.id == entry.id)
    #expect(model.presentation?.pastEntries.first?.title == "After")

    model.refreshIfEntryGraphChanged(
      [entry],
      at: instant,
      calendar: fixture.calendar,
      timeZone: fixture.timeZone,
      locale: fixture.locale
    )
    #expect(queryCount == 2)
  }

  @Test("leap February uses Monday-first geometry and binary written cells")
  func projectsLeapMonthGarden() throws {
    let fixture = try JournalOverviewFixture()
    let leapEntry = try fixture.insert(
      id: "a3000000-0000-0000-0000-000000000001",
      day: "2024-02-29",
      body: "Leap day"
    )
    let model = JournalOverviewModel(context: fixture.context)

    try fixture.refresh(model, at: "2024-03-08T12:00:00Z")
    model.selectPreviousMonth()

    let month = try #require(model.presentation?.month)
    #expect(month.selectedMonth == fixture.day("2024-02-01"))
    #expect(month.cells.count == 29)
    #expect(month.leadingFillerCount == 3)
    #expect(month.trailingFillerCount == 3)
    #expect(
      month.cells.first(where: { $0.day == fixture.day("2024-02-29") })?.state
        == .written(entryID: leapEntry.id)
    )
    #expect(
      month.cells.first(where: { $0.day == fixture.day("2024-02-28") })?.state
        == .absent
    )
    #expect(month.cells.allSatisfy { !$0.isToday })
  }

  @Test("month navigation crosses years and keeps the selected month")
  func navigatesAcrossYearBoundary() throws {
    let fixture = try JournalOverviewFixture()
    _ = try fixture.insert(
      id: "a4000000-0000-0000-0000-000000000001",
      day: "2025-12-31",
      body: "Year end"
    )
    let model = JournalOverviewModel(context: fixture.context)

    try fixture.refresh(model, at: "2026-01-15T12:00:00Z")
    #expect(model.canSelectPreviousMonth)
    model.selectPreviousMonth()
    #expect(model.presentation?.month.selectedMonth == fixture.day("2025-12-01"))
    #expect(!model.canSelectPreviousMonth)
    #expect(model.canSelectNextMonth)

    try fixture.refresh(model, at: "2026-01-15T12:05:00Z")
    #expect(model.presentation?.month.selectedMonth == fixture.day("2025-12-01"))

    model.selectNextMonth()
    #expect(model.presentation?.month.selectedMonth == fixture.day("2026-01-01"))
    #expect(!model.canSelectNextMonth)
  }

  @Test("deleting the earliest entry clamps a removed selected month")
  func deletionClampsSelectedMonth() throws {
    let fixture = try JournalOverviewFixture()
    let oldEntry = try fixture.insert(
      id: "a5000000-0000-0000-0000-000000000001",
      day: "2026-01-10",
      body: "Old"
    )
    let model = JournalOverviewModel(context: fixture.context)

    try fixture.refresh(model, at: "2026-03-08T12:00:00Z")
    model.selectPreviousMonth()
    model.selectPreviousMonth()
    #expect(model.presentation?.month.selectedMonth == fixture.day("2026-01-01"))

    fixture.context.delete(oldEntry)
    try fixture.context.save()
    try fixture.refresh(model, at: "2026-03-08T12:01:00Z")

    let month = try #require(model.presentation?.month)
    #expect(month.earliestMonth == fixture.day("2026-03-01"))
    #expect(month.selectedMonth == fixture.day("2026-03-01"))
    #expect(month.latestMonth == fixture.day("2026-03-01"))
  }

  @Test("malformed duplicate and future entries replace all derived content with retry")
  func invalidDataNeverInventsEmptyHistory() throws {
    try expectProjectionFailure { fixture in
      let malformed = try fixture.insert(
        id: "a6000000-0000-0000-0000-000000000001",
        day: "2026-03-07",
        body: "Malformed"
      )
      malformed.dayKey = "today"
      try fixture.context.save()
    }

    try expectProjectionFailure { fixture in
      _ = try fixture.insert(
        id: "a6000000-0000-0000-0000-000000000002",
        day: "2026-03-07",
        body: "First"
      )
      _ = try fixture.insert(
        id: "a6000000-0000-0000-0000-000000000003",
        day: "2026-03-07",
        body: "Second"
      )
    }

    try expectProjectionFailure { fixture in
      _ = try fixture.insert(
        id: "a6000000-0000-0000-0000-000000000004",
        day: "2026-03-09",
        body: "Future"
      )
    }
  }

  @Test("retry replaces a failed load without fabricating prior content")
  func retriesFailedLoad() throws {
    let fixture = try JournalOverviewFixture()
    let entry = try fixture.insert(
      id: "a7000000-0000-0000-0000-000000000001",
      day: "2026-03-07",
      body: "Recovered"
    )
    var fails = true
    let model = JournalOverviewModel(
      operations: JournalOverviewOperations(loadEntries: {
        if fails { throw ProbeFailure.expected }
        return [entry]
      })
    )

    try fixture.refresh(model, at: "2026-03-08T12:00:00Z")
    #expect(model.presentation == nil)
    #expect(model.loadFailure?.message == "Journal is unavailable right now.")
    #expect(model.loadFailure?.retryTitle == "Try again")

    fails = false
    model.retryRefresh()

    #expect(model.loadFailure == nil)
    #expect(model.presentation?.pastEntries.map(\.title) == ["Recovered"])
  }

  @Test("local midnight moves Today and its clay-marker metadata")
  func refreshesAtLocalMidnight() throws {
    let fixture = try JournalOverviewFixture()
    let model = JournalOverviewModel(context: fixture.context)

    try fixture.refresh(model, at: "2026-03-08T23:59:59Z")
    #expect(model.presentation?.today.unwrittenDay == fixture.day("2026-03-08"))
    #expect(
      model.presentation?.month.cells.first(where: { $0.isToday })?.day
        == fixture.day("2026-03-08")
    )

    try fixture.refresh(model, at: "2026-03-09T00:00:00Z")
    #expect(model.presentation?.today.unwrittenDay == fixture.day("2026-03-09"))
    #expect(
      model.presentation?.month.cells.first(where: { $0.isToday })?.day
        == fixture.day("2026-03-09")
    )
  }

  @Test("time-zone and locale changes rebuild one explicit local context")
  func refreshesForTimeZoneAndLocaleChanges() throws {
    let fixture = try JournalOverviewFixture()
    let model = JournalOverviewModel(context: fixture.context)
    let instant = try fixture.instant("2026-03-08T01:00:00Z")

    model.refresh(
      at: instant,
      calendar: fixture.calendar,
      timeZone: fixture.timeZone,
      locale: Locale(identifier: "en_US")
    )
    #expect(model.presentation?.today.unwrittenDay == fixture.day("2026-03-08"))
    #expect(model.presentation?.month.monthTitle == "March 2026")

    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    model.refresh(
      at: instant,
      calendar: fixture.calendar,
      timeZone: losAngeles,
      locale: Locale(identifier: "fr_FR")
    )
    #expect(model.presentation?.today.unwrittenDay == fixture.day("2026-03-07"))
    #expect(model.presentation?.month.monthTitle == "mars 2026")
  }

  @Test("repeated projection is deterministic and never dirties the store")
  func repeatedRefreshIsReadOnlyAndDeterministic() throws {
    let fixture = try JournalOverviewFixture()
    _ = try fixture.insert(
      id: "a8000000-0000-0000-0000-000000000001",
      day: "2026-03-07",
      body: "Stable"
    )
    let model = JournalOverviewModel(context: fixture.context)

    try fixture.refresh(model, at: "2026-03-08T12:00:00Z")
    let first = try #require(model.presentation)
    #expect(!fixture.context.hasChanges)

    try fixture.refresh(model, at: "2026-03-08T12:00:00Z")
    let second = try #require(model.presentation)

    #expect(second == first)
    #expect(!fixture.context.hasChanges)
  }

  private func expectProjectionFailure(
    configure: (JournalOverviewFixture) throws -> Void
  ) throws {
    let fixture = try JournalOverviewFixture()
    try configure(fixture)
    let model = JournalOverviewModel(context: fixture.context)

    try fixture.refresh(model, at: "2026-03-08T12:00:00Z")

    #expect(model.presentation == nil)
    #expect(model.loadFailure?.message == "Journal is unavailable right now.")
    #expect(model.loadFailure?.retryTitle == "Try again")
  }
}

private enum ProbeFailure: Error {
  case expected
}

@MainActor
private final class JournalOverviewFixture {
  let context: ModelContext
  let timeZone: TimeZone
  let locale = Locale(identifier: "en_US")
  var calendar: Calendar

  init() throws {
    context = ModelContext(try TendModelContainer.inMemory())
    timeZone = try #require(TimeZone(identifier: "UTC"))
    calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    calendar.timeZone = timeZone
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
  }

  func refresh(
    _ model: JournalOverviewModel,
    at value: String,
    timeZone: TimeZone? = nil,
    locale: Locale? = nil
  ) throws {
    model.refresh(
      at: try instant(value),
      calendar: calendar,
      timeZone: timeZone ?? self.timeZone,
      locale: locale ?? self.locale
    )
  }

  func insert(id rawID: String, day rawDay: String, body: String) throws -> JournalEntry {
    let timestamp = try instant("2026-03-08T12:00:00Z")
    let entry = JournalEntry(
      id: try #require(UUID(uuidString: rawID)),
      day: day(rawDay),
      body: body,
      createdAt: timestamp,
      editedAt: timestamp
    )
    context.insert(entry)
    try context.save()
    return entry
  }

  func day(_ value: String) -> LocalDate {
    guard let day = LocalDate(rawValue: value) else {
      preconditionFailure("Invalid Journal fixture day: \(value)")
    }
    return day
  }

  func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }
}
