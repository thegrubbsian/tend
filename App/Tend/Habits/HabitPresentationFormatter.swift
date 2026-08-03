import Foundation
import TendCore

struct HabitPresentationFormatter {
    private let calendar: Calendar
    private let locale: Locale
    private let monthFormatter: DateFormatter
    private let dayFormatter: DateFormatter
    private let weekDayFormatter: DateFormatter
    private let timeFormatter: DateFormatter

    init(calendar: Calendar, locale: Locale, timeZone: TimeZone) {
        var calendar = calendar
        calendar.locale = locale
        calendar.timeZone = timeZone

        self.calendar = calendar
        self.locale = locale
        monthFormatter = Self.dateFormatter(
            template: "MMMM yyyy",
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        dayFormatter = Self.dateFormatter(
            template: "EEEE MMMM d yyyy",
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        weekDayFormatter = Self.dateFormatter(
            template: "MMM d yyyy",
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        timeFormatter = Self.dateFormatter(
            template: "jmm",
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
    }

    func requirement(target: Int, unit: String) -> String {
        let displayUnit = target == 1 && unit == "times"
            ? "time"
            : unit
        return amount(target, unit: displayUnit)
    }

    func cadence(_ cadence: HabitCadence?, fallback: String) -> String {
        switch cadence {
        case .daily:
            String(localized: "Daily", locale: locale)
        case .weekly:
            String(localized: "Weekly", locale: locale)
        case nil:
            fallback
        }
    }

    func pinnedDays(rawValue: Int) -> String? {
        guard let pinnedWeekdays = PinnedWeekdays(rawValue: rawValue) else {
            return nil
        }
        let labels = HabitFormWeekday.localizedLabels(calendar: calendar, locale: locale)
            .filter { pinnedWeekdays.contains($0.weekday.pinnedWeekday) }
            .map(\.abbreviated)
        return labels.isEmpty ? nil : labels.joined(separator: ", ")
    }

    func reminder(minuteOfDay: Int) -> String {
        precondition((0..<(24 * 60)).contains(minuteOfDay))
        let referenceDate = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        guard let date = calendar.date(
            byAdding: .minute,
            value: minuteOfDay,
            to: referenceDate
        ) else {
            preconditionFailure("Valid reminder minute could not be represented")
        }
        return "\(time(date)) \(String(localized: "reminder", locale: locale))"
    }

    func streak(value: Int, cadence: HabitCadence) -> String {
        "\(value.formatted(.number.locale(locale))) \(streakUnit(value: value, cadence: cadence))"
    }

    func streakUnit(value: Int, cadence: HabitCadence) -> String {
        switch cadence {
        case .daily:
            value == 1 ? "day" : "days"
        case .weekly:
            value == 1 ? "week" : "weeks"
        }
    }

    func month(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    func week(start: Date, endExclusive: Date) -> String {
        guard let end = calendar.date(byAdding: .day, value: -1, to: endExclusive) else {
            preconditionFailure("Exclusive week end could not be represented")
        }
        return "\(weekDayFormatter.string(from: start)) – \(weekDayFormatter.string(from: end))"
    }

    func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    func amount(_ amount: Int, unit: String) -> String {
        "\(amount.formatted(.number.locale(locale))) \(unit)"
    }

    private static func dateFormatter(
        template: String,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
