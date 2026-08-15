import Foundation

public enum GoalDateError: Error, Equatable, Sendable {
  case malformedKey(String)
  case invalidDate(String)
  case unrepresentableDate
  case calendarCalculationFailed
}

public struct GoalDate: RawRepresentable, Equatable, Comparable, Codable, Sendable {
  public let year: Int
  public let month: Int
  public let day: Int

  public init?(year: Int, month: Int, day: Int) {
    guard Self.isValid(year: year, month: month, day: day) else {
      return nil
    }
    self.year = year
    self.month = month
    self.day = day
  }

  public init?(rawValue: String) {
    guard let value = try? Self(validating: rawValue) else {
      return nil
    }
    self = value
  }

  public init(validating rawValue: String) throws {
    let components = try Self.parse(rawValue)
    guard Self.isValid(
      year: components.year,
      month: components.month,
      day: components.day
    ) else {
      throw GoalDateError.invalidDate(rawValue)
    }
    year = components.year
    month = components.month
    day = components.day
  }

  public var rawValue: String {
    String(
      format: "%04d-%02d-%02d",
      locale: Locale(identifier: "en_US_POSIX"),
      year,
      month,
      day
    )
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.year != rhs.year {
      return lhs.year < rhs.year
    }
    if lhs.month != rhs.month {
      return lhs.month < rhs.month
    }
    return lhs.day < rhs.day
  }

  public func start(in timeZone: TimeZone) throws -> Date {
    let calendar = Self.calendar(timeZone: timeZone)
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = timeZone
    components.era = 1
    components.year = year
    components.month = month
    components.day = day

    guard let candidate = calendar.date(from: components) else {
      throw GoalDateError.calendarCalculationFailed
    }
    let start = calendar.startOfDay(for: candidate)
    let resolved = calendar.dateComponents([.era, .year, .month, .day], from: start)
    guard
      resolved.era == 1,
      resolved.year == year,
      resolved.month == month,
      resolved.day == day
    else {
      throw GoalDateError.unrepresentableDate
    }
    return start
  }

  public func previous() throws -> Self {
    try adding(days: -1)
  }

  public func next() throws -> Self {
    try adding(days: 1)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let key = try container.decode(String.self)
    do {
      try self.init(validating: key)
    } catch {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid GoalDate key: \(key)"
      )
    }
  }

  private func adding(days: Int) throws -> Self {
    let timeZone = TimeZone(secondsFromGMT: 0)!
    let calendar = Self.calendar(timeZone: timeZone)
    let start = try start(in: timeZone)
    guard let result = calendar.date(byAdding: .day, value: days, to: start) else {
      throw GoalDateError.calendarCalculationFailed
    }
    let components = calendar.dateComponents([.era, .year, .month, .day], from: result)
    guard
      components.era == 1,
      let year = components.year,
      let month = components.month,
      let day = components.day,
      let date = Self(year: year, month: month, day: day)
    else {
      throw GoalDateError.unrepresentableDate
    }
    return date
  }

  private static func parse(_ key: String) throws -> (year: Int, month: Int, day: Int) {
    let bytes = key.utf8
    guard bytes.count == 10 else {
      throw GoalDateError.malformedKey(key)
    }

    func byte(at offset: Int) -> UInt8 {
      bytes[bytes.index(bytes.startIndex, offsetBy: offset)]
    }
    let hyphen: UInt8 = 45
    let zero: UInt8 = 48
    let nine: UInt8 = 57
    for offset in 0..<10 {
      let value = byte(at: offset)
      if offset == 4 || offset == 7 {
        guard value == hyphen else {
          throw GoalDateError.malformedKey(key)
        }
      } else if !(zero...nine).contains(value) {
        throw GoalDateError.malformedKey(key)
      }
    }

    func decimal(from lowerBound: Int, to upperBound: Int) -> Int {
      var result = 0
      for offset in lowerBound..<upperBound {
        result = result * 10 + Int(byte(at: offset) - zero)
      }
      return result
    }
    return (
      year: decimal(from: 0, to: 4),
      month: decimal(from: 5, to: 7),
      day: decimal(from: 8, to: 10)
    )
  }

  private static func isValid(year: Int, month: Int, day: Int) -> Bool {
    guard (1...9_999).contains(year) else {
      return false
    }
    let timeZone = TimeZone(secondsFromGMT: 0)!
    let calendar = calendar(timeZone: timeZone)
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = timeZone
    components.era = 1
    components.year = year
    components.month = month
    components.day = day
    guard let date = calendar.date(from: components) else {
      return false
    }
    let resolved = calendar.dateComponents([.era, .year, .month, .day], from: date)
    return resolved.era == 1
      && resolved.year == year
      && resolved.month == month
      && resolved.day == day
  }

  private static func calendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    return calendar
  }
}
