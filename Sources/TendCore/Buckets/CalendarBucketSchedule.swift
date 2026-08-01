import Foundation

public struct CalendarBucketPeriod: Equatable, Sendable {
  public let cadence: HabitCadence
  public let key: String
  public let start: Date
  public let end: Date
  public let graceEnd: Date
}

public enum CalendarBucketScheduleError: Error, Equatable, Sendable {
  case unsupportedCadence(String)
  case malformedKey(String)
  case invalidDate(String)
  case invalidWeeklyStart(String)
  case unrepresentableDate
  case calendarCalculationFailed
}

public struct CalendarBucketSchedule: Sendable {
  public let timeZone: TimeZone

  public init(timeZone: TimeZone) {
    self.timeZone = timeZone
  }

  public func period(
    containing instant: Date,
    cadence: HabitCadence
  ) throws -> CalendarBucketPeriod {
    let calendar = calendar
    let start: Date

    switch cadence {
    case .daily:
      start = calendar.startOfDay(for: instant)
    case .weekly:
      let dayStart = calendar.startOfDay(for: instant)
      let weekday = calendar.component(.weekday, from: dayStart)
      let daysSinceMonday = (weekday - calendar.firstWeekday + 7) % 7
      guard
        let candidate = calendar.date(
          byAdding: .day,
          value: -daysSinceMonday,
          to: dayStart
        )
      else {
        throw CalendarBucketScheduleError.calendarCalculationFailed
      }
      start = calendar.startOfDay(for: candidate)
    }

    return try makePeriod(cadence: cadence, start: start, calendar: calendar)
  }

  public func period(
    containing instant: Date,
    cadenceRawValue: String
  ) throws -> CalendarBucketPeriod {
    guard let cadence = HabitCadence(rawValue: cadenceRawValue) else {
      throw CalendarBucketScheduleError.unsupportedCadence(cadenceRawValue)
    }
    return try period(containing: instant, cadence: cadence)
  }

  public func period(forKey key: String) throws -> CalendarBucketPeriod {
    let parsed = try parse(key: key)
    let calendar = calendar
    var components = DateComponents()
    components.timeZone = timeZone
    components.era = 1
    components.year = parsed.year
    components.month = parsed.month
    components.day = parsed.day

    guard let date = calendar.date(from: components) else {
      throw CalendarBucketScheduleError.invalidDate(key)
    }

    let start = calendar.startOfDay(for: date)
    let resolved = calendar.dateComponents([.era, .year, .month, .day], from: start)
    guard
      resolved.era == 1,
      resolved.year == parsed.year,
      resolved.month == parsed.month,
      resolved.day == parsed.day
    else {
      throw CalendarBucketScheduleError.invalidDate(key)
    }

    if parsed.cadence == .weekly,
      calendar.component(.weekday, from: start) != calendar.firstWeekday
    {
      throw CalendarBucketScheduleError.invalidWeeklyStart(key)
    }

    return try makePeriod(cadence: parsed.cadence, start: start, calendar: calendar)
  }

  public func next(after period: CalendarBucketPeriod) throws -> CalendarBucketPeriod {
    let current = try self.period(forKey: period.key)
    return try self.period(containing: current.end, cadence: current.cadence)
  }

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
  }

  private func makePeriod(
    cadence: HabitCadence,
    start: Date,
    calendar: Calendar
  ) throws -> CalendarBucketPeriod {
    let lengthInDays = cadence == .daily ? 1 : 7
    guard
      let endCandidate = calendar.date(
        byAdding: .day,
        value: lengthInDays,
        to: start
      )
    else {
      throw CalendarBucketScheduleError.calendarCalculationFailed
    }
    let end = calendar.startOfDay(for: endCandidate)
    guard let graceEndCandidate = calendar.date(byAdding: .day, value: 1, to: end)
    else {
      throw CalendarBucketScheduleError.calendarCalculationFailed
    }
    let graceEnd = calendar.startOfDay(for: graceEndCandidate)

    let components = calendar.dateComponents([.era, .year, .month, .day], from: start)
    guard
      let era = components.era,
      let year = components.year,
      let month = components.month,
      let day = components.day
    else {
      throw CalendarBucketScheduleError.calendarCalculationFailed
    }
    guard era == 1, (1...9_999).contains(year) else {
      throw CalendarBucketScheduleError.unrepresentableDate
    }

    let prefix = cadence == .daily ? "day" : "week"
    let key = String(
      format: "%@:%04d-%02d-%02d",
      locale: Locale(identifier: "en_US_POSIX"),
      prefix,
      year,
      month,
      day
    )
    return CalendarBucketPeriod(
      cadence: cadence,
      key: key,
      start: start,
      end: end,
      graceEnd: graceEnd
    )
  }

  private func parse(key: String) throws -> ParsedKey {
    let cadence: HabitCadence
    let prefixLength: Int
    if key.hasPrefix("day:") {
      cadence = .daily
      prefixLength = 4
    } else if key.hasPrefix("week:") {
      cadence = .weekly
      prefixLength = 5
    } else {
      throw CalendarBucketScheduleError.malformedKey(key)
    }

    let bytes = key.utf8
    guard bytes.count == prefixLength + 10 else {
      throw CalendarBucketScheduleError.malformedKey(key)
    }

    func byte(at dateOffset: Int) -> UInt8 {
      bytes[bytes.index(bytes.startIndex, offsetBy: prefixLength + dateOffset)]
    }
    let hyphen: UInt8 = 45
    let zero: UInt8 = 48
    let nine: UInt8 = 57

    for offset in 0..<10 {
      let value = byte(at: offset)
      if offset == 4 || offset == 7 {
        guard value == hyphen else {
          throw CalendarBucketScheduleError.malformedKey(key)
        }
      } else {
        guard (zero...nine).contains(value)
        else {
          throw CalendarBucketScheduleError.malformedKey(key)
        }
      }
    }

    func decimal(from lowerBound: Int, to upperBound: Int) -> Int {
      var result = 0
      for offset in lowerBound..<upperBound {
        result = result * 10 + Int(byte(at: offset) - zero)
      }
      return result
    }

    return ParsedKey(
      cadence: cadence,
      year: decimal(from: 0, to: 4),
      month: decimal(from: 5, to: 7),
      day: decimal(from: 8, to: 10)
    )
  }
}

private struct ParsedKey {
  let cadence: HabitCadence
  let year: Int
  let month: Int
  let day: Int
}
