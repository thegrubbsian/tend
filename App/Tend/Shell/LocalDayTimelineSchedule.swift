import SwiftUI

nonisolated struct LocalDayTimelineSchedule: TimelineSchedule {
  let calendar: Calendar

  func entries(from startDate: Date, mode: Mode) -> Entries {
    Entries(nextDate: startDate, calendar: calendar)
  }

  nonisolated struct Entries: Sequence, IteratorProtocol {
    private var nextDate: Date?
    private let calendar: Calendar

    fileprivate init(nextDate: Date, calendar: Calendar) {
      self.nextDate = nextDate
      self.calendar = calendar
    }

    mutating func next() -> Date? {
      guard let date = nextDate else {
        return nil
      }

      nextDate = calendar.date(
        byAdding: .day,
        value: 1,
        to: calendar.startOfDay(for: date)
      )
      return date
    }
  }
}
