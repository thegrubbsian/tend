import Foundation
import Testing

@testable import TendCore

@Suite("Calendar bucket schedule")
struct CalendarBucketScheduleTests {
  @Test("daily periods use local half-open calendar days")
  func dailyPeriodsUseLocalHalfOpenCalendarDays() throws {
    let schedule = CalendarBucketSchedule(timeZone: try timeZone("UTC"))

    let leapDay = try schedule.period(
      containing: instant("2024-02-29T23:59:59Z"),
      cadence: .daily
    )
    #expect(leapDay.cadence == .daily)
    #expect(leapDay.key == "day:2024-02-29")
    #expect(leapDay.start == (try instant("2024-02-29T00:00:00Z")))
    #expect(leapDay.end == (try instant("2024-03-01T00:00:00Z")))
    #expect(leapDay.graceEnd == (try instant("2024-03-02T00:00:00Z")))

    let nextDay = try schedule.period(
      containing: leapDay.end,
      cadence: .daily
    )
    #expect(nextDay.key == "day:2024-03-01")
  }

  @Test("weekly periods run Monday through Sunday across year boundaries")
  func weeklyPeriodsRunMondayThroughSundayAcrossYearBoundaries() throws {
    let schedule = CalendarBucketSchedule(timeZone: try timeZone("UTC"))

    let period = try schedule.period(
      containing: instant("2025-01-05T23:59:59Z"),
      cadence: .weekly
    )
    #expect(period.cadence == .weekly)
    #expect(period.key == "week:2024-12-30")
    #expect(period.start == (try instant("2024-12-30T00:00:00Z")))
    #expect(period.end == (try instant("2025-01-06T00:00:00Z")))
    #expect(period.graceEnd == (try instant("2025-01-07T00:00:00Z")))

    let nextWeek = try schedule.period(
      containing: period.end,
      cadence: .weekly
    )
    #expect(nextWeek.key == "week:2025-01-06")
  }

  @Test("spring-forward days and grace use calendar-day boundaries")
  func springForwardDaysAndGraceUseCalendarDayBoundaries() throws {
    let schedule = CalendarBucketSchedule(
      timeZone: try timeZone("America/Los_Angeles")
    )

    let period = try schedule.period(
      containing: instant("2024-03-10T19:00:00Z"),
      cadence: .daily
    )
    #expect(period.key == "day:2024-03-10")
    #expect(period.start == (try instant("2024-03-10T08:00:00Z")))
    #expect(period.end == (try instant("2024-03-11T07:00:00Z")))
    #expect(period.graceEnd == (try instant("2024-03-12T07:00:00Z")))
    #expect(period.end.timeIntervalSince(period.start) == 23 * 60 * 60)

    let previous = try schedule.period(
      containing: instant("2024-03-09T19:00:00Z"),
      cadence: .daily
    )
    #expect(previous.start == (try instant("2024-03-09T08:00:00Z")))
    #expect(previous.end == (try instant("2024-03-10T08:00:00Z")))
    #expect(previous.graceEnd == (try instant("2024-03-11T07:00:00Z")))
    #expect(previous.graceEnd.timeIntervalSince(previous.end) == 23 * 60 * 60)
  }

  @Test("fall-back days and grace use calendar-day boundaries")
  func fallBackDaysAndGraceUseCalendarDayBoundaries() throws {
    let schedule = CalendarBucketSchedule(
      timeZone: try timeZone("America/Los_Angeles")
    )

    let period = try schedule.period(
      containing: instant("2024-11-03T20:00:00Z"),
      cadence: .daily
    )
    #expect(period.key == "day:2024-11-03")
    #expect(period.start == (try instant("2024-11-03T07:00:00Z")))
    #expect(period.end == (try instant("2024-11-04T08:00:00Z")))
    #expect(period.graceEnd == (try instant("2024-11-05T08:00:00Z")))
    #expect(period.end.timeIntervalSince(period.start) == 25 * 60 * 60)

    let previous = try schedule.period(
      containing: instant("2024-11-02T19:00:00Z"),
      cadence: .daily
    )
    #expect(previous.start == (try instant("2024-11-02T07:00:00Z")))
    #expect(previous.end == (try instant("2024-11-03T07:00:00Z")))
    #expect(previous.graceEnd == (try instant("2024-11-04T08:00:00Z")))
    #expect(previous.graceEnd.timeIntervalSince(previous.end) == 25 * 60 * 60)
  }

  @Test("weekly boundaries use calendar days across daylight saving changes")
  func weeklyBoundariesUseCalendarDaysAcrossDaylightSavingChanges() throws {
    let schedule = CalendarBucketSchedule(
      timeZone: try timeZone("America/Los_Angeles")
    )

    let spring = try schedule.period(
      containing: instant("2024-03-06T20:00:00Z"),
      cadence: .weekly
    )
    #expect(spring.key == "week:2024-03-04")
    #expect(spring.start == (try instant("2024-03-04T08:00:00Z")))
    #expect(spring.end == (try instant("2024-03-11T07:00:00Z")))
    #expect(spring.graceEnd == (try instant("2024-03-12T07:00:00Z")))
    #expect(spring.end.timeIntervalSince(spring.start) == 167 * 60 * 60)

    let fall = try schedule.period(
      containing: instant("2024-10-30T19:00:00Z"),
      cadence: .weekly
    )
    #expect(fall.key == "week:2024-10-28")
    #expect(fall.start == (try instant("2024-10-28T07:00:00Z")))
    #expect(fall.end == (try instant("2024-11-04T08:00:00Z")))
    #expect(fall.graceEnd == (try instant("2024-11-05T08:00:00Z")))
    #expect(fall.end.timeIntervalSince(fall.start) == 169 * 60 * 60)
  }

  @Test("periods remain contiguous when a local date has no midnight")
  func periodsRemainContiguousWhenLocalDateHasNoMidnight() throws {
    let schedule = CalendarBucketSchedule(
      timeZone: try timeZone("America/Sao_Paulo")
    )

    let period = try schedule.period(
      containing: instant("2018-11-04T15:00:00Z"),
      cadence: .daily
    )
    #expect(period.key == "day:2018-11-04")
    #expect(period.start == (try instant("2018-11-04T03:00:00Z")))
    #expect(period.end == (try instant("2018-11-05T02:00:00Z")))
    #expect(period.graceEnd == (try instant("2018-11-06T02:00:00Z")))

    let next = try schedule.period(
      containing: period.end,
      cadence: .daily
    )
    #expect(next.start == period.end)
  }

  @Test("persisted keys keep identity while time zones recalculate boundaries")
  func persistedKeysKeepIdentityWhileTimeZonesRecalculateBoundaries() throws {
    let losAngeles = CalendarBucketSchedule(
      timeZone: try timeZone("America/Los_Angeles")
    )
    let newYork = CalendarBucketSchedule(
      timeZone: try timeZone("America/New_York")
    )

    let west = try losAngeles.period(forKey: "day:2024-03-10")
    let east = try newYork.period(forKey: "day:2024-03-10")

    #expect(west.key == east.key)
    #expect(west.start == (try instant("2024-03-10T08:00:00Z")))
    #expect(east.start == (try instant("2024-03-10T05:00:00Z")))
    #expect(west.end == (try instant("2024-03-11T07:00:00Z")))
    #expect(east.end == (try instant("2024-03-11T04:00:00Z")))
  }

  @Test("advancing periods crosses the year without gaps")
  func advancingPeriodsCrossesTheYearWithoutGaps() throws {
    let schedule = CalendarBucketSchedule(timeZone: try timeZone("UTC"))

    let daily = try schedule.period(forKey: "day:2024-12-31")
    let nextDaily = try schedule.next(after: daily)
    #expect(nextDaily.key == "day:2025-01-01")
    #expect(nextDaily.start == daily.end)

    let weekly = try schedule.period(forKey: "week:2024-12-30")
    let nextWeekly = try schedule.next(after: weekly)
    #expect(nextWeekly.key == "week:2025-01-06")
    #expect(nextWeekly.start == weekly.end)
  }

  @Test("generated keys reject dates outside the four-digit common era")
  func generatedKeysRejectDatesOutsideTheFourDigitCommonEra() throws {
    let schedule = CalendarBucketSchedule(timeZone: try timeZone("UTC"))

    try expectError(.unrepresentableDate) {
      _ = try schedule.period(
        containing: gregorianDate(era: 0, year: 1),
        cadence: .daily
      )
    }
    try expectError(.unrepresentableDate) {
      _ = try schedule.period(
        containing: gregorianDate(era: 1, year: 10_000),
        cadence: .daily
      )
    }
  }

  @Test("strict keys reject malformed impossible and non-Monday dates")
  func strictKeysRejectMalformedImpossibleAndNonMondayDates() throws {
    let schedule = CalendarBucketSchedule(timeZone: try timeZone("UTC"))

    try expectError(.malformedKey("day:2024-2-01")) {
      _ = try schedule.period(forKey: "day:2024-2-01")
    }
    try expectError(.invalidDate("day:2024-02-30")) {
      _ = try schedule.period(forKey: "day:2024-02-30")
    }
    try expectError(.invalidWeeklyStart("week:2024-01-02")) {
      _ = try schedule.period(forKey: "week:2024-01-02")
    }
    try expectError(.malformedKey("month:2024-01-01")) {
      _ = try schedule.period(forKey: "month:2024-01-01")
    }
  }

  @Test("raw cadence rejects unsupported persisted values")
  func rawCadenceRejectsUnsupportedPersistedValues() throws {
    let schedule = CalendarBucketSchedule(timeZone: try timeZone("UTC"))

    try expectError(.unsupportedCadence("monthly")) {
      _ = try schedule.period(
        containing: instant("2024-01-01T12:00:00Z"),
        cadenceRawValue: "monthly"
      )
    }
  }

  private func expectError(
    _ expected: CalendarBucketScheduleError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected CalendarBucketScheduleError: \(expected)")
    } catch let error as CalendarBucketScheduleError {
      #expect(error == expected)
    }
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private func gregorianDate(era: Int, year: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try timeZone("UTC")
    var components = DateComponents()
    components.era = era
    components.year = year
    components.month = 1
    components.day = 1
    components.hour = 12
    return try #require(calendar.date(from: components))
  }

  private func timeZone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }
}
