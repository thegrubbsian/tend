import Foundation
import Testing

@testable import Tend

@Suite("Today date timeline")
struct LocalDayTimelineScheduleTests {
  @Test("timeline starts immediately then follows local midnights across daylight saving time")
  func timelineFollowsLocalMidnightsAcrossDaylightSavingTime() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))

    let start = try date(
      year: 2026,
      month: 3,
      day: 7,
      hour: 12,
      calendar: calendar
    )
    let firstMidnight = try date(
      year: 2026,
      month: 3,
      day: 8,
      hour: 0,
      calendar: calendar
    )
    let secondMidnight = try date(
      year: 2026,
      month: 3,
      day: 9,
      hour: 0,
      calendar: calendar
    )
    var entries = LocalDayTimelineSchedule(calendar: calendar)
      .entries(from: start, mode: .normal)
      .makeIterator()

    #expect(entries.next() == start)
    #expect(entries.next() == firstMidnight)
    #expect(entries.next() == secondMidnight)
    #expect(secondMidnight.timeIntervalSince(firstMidnight) == 23 * 60 * 60)
  }

  private func date(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    calendar: Calendar
  ) throws -> Date {
    try #require(
      calendar.date(
        from: DateComponents(
          calendar: calendar,
          timeZone: calendar.timeZone,
          year: year,
          month: month,
          day: day,
          hour: hour
        )
      )
    )
  }
}
