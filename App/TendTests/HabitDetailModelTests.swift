import Foundation
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Habit presentation formatter")
struct HabitDetailModelTests {
    @Test("owner facts preserve locale and owner-written units")
    func formatsOwnerFacts() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var fixedCalendar = Calendar(identifier: .gregorian)
        fixedCalendar.locale = Locale(identifier: "en_US")
        fixedCalendar.timeZone = utc
        let formatter = HabitPresentationFormatter(
            calendar: fixedCalendar,
            locale: Locale(identifier: "en_US"),
            timeZone: utc
        )
        let mondayAndWednesday = try #require(PinnedWeekdays(
            rawValue: PinnedWeekdays.monday.rawValue | PinnedWeekdays.wednesday.rawValue
        ))
        let instant = try #require(
            ISO8601DateFormatter().date(from: "2026-01-05T09:05:00Z")
        )
        let longOwnerUnit = "sets of calf raises completed before breakfast"

        #expect(formatter.requirement(target: 8_000, unit: "steps") == "8,000 steps")
        #expect(formatter.requirement(target: 1, unit: "times") == "1 time")
        #expect(formatter.requirement(target: 1, unit: "steps") == "1 steps")
        #expect(formatter.cadence(.weekly, fallback: "weekly") == "Weekly")
        #expect(formatter.cadence(nil, fallback: "owner cadence") == "owner cadence")
        #expect(formatter.pinnedDays(rawValue: mondayAndWednesday.rawValue) == "Mon, Wed")
        #expect(formatter.reminder(minuteOfDay: 9 * 60 + 5) == "9:05\u{202F}AM reminder")
        #expect(formatter.streak(value: 1, cadence: .daily) == "1 day")
        #expect(formatter.streak(value: 2, cadence: .weekly) == "2 weeks")
        #expect(formatter.streakUnit(value: 2, cadence: .daily) == "days")
        #expect(formatter.streakUnit(value: 1, cadence: .weekly) == "week")
        #expect(formatter.month(instant) == "January 2026")
        #expect(formatter.day(instant) == "Monday, January 5, 2026")
        #expect(formatter.time(instant) == "9:05\u{202F}AM")
        #expect(formatter.amount(12_345, unit: longOwnerUnit) == "12,345 \(longOwnerUnit)")
    }

    @Test("half-open weeks end on the preceding local day across year and DST boundaries")
    func formatsHalfOpenWeeks() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.locale = Locale(identifier: "en_US")
        utcCalendar.timeZone = utc
        let utcFormatter = HabitPresentationFormatter(
            calendar: utcCalendar,
            locale: Locale(identifier: "en_US"),
            timeZone: utc
        )
        let yearStart = try instant("2025-12-29T00:00:00Z")
        let yearEndExclusive = try instant("2026-01-05T00:00:00Z")

        #expect(
            utcFormatter.week(start: yearStart, endExclusive: yearEndExclusive)
                == "Dec 29, 2025 – Jan 4, 2026"
        )

        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.locale = Locale(identifier: "en_US")
        localCalendar.timeZone = losAngeles
        let localFormatter = HabitPresentationFormatter(
            calendar: localCalendar,
            locale: Locale(identifier: "en_US"),
            timeZone: losAngeles
        )
        let springForwardStart = try instant("2024-03-04T08:00:00Z")
        let springForwardEndExclusive = try instant("2024-03-11T07:00:00Z")

        #expect(
            localFormatter.week(
                start: springForwardStart,
                endExclusive: springForwardEndExclusive
            ) == "Mar 4, 2024 – Mar 10, 2024"
        )
    }

    private func instant(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
