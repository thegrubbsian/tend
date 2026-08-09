import Foundation
import Testing
import TendCore

@testable import Tend

@Suite("Reminder plan")
struct ReminderPlanTests {
  @Test("daily plan begins with the next future local occasion")
  func dailyPlanBeginsWithNextFutureLocalOccasion() throws {
    let context = try TestContext(timeZoneIdentifier: "America/Los_Angeles")
    let now = try context.date(2026, 1, 5, 8, 0)
    let today = try context.date(2026, 1, 5, 9, 0)
    let tomorrow = try context.date(2026, 1, 6, 9, 0)
    let habitID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let habit = ReminderHabitFacts(
      id: habitID,
      name: "Meditation",
      cadenceRawValue: HabitCadence.daily.rawValue,
      target: 3,
      unit: "times",
      pinnedWeekdaysRawValue: PinnedWeekdays.none.rawValue,
      reminderMinuteOfDay: 9 * 60,
      isActive: true,
      currentBucket: ReminderCurrentBucketFacts(
        periodKey: "day:2026-01-05",
        progress: 1,
        target: 3,
        unit: "times",
        isMet: false
      )
    )

    let occurrences = ReminderPlanner(
      calendar: context.calendar,
      timeZone: context.timeZone,
      locale: Locale(identifier: "en_US")
    ).plan(habits: [habit], at: now, limit: 2)

    #expect(occurrences.map(\.fireDate) == [today, tomorrow])
    #expect(occurrences.map(\.title) == ["Meditation", "Meditation"])
    #expect(occurrences.map(\.body) == ["2 times left today.", "3 times left today."])
    #expect(occurrences.map(\.bucketPeriodKey) == ["day:2026-01-05", "day:2026-01-06"])
    #expect(occurrences[0].dateComponents.hour == 9)
    #expect(occurrences[0].dateComponents.minute == 0)
  }

  @Test("weekly plan follows pinned weekdays and suppresses the met current week")
  func weeklyPlanFollowsPinsAndSuppressesMetCurrentWeek() throws {
    let context = try TestContext(timeZoneIdentifier: "America/Los_Angeles")
    let now = try context.date(2026, 1, 5, 8, 0)
    let pins = PinnedWeekdays.monday.rawValue | PinnedWeekdays.wednesday.rawValue
    let unmet = makeHabit(
      id: 1,
      name: "LinkedIn",
      cadence: .weekly,
      pinnedWeekdaysRawValue: pins,
      currentPeriodKey: "week:2026-01-05"
    )
    let met = makeHabit(
      id: 1,
      name: "LinkedIn",
      cadence: .weekly,
      pinnedWeekdaysRawValue: pins,
      currentPeriodKey: "week:2026-01-05",
      progress: 1,
      isMet: true
    )
    let planner = makePlanner(context)

    let unmetOccurrences = planner.plan(habits: [unmet], at: now, limit: 4)
    let metOccurrences = planner.plan(habits: [met], at: now, limit: 2)

    #expect(unmetOccurrences.map(\.fireDate) == [
      try context.date(2026, 1, 5, 9, 0),
      try context.date(2026, 1, 7, 9, 0),
      try context.date(2026, 1, 12, 9, 0),
      try context.date(2026, 1, 14, 9, 0),
    ])
    #expect(unmetOccurrences.map(\.body) == Array(repeating: "1 time left this week.", count: 4))
    #expect(metOccurrences.map(\.fireDate) == [
      try context.date(2026, 1, 12, 9, 0),
      try context.date(2026, 1, 14, 9, 0),
    ])
  }

  @Test("planner excludes invalid and unscheduled habit facts without dropping valid habits")
  func plannerExcludesInvalidFacts() throws {
    let context = try TestContext(timeZoneIdentifier: "America/Los_Angeles")
    let now = try context.date(2026, 1, 5, 8, 0)
    let valid = makeHabit(id: 1, currentPeriodKey: "day:2026-01-05")
    let invalid = [
      makeHabit(id: 2, currentPeriodKey: "day:2026-01-05", isActive: false),
      makeHabit(id: 3, reminderMinuteOfDay: nil, currentPeriodKey: "day:2026-01-05"),
      makeHabit(
        id: 4,
        cadence: .weekly,
        pinnedWeekdaysRawValue: PinnedWeekdays.none.rawValue,
        currentPeriodKey: "week:2026-01-05"
      ),
      makeHabit(id: 5, cadenceRawValue: "monthly", currentPeriodKey: "day:2026-01-05"),
      makeHabit(id: 6, target: 0, currentPeriodKey: "day:2026-01-05"),
      makeHabit(id: 7, unit: " ", currentPeriodKey: "day:2026-01-05"),
      makeHabit(id: 8, name: "\n", currentPeriodKey: "day:2026-01-05"),
      makeHabit(id: 9, pinnedWeekdaysRawValue: 1 << 7, currentPeriodKey: "day:2026-01-05"),
      makeHabit(id: 10, reminderMinuteOfDay: 24 * 60, currentPeriodKey: "day:2026-01-05"),
      makeHabit(id: 11, currentPeriodKey: "day:2026-01-04"),
      makeHabit(id: 12, currentPeriodKey: "day:2026-01-05", progress: 1, isMet: false),
    ]

    let occurrences = makePlanner(context).plan(
      habits: invalid + [valid],
      at: now,
      limit: 2
    )

    #expect(occurrences.map(\.habitID) == [valid.id, valid.id])
  }

  @Test("an occasion equal to now is skipped instead of delivered late")
  func equalOccasionIsSkipped() throws {
    let context = try TestContext(timeZoneIdentifier: "America/Los_Angeles")
    let now = try context.date(2026, 1, 5, 9, 0)
    let habit = makeHabit(id: 1, currentPeriodKey: "day:2026-01-05")

    let occurrence = try #require(
      makePlanner(context).plan(habits: [habit], at: now, limit: 1).first
    )
    let tomorrow = try context.date(2026, 1, 6, 9, 0)

    #expect(occurrence.fireDate == tomorrow)
  }

  @Test("capacity reserves each habit's next occasion before chronological fill")
  func capacityReservesNextOccasionsBeforeFill() throws {
    let context = try TestContext(timeZoneIdentifier: "America/Los_Angeles")
    let now = try context.date(2026, 1, 5, 8, 0)
    let habits = [
      makeHabit(id: 1, reminderMinuteOfDay: 9 * 60, currentPeriodKey: "day:2026-01-05"),
      makeHabit(id: 2, reminderMinuteOfDay: 10 * 60, currentPeriodKey: "day:2026-01-05"),
      makeHabit(
        id: 3,
        cadence: .weekly,
        pinnedWeekdaysRawValue: PinnedWeekdays.sunday.rawValue,
        reminderMinuteOfDay: 7 * 60,
        currentPeriodKey: "week:2026-01-05"
      ),
    ]
    let planner = makePlanner(context)

    let constrained = planner.plan(habits: habits, at: now, limit: 2)
    let fair = planner.plan(habits: habits, at: now, limit: 5)

    #expect(constrained.map(\.habitID) == [habits[0].id, habits[1].id])
    #expect(fair.map(\.fireDate) == [
      try context.date(2026, 1, 5, 9, 0),
      try context.date(2026, 1, 5, 10, 0),
      try context.date(2026, 1, 6, 9, 0),
      try context.date(2026, 1, 6, 10, 0),
      try context.date(2026, 1, 11, 7, 0),
    ])
    #expect(planner.plan(habits: habits, at: now, limit: 0).isEmpty)
  }

  @Test("plan stops at the exact platform request limit")
  func planStopsAtPlatformRequestLimit() throws {
    let context = try TestContext(timeZoneIdentifier: "America/Los_Angeles")
    let now = try context.date(2026, 1, 5, 8, 0)
    let habits = [
      makeHabit(id: 1, currentPeriodKey: "day:2026-01-05"),
      makeHabit(id: 2, reminderMinuteOfDay: 10 * 60, currentPeriodKey: "day:2026-01-05"),
    ]

    let occurrences = makePlanner(context).plan(habits: habits, at: now)

    #expect(occurrences.count == 64)
    #expect(Set(occurrences.map(\.identifier)).count == 64)
  }

  @Test("mutable reminder content and time do not change local occasion identity")
  func mutableContentDoesNotChangeIdentity() throws {
    let context = try TestContext(timeZoneIdentifier: "America/Los_Angeles")
    let now = try context.date(2026, 1, 5, 8, 0)
    let original = makeHabit(
      id: 1,
      name: "Read",
      target: 1,
      unit: "times",
      currentPeriodKey: "day:2026-01-05"
    )
    let edited = makeHabit(
      id: 1,
      name: "Read deeply",
      target: 30,
      unit: "min",
      reminderMinuteOfDay: 10 * 60,
      currentPeriodKey: "day:2026-01-05",
      currentTarget: 30,
      currentUnit: "min"
    )
    let planner = makePlanner(context)

    let originalOccurrence = try #require(
      planner.plan(habits: [original], at: now, limit: 1).first
    )
    let editedOccurrence = try #require(
      planner.plan(habits: [edited], at: now, limit: 1).first
    )

    #expect(originalOccurrence.identifier == editedOccurrence.identifier)
    #expect(originalOccurrence.fireDate != editedOccurrence.fireDate)
    #expect(originalOccurrence.title != editedOccurrence.title)
    #expect(originalOccurrence.body != editedOccurrence.body)
  }

  @Test("spring-forward gaps use the next valid local time")
  func springForwardGapUsesNextValidTime() throws {
    let context = try TestContext(timeZoneIdentifier: "America/New_York")
    let now = try context.date(2026, 3, 7, 12, 0)
    let habit = makeHabit(
      id: 1,
      reminderMinuteOfDay: 2 * 60 + 30,
      currentPeriodKey: "day:2026-03-07"
    )

    let occurrences = makePlanner(context).plan(habits: [habit], at: now, limit: 2)

    #expect(occurrences.map(\.fireDate) == [
      try context.date(2026, 3, 8, 3, 0),
      try context.date(2026, 3, 9, 2, 30),
    ])
  }

  @Test("fall-back folds choose the first repeated local time")
  func fallBackFoldChoosesFirstTime() throws {
    let context = try TestContext(timeZoneIdentifier: "America/New_York")
    let now = try context.date(2026, 10, 31, 12, 0)
    let habit = makeHabit(
      id: 1,
      reminderMinuteOfDay: 1 * 60 + 30,
      currentPeriodKey: "day:2026-10-31"
    )

    let occurrences = makePlanner(context).plan(habits: [habit], at: now, limit: 2)

    #expect(occurrences.map(\.fireDate) == [
      try context.date(2026, 11, 1, 1, 30),
      try context.date(2026, 11, 2, 1, 30),
    ])
    #expect(occurrences[0].dateComponents.timeZone == context.timeZone)
  }

  @Test("weekly buckets cross the year boundary without losing pinned days")
  func weeklyBucketsCrossYearBoundary() throws {
    let context = try TestContext(timeZoneIdentifier: "America/Los_Angeles")
    let now = try context.date(2026, 12, 31, 12, 0)
    let habit = makeHabit(
      id: 1,
      cadence: .weekly,
      pinnedWeekdaysRawValue: PinnedWeekdays.sunday.rawValue,
      currentPeriodKey: "week:2026-12-28"
    )

    let occurrences = makePlanner(context).plan(habits: [habit], at: now, limit: 2)

    #expect(occurrences.map(\.fireDate) == [
      try context.date(2027, 1, 3, 9, 0),
      try context.date(2027, 1, 10, 9, 0),
    ])
    #expect(occurrences.map(\.bucketPeriodKey) == [
      "week:2026-12-28",
      "week:2027-01-04",
    ])
  }

  @Test("different time zones retain the same local components")
  func timeZonesRetainLocalComponents() throws {
    let losAngeles = try TestContext(timeZoneIdentifier: "America/Los_Angeles")
    let tokyo = try TestContext(timeZoneIdentifier: "Asia/Tokyo")
    let habit = makeHabit(id: 1, currentPeriodKey: "day:2026-01-05")

    let laOccurrence = try #require(
      makePlanner(losAngeles).plan(
        habits: [habit],
        at: losAngeles.date(2026, 1, 5, 8, 0),
        limit: 1
      ).first
    )
    let tokyoOccurrence = try #require(
      makePlanner(tokyo).plan(
        habits: [habit],
        at: tokyo.date(2026, 1, 5, 8, 0),
        limit: 1
      ).first
    )

    #expect(laOccurrence.fireDate != tokyoOccurrence.fireDate)
    #expect(laOccurrence.identifier == tokyoOccurrence.identifier)
    #expect(laOccurrence.dateComponents.hour == tokyoOccurrence.dateComponents.hour)
    #expect(laOccurrence.dateComponents.minute == tokyoOccurrence.dateComponents.minute)
  }

  @Test("content formats singular counts and grouped quantities")
  func contentFormatsAmounts() throws {
    let context = try TestContext(timeZoneIdentifier: "America/Los_Angeles")
    let now = try context.date(2026, 1, 5, 8, 0)
    let habits = [
      makeHabit(id: 1, target: 1, unit: "times", currentPeriodKey: "day:2026-01-05"),
      makeHabit(
        id: 2,
        target: 3,
        unit: "times",
        currentPeriodKey: "day:2026-01-05",
        currentTarget: 3
      ),
      makeHabit(
        id: 3,
        target: 8_000,
        unit: "steps",
        currentPeriodKey: "day:2026-01-05",
        currentTarget: 8_000,
        currentUnit: "steps"
      ),
    ]

    let occurrences = makePlanner(context).plan(habits: habits, at: now, limit: 3)

    #expect(occurrences.map(\.body) == [
      "1 time left today.",
      "3 times left today.",
      "8,000 steps left today.",
    ])
  }

  @Test("release habits replan only met current-period occasions")
  func releaseHabitsReplanOnlyMetCurrentPeriods() throws {
    let context = try TestContext(timeZoneIdentifier: "America/Los_Angeles")
    let now = try context.date(2026, 1, 5, 7, 0)
    let planner = makePlanner(context)

    func releaseHabits(gardenMet: Bool, linkedInMet: Bool) -> [ReminderHabitFacts] {
      [
        makeHabit(
          id: 1,
          name: "Meditation",
          target: 10,
          unit: "min",
          reminderMinuteOfDay: 6 * 60 + 30,
          currentPeriodKey: "day:2026-01-05"
        ),
        makeHabit(
          id: 2,
          name: "Exercise",
          target: 8_000,
          unit: "steps",
          reminderMinuteOfDay: 17 * 60,
          currentPeriodKey: "day:2026-01-05"
        ),
        makeHabit(
          id: 3,
          name: "Piano",
          target: 30,
          unit: "min",
          reminderMinuteOfDay: 19 * 60 + 30,
          currentPeriodKey: "day:2026-01-05"
        ),
        makeHabit(
          id: 4,
          name: "Garden",
          reminderMinuteOfDay: 8 * 60,
          currentPeriodKey: "day:2026-01-05",
          progress: gardenMet ? 1 : 0,
          isMet: gardenMet
        ),
        makeHabit(
          id: 5,
          name: "LinkedIn",
          cadence: .weekly,
          pinnedWeekdaysRawValue: PinnedWeekdays.wednesday.rawValue,
          reminderMinuteOfDay: 9 * 60,
          currentPeriodKey: "week:2026-01-05",
          progress: linkedInMet ? 1 : 0,
          isMet: linkedInMet
        ),
      ]
    }

    func firstOccurrences(
      for habits: [ReminderHabitFacts]
    ) -> [UUID: ReminderOccurrence] {
      Dictionary(
        grouping: planner.plan(habits: habits, at: now),
        by: \.habitID
      ).compactMapValues(\.first)
    }

    let initial = firstOccurrences(
      for: releaseHabits(gardenMet: false, linkedInMet: false)
    )
    let replanned = firstOccurrences(
      for: releaseHabits(gardenMet: true, linkedInMet: true)
    )
    let identifiers = releaseHabits(gardenMet: false, linkedInMet: false).map(\.id)

    #expect(initial.count == 5)
    #expect(replanned.count == 5)
    for id in identifiers.prefix(3) {
      #expect(replanned[id]?.identifier == initial[id]?.identifier)
    }
    #expect(initial[identifiers[3]]?.bucketPeriodKey == "day:2026-01-05")
    #expect(replanned[identifiers[3]]?.bucketPeriodKey == "day:2026-01-06")
    #expect(initial[identifiers[4]]?.bucketPeriodKey == "week:2026-01-05")
    #expect(replanned[identifiers[4]]?.bucketPeriodKey == "week:2026-01-12")
  }
}

private func makePlanner(_ context: TestContext) -> ReminderPlanner {
  ReminderPlanner(
    calendar: context.calendar,
    timeZone: context.timeZone,
    locale: Locale(identifier: "en_US")
  )
}

private func makeHabit(
  id: Int,
  name: String = "Habit",
  cadence: HabitCadence = .daily,
  cadenceRawValue: String? = nil,
  target: Int = 1,
  unit: String = "times",
  pinnedWeekdaysRawValue: Int = PinnedWeekdays.none.rawValue,
  reminderMinuteOfDay: Int? = 9 * 60,
  currentPeriodKey: String,
  progress: Int = 0,
  isMet: Bool = false,
  isActive: Bool = true,
  currentTarget: Int? = nil,
  currentUnit: String? = nil
) -> ReminderHabitFacts {
  let identifier = String(
    format: "00000000-0000-0000-0000-%012d",
    locale: Locale(identifier: "en_US_POSIX"),
    id
  )
  return ReminderHabitFacts(
    id: UUID(uuidString: identifier)!,
    name: name,
    cadenceRawValue: cadenceRawValue ?? cadence.rawValue,
    target: target,
    unit: unit,
    pinnedWeekdaysRawValue: pinnedWeekdaysRawValue,
    reminderMinuteOfDay: reminderMinuteOfDay,
    isActive: isActive,
    currentBucket: ReminderCurrentBucketFacts(
      periodKey: currentPeriodKey,
      progress: progress,
      target: currentTarget ?? target,
      unit: currentUnit ?? unit,
      isMet: isMet
    )
  )
}

private struct TestContext {
  let calendar: Calendar
  let timeZone: TimeZone

  init(timeZoneIdentifier: String) throws {
    timeZone = try #require(TimeZone(identifier: timeZoneIdentifier))
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    calendar.firstWeekday = 2
    self.calendar = calendar
  }

  func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
    try #require(
      calendar.date(
        from: DateComponents(
          calendar: calendar,
          timeZone: timeZone,
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute
        )
      )
    )
  }
}
