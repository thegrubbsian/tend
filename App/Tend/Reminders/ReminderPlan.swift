import Foundation
import TendCore

nonisolated struct ReminderCurrentBucketFacts: Equatable, Sendable {
  let periodKey: String
  let progress: Int
  let target: Int
  let unit: String
  let isMet: Bool
}

nonisolated struct ReminderHabitFacts: Equatable, Sendable {
  let id: UUID
  let name: String
  let cadenceRawValue: String
  let target: Int
  let unit: String
  let pinnedWeekdaysRawValue: Int
  let reminderMinuteOfDay: Int?
  let isActive: Bool
  let currentBucket: ReminderCurrentBucketFacts
}

nonisolated struct ReminderOccurrence: Equatable, Sendable {
  let identifier: String
  let habitID: UUID
  let fireDate: Date
  let dateComponents: DateComponents
  let bucketPeriodKey: String
  let title: String
  let body: String
}

nonisolated struct ReminderPlanner {
  private static let maximumRequestCount = 64
  static let identifierPrefix = "tend.reminder."

  private let calendar: Calendar
  private let timeZone: TimeZone
  private let formatter: ReminderContentFormatter

  init(calendar: Calendar, timeZone: TimeZone, locale: Locale) {
    var calendar = calendar
    calendar.locale = locale
    calendar.timeZone = timeZone
    self.calendar = calendar
    self.timeZone = timeZone
    formatter = ReminderContentFormatter(locale: locale)
  }

  func plan(
    habits: [ReminderHabitFacts],
    at instant: Date,
    limit: Int = 64
  ) -> [ReminderOccurrence] {
    guard limit > 0 else { return [] }
    let capacity = min(limit, Self.maximumRequestCount)

    var reservations: [ReminderCandidate] = []
    reservations.reserveCapacity(min(habits.count, capacity))
    for habit in habits {
      guard
        let facts = validated(habit, at: instant),
        let occurrence = nextOccurrence(for: facts, after: instant)
      else {
        continue
      }
      reservations.append(ReminderCandidate(facts: facts, occurrence: occurrence))
    }
    reservations.sort(by: ReminderCandidate.isOrdered)
    if capacity <= reservations.count {
      return reservations.prefix(capacity).map(\.occurrence)
    }

    var selected = reservations.map(\.occurrence)
    selected.reserveCapacity(capacity)
    var candidates = reservations.compactMap { reservation -> ReminderCandidate? in
      guard
        let occurrence = nextOccurrence(
          for: reservation.facts,
          after: reservation.occurrence.fireDate
        )
      else {
        return nil
      }
      return ReminderCandidate(facts: reservation.facts, occurrence: occurrence)
    }
    while selected.count < capacity, !candidates.isEmpty {
      guard
        let earliestIndex = candidates.indices.min(by: {
          ReminderCandidate.isOrdered(candidates[$0], candidates[$1])
        })
      else {
        break
      }
      let earliest = candidates.remove(at: earliestIndex)
      selected.append(earliest.occurrence)
      if let following = nextOccurrence(
        for: earliest.facts,
        after: earliest.occurrence.fireDate
      ) {
        candidates.append(
          ReminderCandidate(facts: earliest.facts, occurrence: following)
        )
      }
    }
    return selected.sorted(by: ReminderOccurrence.isOrdered)
  }

  private func validated(
    _ habit: ReminderHabitFacts,
    at instant: Date
  ) -> ValidatedHabit? {
    guard
      habit.isActive,
      !habit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let cadence = HabitCadence(rawValue: habit.cadenceRawValue),
      habit.target > 0,
      !habit.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let pinnedWeekdays = PinnedWeekdays(rawValue: habit.pinnedWeekdaysRawValue),
      cadence == .daily || pinnedWeekdays.rawValue != 0,
      let reminderMinuteOfDay = habit.reminderMinuteOfDay,
      let reminderTime = ReminderTime(rawValue: reminderMinuteOfDay),
      habit.currentBucket.progress >= 0,
      habit.currentBucket.target > 0,
      !habit.currentBucket.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      habit.currentBucket.isMet == (habit.currentBucket.progress >= habit.currentBucket.target),
      let currentPeriod = try? CalendarBucketSchedule(timeZone: timeZone).period(
        containing: instant,
        cadence: cadence
      ),
      currentPeriod.key == habit.currentBucket.periodKey
    else {
      return nil
    }
    return ValidatedHabit(
      habit: habit,
      cadence: cadence,
      pinnedWeekdays: pinnedWeekdays,
      reminderTime: reminderTime
    )
  }

  private func nextOccurrence(
    for facts: ValidatedHabit,
    after instant: Date
  ) -> ReminderOccurrence? {
    var cursor = instant
    while let fireDate = nextFireDate(for: facts, after: cursor) {
      guard fireDate > cursor else { return nil }
      cursor = fireDate
      guard let occurrence = occurrence(for: facts, at: fireDate) else {
        return nil
      }
      if occurrence.bucketPeriodKey == facts.habit.currentBucket.periodKey,
        facts.habit.currentBucket.isMet
      {
        continue
      }
      return occurrence
    }
    return nil
  }

  private func nextFireDate(
    for facts: ValidatedHabit,
    after instant: Date
  ) -> Date? {
    switch facts.cadence {
    case .daily:
      return calendar.nextDate(
        after: instant,
        matching: DateComponents(
          hour: facts.reminderTime.hour,
          minute: facts.reminderTime.minute
        ),
        matchingPolicy: .nextTime,
        repeatedTimePolicy: .first,
        direction: .forward
      )
    case .weekly:
      var earliest: Date?
      for (pinnedWeekday, calendarWeekday) in Self.calendarWeekdays
      where facts.pinnedWeekdays.contains(pinnedWeekday) {
        guard
          let candidate = calendar.nextDate(
            after: instant,
            matching: DateComponents(
              hour: facts.reminderTime.hour,
              minute: facts.reminderTime.minute,
              weekday: calendarWeekday
            ),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
          )
        else {
          continue
        }
        if let currentEarliest = earliest {
          earliest = min(currentEarliest, candidate)
        } else {
          earliest = candidate
        }
      }
      return earliest
    }
  }

  private static let calendarWeekdays: [(PinnedWeekdays, Int)] = [
    (.sunday, 1),
    (.monday, 2),
    (.tuesday, 3),
    (.wednesday, 4),
    (.thursday, 5),
    (.friday, 6),
    (.saturday, 7),
  ]

  private func occurrence(
    for facts: ValidatedHabit,
    at fireDate: Date
  ) -> ReminderOccurrence? {
    guard
      let period = try? CalendarBucketSchedule(timeZone: timeZone).period(
        containing: fireDate,
        cadence: facts.cadence
      )
    else {
      return nil
    }
    let local = calendar.dateComponents(
      [.era, .year, .month, .day, .hour, .minute],
      from: fireDate
    )
    guard
      let era = local.era,
      let year = local.year,
      let month = local.month,
      let day = local.day,
      let hour = local.hour,
      let minute = local.minute
    else {
      return nil
    }
    let isLeapMonth = local.isLeapMonth ?? false
    let isCurrent = period.key == facts.habit.currentBucket.periodKey
    let amount =
      isCurrent
      ? max(facts.habit.currentBucket.target - facts.habit.currentBucket.progress, 0)
      : facts.habit.target
    let unit = isCurrent ? facts.habit.currentBucket.unit : facts.habit.unit
    var dateComponents = local
    dateComponents.calendar = calendar
    dateComponents.timeZone = timeZone
    dateComponents.isLeapMonth = isLeapMonth
    return ReminderOccurrence(
      identifier: identifier(
        habitID: facts.habit.id,
        era: era,
        year: year,
        month: month,
        day: day,
        isLeapMonth: isLeapMonth
      ),
      habitID: facts.habit.id,
      fireDate: fireDate,
      dateComponents: dateComponents,
      bucketPeriodKey: period.key,
      title: facts.habit.name,
      body: formatter.body(
        amount: amount,
        unit: unit,
        cadence: facts.cadence
      )
    )
  }

  private func identifier(
    habitID: UUID,
    era: Int,
    year: Int,
    month: Int,
    day: Int,
    isLeapMonth: Bool
  ) -> String {
    let localDay = String(
      format: "%d-%04d-%02d-%02d-%d",
      locale: Locale(identifier: "en_US_POSIX"),
      era,
      year,
      month,
      day,
      isLeapMonth ? 1 : 0
    )
    return "\(Self.identifierPrefix)\(habitID.uuidString.lowercased()).\(localDay)"
  }
}

private nonisolated struct ReminderContentFormatter {
  let locale: Locale

  func requirement(target: Int, unit: String) -> String {
    let displayUnit = target == 1 && unit == "times" ? "time" : unit
    return "\(target.formatted(.number.locale(locale))) \(displayUnit)"
  }

  func body(amount: Int, unit: String, cadence: HabitCadence) -> String {
    let requirement = requirement(target: amount, unit: unit)
    switch cadence {
    case .daily:
      return String(localized: "\(requirement) left today.", locale: locale)
    case .weekly:
      return String(localized: "\(requirement) left this week.", locale: locale)
    }
  }
}

private nonisolated struct ValidatedHabit {
  let habit: ReminderHabitFacts
  let cadence: HabitCadence
  let pinnedWeekdays: PinnedWeekdays
  let reminderTime: ReminderTime
}

private nonisolated struct ReminderCandidate {
  let facts: ValidatedHabit
  let occurrence: ReminderOccurrence

  static func isOrdered(_ lhs: Self, _ rhs: Self) -> Bool {
    ReminderOccurrence.isOrdered(lhs.occurrence, rhs.occurrence)
  }
}
nonisolated

  extension ReminderOccurrence
{
  fileprivate static func isOrdered(_ lhs: Self, _ rhs: Self) -> Bool {
    if lhs.fireDate != rhs.fireDate {
      return lhs.fireDate < rhs.fireDate
    }
    return lhs.habitID.uuidString < rhs.habitID.uuidString
  }
}
