import SwiftUI

nonisolated struct LocalDayTimelineSchedule: TimelineSchedule {
  let calendar: Calendar
  let earlierTransition: Date?

  init(calendar: Calendar, earlierTransition: Date? = nil) {
    self.calendar = calendar
    self.earlierTransition = earlierTransition
  }

  func entries(from startDate: Date, mode: Mode) -> Entries {
    Entries(
      nextDate: startDate,
      calendar: calendar,
      earlierTransition: earlierTransition.flatMap { $0 > startDate ? $0 : nil }
    )
  }

  nonisolated struct Entries: Sequence, IteratorProtocol {
    private var nextDate: Date?
    private let calendar: Calendar
    private var earlierTransition: Date?

    fileprivate init(
      nextDate: Date,
      calendar: Calendar,
      earlierTransition: Date?
    ) {
      self.nextDate = nextDate
      self.calendar = calendar
      self.earlierTransition = earlierTransition
    }

    mutating func next() -> Date? {
      guard let date = nextDate else { return nil }

      let nextMidnight = calendar.date(
        byAdding: .day,
        value: 1,
        to: calendar.startOfDay(for: date)
      )
      if let transition = earlierTransition {
        if transition <= date {
          earlierTransition = nil
          nextDate = nextMidnight
        } else if let nextMidnight, transition <= nextMidnight {
          earlierTransition = nil
          nextDate = transition
        } else {
          nextDate = nextMidnight
        }
      } else {
        nextDate = nextMidnight
      }
      return date
    }
  }
}
