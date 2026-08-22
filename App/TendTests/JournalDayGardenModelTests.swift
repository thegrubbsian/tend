import Foundation
import SwiftData
import Testing

@testable import Tend
@testable import TendCore

@MainActor
@Suite("Journal day garden model")
struct JournalDayGardenModelTests {
  @Test("Almanac rows format progress, result, leaf fill, and accessibility truthfully")
  func presentationFormatsEveryState() throws {
    let day = try localDate("2026-08-05")
    let start = try instant("2026-08-05T00:00:00Z")
    let end = try instant("2026-08-06T00:00:00Z")
    let rows = [
      row(1, "Met", .met, start, end, progress: 2, target: 2, unit: "sessions", met: true),
      row(2, "Missed", .missed, start, end, progress: 1, target: 3, unit: "pages", met: false),
      row(3, "Open", .open, start, end, progress: 1, target: 1, unit: "times", met: true),
      row(4, "Grace", .grace, start, end, progress: 1, target: 2, unit: "times", met: false),
      row(5, "Exempt", .exempt, start, end),
      row(6, "Broken", .unavailable, start, end),
    ]
    let probe = GardenProjectionProbe(results: [rows])
    let model = JournalDayGardenModel(operations: probe.operations)

    #expect(
      model.refresh(
        day: day,
        habits: [],
        context: refreshContext(start)
      ))

    #expect(model.rows.map(\.name) == ["Met", "Missed", "Open", "Grace", "Exempt", "Broken"])
    #expect(
      model.rows.map(\.stateText) == ["Met", "Missed", "Open", "Grace", "Exempt", "Unavailable"])
    #expect(
      model.rows.map(\.progressText)
        == [
          "2 of 2 sessions",
          "1 of 3 pages",
          "1 of 1 time",
          "1 of 2 times",
          "No requirement",
          "Progress unavailable",
        ])
    #expect(model.rows.map(\.isLeafFilled) == [true, false, true, false, false, false])
    #expect(model.rows.map(\.showsRetry) == [false, false, false, false, false, true])
    #expect(model.rows[0].accessibilityValue == "2 of 2 sessions, Met")
    #expect(model.rows[4].accessibilityValue == "Exempt, No requirement")
    #expect(model.rows[5].accessibilityValue == "Unavailable, Progress unavailable, Try again")
  }

  @Test("selection, Habit graph, local context, activation, and retry drive refresh")
  func inputFingerprintControlsRefresh() throws {
    let day = try localDate("2026-08-05")
    let nextDay = try day.next()
    let now = try instant("2026-08-05T12:00:00Z")
    let habit = Habit(
      id: uuid(1),
      name: "Read",
      cadence: .daily,
      target: 2,
      unit: "pages",
      createdAt: now
    )
    let period = HabitActivityPeriod(startedAt: now, habit: habit)
    let bucket = HabitBucket(
      periodKey: "day:2026-08-05",
      startAt: try instant("2026-08-05T00:00:00Z"),
      endAt: try instant("2026-08-06T00:00:00Z"),
      cadence: .daily,
      habit: habit
    )
    let entry = LogEntry(timestamp: now, amount: 1, habit: habit, bucket: bucket)
    habit.activityPeriods = [period]
    habit.buckets = [bucket]
    habit.entries = [entry]
    bucket.entries = [entry]
    let probe = GardenProjectionProbe(results: [[]])
    let model = JournalDayGardenModel(operations: probe.operations)
    let utc = refreshContext(now)

    #expect(model.refresh(day: day, habits: [habit], context: utc))
    #expect(probe.calls.count == 1)
    #expect(!model.refresh(day: day, habits: [habit], context: utc))
    #expect(probe.calls.count == 1)

    entry.amount = 2
    #expect(model.refresh(day: day, habits: [habit], context: utc))
    #expect(probe.calls.count == 2)

    #expect(model.refresh(day: nextDay, habits: [habit], context: utc))
    #expect(probe.calls.count == 3)

    let pacific = refreshContext(
      now,
      timeZone: "America/Los_Angeles",
      locale: "en_US"
    )
    #expect(model.refresh(day: nextDay, habits: [habit], context: pacific))
    #expect(probe.calls.count == 4)

    let french = refreshContext(
      now,
      timeZone: "America/Los_Angeles",
      locale: "fr_FR"
    )
    #expect(model.refresh(day: nextDay, habits: [habit], context: french))
    #expect(probe.calls.count == 5)

    #expect(model.refresh(day: nextDay, habits: [habit], context: french, force: true))
    #expect(probe.calls.count == 6)
    model.retry()
    #expect(probe.calls.count == 7)
  }

  @Test("retry replaces one unavailable row without disturbing valid siblings")
  func retryReprojectsUnavailableSibling() throws {
    let day = try localDate("2026-08-05")
    let start = try instant("2026-08-05T00:00:00Z")
    let end = try instant("2026-08-06T00:00:00Z")
    let valid = row(
      1, "Breathe", .open, start, end, progress: 0, target: 1, unit: "time", met: false)
    let unavailable = row(2, "Stretch", .unavailable, start, end)
    let repaired = row(
      2, "Stretch", .open, start, end, progress: 1, target: 1, unit: "time", met: true)
    let probe = GardenProjectionProbe(results: [[valid, unavailable], [valid, repaired]])
    let model = JournalDayGardenModel(operations: probe.operations)

    _ = model.refresh(day: day, habits: [], context: refreshContext(start))
    #expect(model.rows.map(\.stateText) == ["Open", "Unavailable"])

    model.retry()

    #expect(probe.calls.count == 2)
    #expect(model.rows.map(\.stateText) == ["Open", "Open"])
    #expect(model.rows.map(\.name) == ["Breathe", "Stretch"])
  }

  @Test("real logging, correction, archive, and reactivation refresh live without rewriting prose")
  func liveHabitChangesRefreshWithoutTouchingJournalEntry() throws {
    let context = ModelContext(try TendModelContainer.inMemory())
    let zone = try timeZone("UTC")
    let day = try localDate("2026-08-05")
    let createdAt = try instant("2026-08-05T08:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Read", target: 2, unit: "pages"),
      cadence: .daily,
      at: createdAt,
      timeZone: zone
    )
    let prose = try JournalEntryOperations(context: context).create(
      day: day,
      body: "A quiet page",
      at: createdAt,
      timeZone: zone
    )
    let proseBytes = JournalBytes(prose)
    let model = JournalDayGardenModel(context: context)
    let logging = LogEntryOperations(context: context)
    let lifecycle = HabitActivityOperations(context: context)

    _ = model.refresh(
      day: day,
      habits: [habit],
      context: refreshContext(createdAt)
    )
    #expect(model.rows.first?.progressText == "0 of 2 pages")
    #expect(model.rows.first?.stateText == "Open")

    let entry = try logging.append(
      amount: 1,
      to: habit,
      at: createdAt.addingTimeInterval(60),
      timeZone: zone
    )
    _ = model.refresh(
      day: day,
      habits: [habit],
      context: refreshContext(createdAt.addingTimeInterval(60))
    )
    #expect(model.rows.first?.progressText == "1 of 2 pages")

    try logging.delete(
      entry,
      from: habit,
      at: createdAt.addingTimeInterval(120),
      timeZone: zone
    )
    _ = model.refresh(
      day: day,
      habits: [habit],
      context: refreshContext(createdAt.addingTimeInterval(120))
    )
    #expect(model.rows.first?.progressText == "0 of 2 pages")

    try lifecycle.deactivate(
      habit,
      at: createdAt.addingTimeInterval(180),
      timeZone: zone
    )
    _ = model.refresh(
      day: day,
      habits: [habit],
      context: refreshContext(createdAt.addingTimeInterval(180))
    )
    #expect(model.rows.first?.stateText == "Exempt")

    try lifecycle.reactivate(
      habit,
      at: createdAt.addingTimeInterval(240),
      timeZone: zone
    )
    _ = model.refresh(
      day: day,
      habits: [habit],
      context: refreshContext(createdAt.addingTimeInterval(240))
    )
    #expect(model.rows.first?.stateText == "Open")
    #expect(JournalBytes(prose) == proseBytes)
  }

  private struct JournalBytes: Equatable {
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

  @MainActor
  private final class GardenProjectionProbe {
    struct Call {
      let day: LocalDate
      let instant: Date
      let timeZone: TimeZone
    }

    private var results: [[JournalDayGardenRow]]
    private(set) var calls: [Call] = []

    init(results: [[JournalDayGardenRow]]) {
      self.results = results
    }

    var operations: JournalDayGardenOperations {
      JournalDayGardenOperations { [self] _, day, instant, timeZone in
        calls.append(Call(day: day, instant: instant, timeZone: timeZone))
        let index = min(calls.count - 1, results.count - 1)
        return results[index]
      }
    }
  }

  private func row(
    _ id: Int,
    _ name: String,
    _ state: JournalDayGardenState,
    _ start: Date,
    _ end: Date,
    progress: Int? = nil,
    target: Int? = nil,
    unit: String? = nil,
    met: Bool? = nil
  ) -> JournalDayGardenRow {
    JournalDayGardenRow(
      habitID: uuid(id),
      name: name,
      cadence: .daily,
      periodKey: "day:2026-08-05",
      periodStart: start,
      periodEnd: end,
      state: state,
      progress: progress,
      target: target,
      unit: unit,
      isRequirementMet: met
    )
  }

  private func refreshContext(
    _ instant: Date,
    timeZone: String = "UTC",
    locale: String = "en_US"
  ) -> JournalDayGardenRefreshContext {
    JournalDayGardenRefreshContext(
      instant: instant,
      timeZone: TimeZone(identifier: timeZone)!,
      locale: Locale(identifier: locale)
    )
  }

  private func localDate(_ value: String) throws -> LocalDate {
    try LocalDate(validating: value)
  }

  private func instant(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return try #require(formatter.date(from: value))
  }

  private func timeZone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }

  private func uuid(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
  }
}
