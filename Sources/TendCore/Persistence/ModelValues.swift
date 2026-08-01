public enum HabitCadence: String, Codable, CaseIterable, Sendable {
  case daily
  case weekly
}

public enum BucketVerdict: String, Codable, CaseIterable, Sendable {
  case met
  case missed
}

public struct PinnedWeekdays: RawRepresentable, Codable, Hashable, Sendable {
  public static let none = Self(uncheckedRawValue: 0)
  public static let monday = Self(uncheckedRawValue: 1 << 0)
  public static let tuesday = Self(uncheckedRawValue: 1 << 1)
  public static let wednesday = Self(uncheckedRawValue: 1 << 2)
  public static let thursday = Self(uncheckedRawValue: 1 << 3)
  public static let friday = Self(uncheckedRawValue: 1 << 4)
  public static let saturday = Self(uncheckedRawValue: 1 << 5)
  public static let sunday = Self(uncheckedRawValue: 1 << 6)

  private static let supportedMask = 0b111_1111

  public let rawValue: Int

  public init?(rawValue: Int) {
    guard rawValue >= 0, rawValue & ~Self.supportedMask == 0 else {
      return nil
    }
    self.rawValue = rawValue
  }

  public func contains(_ weekday: Self) -> Bool {
    rawValue & weekday.rawValue == weekday.rawValue
  }

  private init(uncheckedRawValue: Int) {
    rawValue = uncheckedRawValue
  }
}

public struct ReminderTime: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: Int

  public init?(rawValue: Int) {
    guard (0..<24 * 60).contains(rawValue) else {
      return nil
    }
    self.rawValue = rawValue
  }

  public init?(hour: Int, minute: Int) {
    guard (0..<24).contains(hour), (0..<60).contains(minute) else {
      return nil
    }
    rawValue = hour * 60 + minute
  }

  public var hour: Int {
    rawValue / 60
  }

  public var minute: Int {
    rawValue % 60
  }
}
