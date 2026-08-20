import Foundation
import Observation
import SwiftData
import TendCore

struct JournalOverviewLoadFailure: Equatable, Sendable {
  let message: String
  let retryTitle: String
}

struct JournalOverviewEntry: Equatable, Identifiable, Sendable {
  let id: UUID
  let day: LocalDate
  let dateText: String
  let title: String
}

enum JournalTodayPresentation: Equatable, Sendable {
  case unwritten(day: LocalDate, dateText: String)
  case written(JournalOverviewEntry)

  var unwrittenDay: LocalDate? {
    guard case .unwritten(let day, _) = self else { return nil }
    return day
  }

  var writtenEntry: JournalOverviewEntry? {
    guard case .written(let entry) = self else { return nil }
    return entry
  }
}

struct JournalOverviewPresentation: Equatable, Sendable {
  let today: JournalTodayPresentation
  let pastEntries: [JournalOverviewEntry]
  let month: JournalMonthProjection
}

@MainActor
struct JournalOverviewOperations {
  typealias LoadEntries = () throws -> [JournalEntry]

  let loadEntries: LoadEntries

  static func live(context: ModelContext) -> Self {
    let query = JournalEntryQuery(context: context)
    return Self(loadEntries: query.entries)
  }
}

@MainActor
@Observable
final class JournalOverviewModel {
  private(set) var presentation: JournalOverviewPresentation?
  private(set) var loadFailure: JournalOverviewLoadFailure?
  private(set) var selectedMonth: LocalDate?

  var canSelectPreviousMonth: Bool {
    guard let month = presentation?.month else { return false }
    return month.selectedMonth > month.earliestMonth
  }

  var canSelectNextMonth: Bool {
    guard let month = presentation?.month else { return false }
    return month.selectedMonth < month.latestMonth
  }

  @ObservationIgnored private let operations: JournalOverviewOperations
  @ObservationIgnored private var lastRefreshRequest: RefreshRequest?
  @ObservationIgnored private var lastSuccessfulRequest: RefreshRequest?
  @ObservationIgnored private var lastEntryFingerprint: EntryGraphFingerprint?

  convenience init(context: ModelContext) {
    self.init(operations: .live(context: context))
  }

  init(operations: JournalOverviewOperations) {
    self.operations = operations
  }

  func refresh(
    at instant: Date,
    calendar: Calendar,
    timeZone: TimeZone,
    locale: Locale
  ) {
    load(
      request: Self.refreshRequest(
        instant: instant,
        calendar: calendar,
        timeZone: timeZone,
        locale: locale
      )
    )
  }

  func refreshIfEntryGraphChanged(
    _ entries: [JournalEntry],
    at instant: Date,
    calendar: Calendar,
    timeZone: TimeZone,
    locale: Locale
  ) {
    let request = Self.refreshRequest(
      instant: instant,
      calendar: calendar,
      timeZone: timeZone,
      locale: locale
    )
    let fingerprint = EntryGraphFingerprint(entries: entries)
    guard
      loadFailure != nil || request != lastSuccessfulRequest
        || fingerprint != lastEntryFingerprint
    else { return }
    load(request: request)
  }

  func retryRefresh() {
    guard loadFailure != nil, let lastRefreshRequest else { return }
    load(request: lastRefreshRequest)
  }

  func selectPreviousMonth() {
    navigateMonth(by: -1)
  }

  func selectNextMonth() {
    navigateMonth(by: 1)
  }

  private func navigateMonth(by offset: Int) {
    guard
      let request = lastRefreshRequest,
      let month = presentation?.month,
      let requestedMonth = Self.adjacentMonth(month.selectedMonth, by: offset),
      month.earliestMonth <= requestedMonth,
      requestedMonth <= month.latestMonth
    else { return }
    selectedMonth = requestedMonth
    load(request: request)
  }

  private func load(request: RefreshRequest) {
    lastRefreshRequest = request
    do {
      let entries = try operations.loadEntries()
      let replacement = try JournalOverviewProjector(
        request: request,
        requestedMonth: selectedMonth
      ).presentation(entries: entries)
      presentation = replacement
      selectedMonth = replacement.month.selectedMonth
      loadFailure = nil
      lastSuccessfulRequest = request
      lastEntryFingerprint = EntryGraphFingerprint(entries: entries)
    } catch {
      presentation = nil
      loadFailure = JournalOverviewLoadFailure(
        message: String(
          localized: "Journal is unavailable right now.",
          locale: request.locale
        ),
        retryTitle: String(localized: "Try again", locale: request.locale)
      )
    }
  }

  private static func refreshRequest(
    instant: Date,
    calendar: Calendar,
    timeZone: TimeZone,
    locale: Locale
  ) -> RefreshRequest {
    let fixedTimeZone = TimeZone(identifier: timeZone.identifier) ?? timeZone
    let fixedLocale = Locale(identifier: locale.identifier)
    var fixedCalendar =
      calendar.identifier == .gregorian
      ? calendar
      : Calendar(identifier: .gregorian)
    fixedCalendar.locale = fixedLocale
    fixedCalendar.timeZone = fixedTimeZone
    fixedCalendar.firstWeekday = 2
    fixedCalendar.minimumDaysInFirstWeek = 4
    return RefreshRequest(
      instant: instant,
      calendar: fixedCalendar,
      timeZone: fixedTimeZone,
      locale: fixedLocale
    )
  }

  private static func adjacentMonth(_ month: LocalDate, by offset: Int) -> LocalDate? {
    switch offset {
    case -1 where month.month == 1:
      guard month.year > 1 else { return nil }
      return LocalDate(year: month.year - 1, month: 12, day: 1)
    case -1:
      return LocalDate(year: month.year, month: month.month - 1, day: 1)
    case 1 where month.month == 12:
      guard month.year < 9_999 else { return nil }
      return LocalDate(year: month.year + 1, month: 1, day: 1)
    case 1:
      return LocalDate(year: month.year, month: month.month + 1, day: 1)
    default:
      return nil
    }
  }
}

extension JournalOverviewModel {
  fileprivate struct RefreshRequest: Equatable {
    let instant: Date
    let calendar: Calendar
    let timeZone: TimeZone
    let locale: Locale
  }

  fileprivate struct EntryGraphFingerprint: Equatable {
    let entries: [EntryFingerprint]

    init(entries: [JournalEntry]) {
      self.entries = entries.map(EntryFingerprint.init).sorted(by: EntryFingerprint.precedes)
    }
  }

  fileprivate struct EntryFingerprint: Equatable {
    let id: UUID
    let dayKey: String
    let body: String
    let createdAt: Date
    let editedAt: Date

    init(entry: JournalEntry) {
      id = entry.id
      dayKey = entry.dayKey
      body = entry.body
      createdAt = entry.createdAt
      editedAt = entry.editedAt
    }

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
      if lhs.id != rhs.id { return lhs.id.uuidString < rhs.id.uuidString }
      if lhs.dayKey != rhs.dayKey { return lhs.dayKey < rhs.dayKey }
      if lhs.body != rhs.body { return lhs.body < rhs.body }
      if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
      return lhs.editedAt < rhs.editedAt
    }
  }
}

private struct JournalOverviewProjector {
  let request: JournalOverviewModel.RefreshRequest
  let requestedMonth: LocalDate?

  func presentation(entries: [JournalEntry]) throws -> JournalOverviewPresentation {
    let today = try localDate(containing: request.instant)
    let candidates = try validatedCandidates(entries, today: today)
    let currentMonth = try month(containing: today)
    let earliestMonth = try candidates.map(\.day).min().map(month(containing:)) ?? currentMonth
    let selectedMonth = clampedSelection(
      requestedMonth ?? currentMonth,
      earliest: earliestMonth,
      latest: currentMonth
    )
    let formatter = JournalOverviewFormatter(request: request)
    let rows = try candidates.map { try row(for: $0, formatter: formatter) }
    let todayRow = rows.first { $0.day == today }
    let pastRows = rows.filter { $0.day < today }
    let monthProjection = try monthProjection(
      candidates: candidates,
      today: today,
      earliestMonth: earliestMonth,
      selectedMonth: selectedMonth,
      latestMonth: currentMonth,
      formatter: formatter
    )

    return JournalOverviewPresentation(
      today: todayRow.map(JournalTodayPresentation.written)
        ?? .unwritten(day: today, dateText: try formatter.day(today)),
      pastEntries: pastRows,
      month: monthProjection
    )
  }

  private func validatedCandidates(
    _ entries: [JournalEntry],
    today: LocalDate
  ) throws -> [Candidate] {
    var candidates: [Candidate] = []
    candidates.reserveCapacity(entries.count)
    for entry in entries {
      guard let day = LocalDate(rawValue: entry.dayKey) else {
        throw ProjectionError.malformedDay
      }
      guard day <= today else {
        throw ProjectionError.futureEntry
      }
      candidates.append(Candidate(entry: entry, day: day))
    }

    let grouped = Dictionary(grouping: candidates, by: \.day)
    guard grouped.values.allSatisfy({ $0.count == 1 }) else {
      throw ProjectionError.duplicateDay
    }
    return candidates.sorted {
      if $0.day != $1.day { return $0.day > $1.day }
      return $0.entry.id.uuidString < $1.entry.id.uuidString
    }
  }

  private func row(
    for candidate: Candidate,
    formatter: JournalOverviewFormatter
  ) throws -> JournalOverviewEntry {
    JournalOverviewEntry(
      id: candidate.entry.id,
      day: candidate.day,
      dateText: try formatter.day(candidate.day),
      title: formatter.title(body: candidate.entry.body)
    )
  }

  private func monthProjection(
    candidates: [Candidate],
    today: LocalDate,
    earliestMonth: LocalDate,
    selectedMonth: LocalDate,
    latestMonth: LocalDate,
    formatter: JournalOverviewFormatter
  ) throws -> JournalMonthProjection {
    let entriesByDay = Dictionary(uniqueKeysWithValues: candidates.map { ($0.day, $0.entry.id) })
    var cells: [JournalMonthCell] = []
    var day = selectedMonth
    while day.year == selectedMonth.year && day.month == selectedMonth.month {
      let state = entriesByDay[day].map(JournalMonthCellState.written(entryID:)) ?? .absent
      cells.append(JournalMonthCell(day: day, state: state, isToday: day == today))
      day = try day.next()
    }

    let geometry = AlmanacMonthGridGeometry(
      monthStart: try selectedMonth.start(in: request.timeZone),
      dayCount: cells.count,
      calendar: request.calendar
    )
    return JournalMonthProjection(
      earliestMonth: earliestMonth,
      selectedMonth: selectedMonth,
      latestMonth: latestMonth,
      monthTitle: try formatter.month(selectedMonth),
      cells: cells,
      leadingFillerCount: geometry.leadingFillerCount,
      trailingFillerCount: geometry.trailingFillerCount
    )
  }

  private func localDate(containing instant: Date) throws -> LocalDate {
    let components = request.calendar.dateComponents(
      [.era, .year, .month, .day],
      from: instant
    )
    guard
      components.era == 1,
      let year = components.year,
      let month = components.month,
      let day = components.day,
      let localDate = LocalDate(year: year, month: month, day: day)
    else {
      throw ProjectionError.invalidInstant
    }
    return localDate
  }

  private func month(containing day: LocalDate) throws -> LocalDate {
    guard let month = LocalDate(year: day.year, month: day.month, day: 1) else {
      throw ProjectionError.unrepresentableMonth
    }
    return month
  }

  private func clampedSelection(
    _ selected: LocalDate,
    earliest: LocalDate,
    latest: LocalDate
  ) -> LocalDate {
    if selected < earliest { return earliest }
    if selected > latest { return latest }
    return selected
  }

  private struct Candidate {
    let entry: JournalEntry
    let day: LocalDate
  }

  private enum ProjectionError: Error {
    case invalidInstant
    case malformedDay
    case duplicateDay
    case futureEntry
    case unrepresentableMonth
  }
}

private struct JournalOverviewFormatter {
  private let request: JournalOverviewModel.RefreshRequest
  private let dayFormatter: DateFormatter
  private let monthFormatter: DateFormatter

  init(request: JournalOverviewModel.RefreshRequest) {
    self.request = request
    dayFormatter = Self.formatter(
      template: "EEEE MMMM d yyyy",
      request: request
    )
    monthFormatter = Self.formatter(
      template: "MMMM yyyy",
      request: request
    )
  }

  func day(_ day: LocalDate) throws -> String {
    dayFormatter.string(from: try day.start(in: request.timeZone))
  }

  func month(_ month: LocalDate) throws -> String {
    monthFormatter.string(from: try month.start(in: request.timeZone))
  }

  func title(body: String) -> String {
    let firstLine =
      body
      .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
      .first
      .map(String.init)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      ?? ""
    return firstLine.isEmpty
      ? String(localized: "No text", locale: request.locale)
      : firstLine
  }

  private static func formatter(
    template: String,
    request: JournalOverviewModel.RefreshRequest
  ) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = request.locale
    formatter.calendar = request.calendar
    formatter.timeZone = request.timeZone
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter
  }
}
