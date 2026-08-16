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
    let targetDay = Self.dayIndex(year: year, month: month, day: day)
    let naiveMidnight = Date(
      timeIntervalSince1970: TimeInterval(targetDay) * Self.secondsPerDay
    )
    var earliestStart = Self.startCandidate(
      targetDay: targetDay,
      naiveMidnight: naiveMidnight,
      probeOffset: -3 * Self.secondsPerDay,
      timeZone: timeZone
    )
    if let candidate = Self.startCandidate(
      targetDay: targetDay,
      naiveMidnight: naiveMidnight,
      probeOffset: 0,
      timeZone: timeZone
    ) {
      earliestStart = earliestStart.map { min($0, candidate) } ?? candidate
    }
    if let candidate = Self.startCandidate(
      targetDay: targetDay,
      naiveMidnight: naiveMidnight,
      probeOffset: 3 * Self.secondsPerDay,
      timeZone: timeZone
    ) {
      earliestStart = earliestStart.map { min($0, candidate) } ?? candidate
    }

    guard let earliestStart else {
      throw GoalDateError.unrepresentableDate
    }
    return earliestStart
  }

  public func previous() throws -> Self {
    if day > 1 {
      return try adjacent(year: year, month: month, day: day - 1)
    }
    if month > 1 {
      let previousMonth = month - 1
      return try adjacent(
        year: year,
        month: previousMonth,
        day: Self.daysInMonth(year: year, month: previousMonth)!
      )
    }
    guard year > 1 else {
      throw GoalDateError.unrepresentableDate
    }
    return try adjacent(year: year - 1, month: 12, day: 31)
  }

  public func next() throws -> Self {
    let finalDay = Self.daysInMonth(year: year, month: month)!
    if day < finalDay {
      return try adjacent(year: year, month: month, day: day + 1)
    }
    if month < 12 {
      return try adjacent(year: year, month: month + 1, day: 1)
    }
    guard year < 9_999 else {
      throw GoalDateError.unrepresentableDate
    }
    return try adjacent(year: year + 1, month: 1, day: 1)
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

  private func adjacent(year: Int, month: Int, day: Int) throws -> Self {
    guard let date = Self(year: year, month: month, day: day) else {
      throw GoalDateError.calendarCalculationFailed
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
    guard
      (1...9_999).contains(year),
      let finalDay = daysInMonth(year: year, month: month)
    else {
      return false
    }
    return (1...finalDay).contains(day)
  }

  private static func daysInMonth(year: Int, month: Int) -> Int? {
    switch month {
    case 1, 3, 5, 7, 8, 10, 12:
      31
    case 4, 6, 9, 11:
      30
    case 2:
      isLeapYear(year) ? 29 : 28
    default:
      nil
    }
  }

  private static func isLeapYear(_ year: Int) -> Bool {
    year.isMultiple(of: 4)
      && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
  }

  private static let secondsPerDay: TimeInterval = 24 * 60 * 60

  private static func dayIndex(year: Int, month: Int, day: Int) -> Int {
    let adjustedYear = year - (month <= 2 ? 1 : 0)
    let era = adjustedYear / 400
    let yearOfEra = adjustedYear - era * 400
    let adjustedMonth = month + (month > 2 ? -3 : 9)
    let dayOfYear = (153 * adjustedMonth + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }

  private static func startCandidate(
    targetDay: Int,
    naiveMidnight: Date,
    probeOffset: TimeInterval,
    timeZone: TimeZone
  ) -> Date? {
    let probe = naiveMidnight.addingTimeInterval(probeOffset)
    let timeZoneOffset = timeZone.secondsFromGMT(for: probe)
    let candidate = naiveMidnight.addingTimeInterval(-TimeInterval(timeZoneOffset))
    guard
      localDayIndex(at: candidate, in: timeZone) == targetDay,
      localDayIndex(at: candidate.addingTimeInterval(-1), in: timeZone) != targetDay
    else {
      return nil
    }
    return candidate
  }

  private static func localDayIndex(at instant: Date, in timeZone: TimeZone) -> Int {
    let localSeconds = instant.timeIntervalSince1970
      + TimeInterval(timeZone.secondsFromGMT(for: instant))
    return Int((localSeconds / secondsPerDay).rounded(.down))
  }

}
