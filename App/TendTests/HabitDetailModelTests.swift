import Foundation
import SwiftData
import Testing

@testable import Tend
@testable import TendCore

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
    let mondayAndWednesday = try #require(
      PinnedWeekdays(
        rawValue: PinnedWeekdays.monday.rawValue | PinnedWeekdays.wednesday.rawValue
      ))
    let instant = try #require(
      ISO8601DateFormatter().date(from: "2026-01-05T09:05:00Z")
    )
    let longOwnerUnit = "sets of calf raises completed before breakfast"

    #expect(formatter.requirement(target: 8_000, unit: "steps") == "8,000 steps")
    #expect(formatter.requirement(target: 1, unit: "times") == "1 time")
    #expect(formatter.requirement(target: 1, unit: "TIMES") == "1 TIMES")
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

  @Test("current streak risk copy does not assign a responsible period or state")
  func formatsGenericCurrentStreakRisk() throws {
    let utc = try #require(TimeZone(identifier: "UTC"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US")
    calendar.timeZone = utc
    let formatter = HabitPresentationFormatter(
      calendar: calendar,
      locale: Locale(identifier: "en_US"),
      timeZone: utc
    )

    let message = formatter.currentStreakRisk()

    #expect(message == "Current streak at risk")
    #expect(!message.contains("Yesterday"))
    #expect(!message.contains("Last week"))
    #expect(!message.contains("Open"))
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

  @Test("successful daily load atomically maps owner facts, history geometry, and entries")
  func mapsDailyDetailPresentation() throws {
    let fixture = try HabitDetailFixture()
    let longName = "Morning movement before the neighborhood wakes and the coffee finishes brewing"
    let longUnit = "sets of calf raises completed before breakfast"
    let habit = Habit(
      name: longName,
      cadence: .daily,
      target: 8_000,
      unit: longUnit,
      reminderTime: ReminderTime(rawValue: 9 * 60 + 5)
    )
    let january = try fixture.instant("2026-01-01T00:00:00Z")
    let firstEntryID = try #require(
      UUID(
        uuidString: "00000000-0000-0000-0000-000000000002"
      ))
    let secondEntryID = try #require(
      UUID(
        uuidString: "00000000-0000-0000-0000-000000000001"
      ))
    let history = try (1...31).map { day in
      try fixture.dailyPeriod(
        day: day,
        state: day == 6 ? .inactive : .future
      )
    }
    let entries = [
      HabitEditableEntry(
        id: firstEntryID,
        timestamp: try fixture.instant("2026-01-06T18:30:00Z"),
        amount: 12_345,
        bucketKey: "2026-01-06",
        unit: longUnit,
        bucketStart: try fixture.instant("2026-01-06T00:00:00Z"),
        bucketEnd: try fixture.instant("2026-01-07T00:00:00Z")
      ),
      HabitEditableEntry(
        id: secondEntryID,
        timestamp: try fixture.instant("2026-01-05T09:05:00Z"),
        amount: 7,
        bucketKey: "2026-01-05",
        unit: longUnit,
        bucketStart: try fixture.instant("2026-01-05T00:00:00Z"),
        bucketEnd: try fixture.instant("2026-01-06T00:00:00Z")
      ),
    ]
    let snapshot = fixture.snapshot(
      habitID: habit.id,
      cadence: .daily,
      selectedMonth: january,
      streak: HabitStreakState(
        currentStreak: 12_345,
        bestStreak: 987_654,
        isAtRisk: true,
        cadence: .daily
      ),
      history: history,
      editableEntries: entries
    )
    var receivedHabit: Habit?
    var receivedMonth: Date?
    var receivedInstant: Date?
    var receivedTimeZone: TimeZone?
    let model = fixture.model(
      habit: habit,
      operations: HabitDetailOperations(snapshot: { candidate, month, instant, timeZone in
        receivedHabit = candidate
        receivedMonth = month
        receivedInstant = instant
        receivedTimeZone = timeZone
        return snapshot
      })
    )

    model.start()

    let presentation = try #require(model.presentation)
    #expect(receivedHabit === habit)
    #expect(receivedMonth == january)
    #expect(receivedInstant == fixture.now)
    #expect(receivedTimeZone == fixture.timeZone)
    #expect(model.habitID == habit.id)
    #expect(model.habitName == longName)
    #expect(presentation.name == longName)
    #expect(presentation.requirementText == "8,000 \(longUnit)")
    #expect(presentation.cadenceText == "Daily")
    #expect(presentation.pinnedDaysText == nil)
    #expect(presentation.reminderText == "9:05\u{202F}AM reminder")
    #expect(
      presentation.metadataText
        == "8,000 \(longUnit) · Daily · 9:05\u{202F}AM reminder"
    )
    #expect(presentation.currentStreak == 12_345)
    #expect(presentation.currentStreakText == "12,345 days")
    #expect(presentation.currentStreakUnit == "days")
    #expect(presentation.bestStreak == 987_654)
    #expect(presentation.bestStreakText == "987,654 days")
    #expect(presentation.bestStreakUnit == "days")
    #expect(presentation.isAtRisk)
    #expect(presentation.currentStreakRiskText == "Current streak at risk")
    #expect(presentation.monthTitle == "January 2026")
    #expect(presentation.dailyLeadingFillerCount == 3)
    #expect(presentation.dailyTrailingFillerCount == 1)
    #expect(presentation.history.map(\.key) == history.map(\.key))
    #expect(presentation.history.first?.dateText == "Thursday, January 1, 2026")
    #expect(presentation.history.last?.dateText == "Saturday, January 31, 2026")
    let inactive = try #require(presentation.history.first { $0.key == "2026-01-06" })
    #expect(inactive.state == .inactive)
    #expect(inactive.progress == nil)
    #expect(inactive.target == nil)
    #expect(inactive.unit == nil)
    #expect(inactive.progressText == nil)
    #expect(inactive.calloutText == "Tuesday, January 6, 2026 · Inactive")
    #expect(presentation.entries.map(\.id) == [firstEntryID, secondEntryID])
    #expect(presentation.entries[0].scopeText == "Tuesday, January 6, 2026")
    #expect(presentation.entries[0].timeText == "6:30\u{202F}PM")
    #expect(presentation.entries[0].amountText == "12,345 \(longUnit)")
    #expect(
      presentation.entries[0].accessibilityLabel
        == "Tuesday, January 6, 2026, 6:30\u{202F}PM, 12,345 \(longUnit), Delete entry"
    )
  }

  @Test("weekly load preserves Monday-through-Sunday chronological ranges and pin metadata")
  func mapsWeeklyRangesChronologically() throws {
    let fixture = try HabitDetailFixture()
    let pins = try #require(
      PinnedWeekdays(
        rawValue: PinnedWeekdays.monday.rawValue | PinnedWeekdays.wednesday.rawValue
      ))
    let habit = Habit(
      name: "Share",
      cadence: .weekly,
      target: 2,
      unit: "posts",
      pinnedWeekdays: pins
    )
    let weeks = [
      HabitHistoryPeriod(
        key: "2025-W53",
        start: try fixture.instant("2025-12-29T00:00:00Z"),
        end: try fixture.instant("2026-01-05T00:00:00Z"),
        state: .met
      ),
      HabitHistoryPeriod(
        key: "2026-W02",
        start: try fixture.instant("2026-01-05T00:00:00Z"),
        end: try fixture.instant("2026-01-12T00:00:00Z"),
        state: .open,
        progress: 1,
        target: 2,
        unit: "posts",
        isRequirementMet: false
      ),
    ]
    let snapshot = fixture.snapshot(
      habitID: habit.id,
      cadence: .weekly,
      selectedMonth: try fixture.instant("2026-01-01T00:00:00Z"),
      streak: HabitStreakState(
        currentStreak: 1,
        bestStreak: 2,
        isAtRisk: false,
        cadence: .weekly
      ),
      history: weeks
    )
    let model = fixture.model(
      habit: habit,
      operations: HabitDetailOperations(snapshot: { _, _, _, _ in snapshot })
    )

    model.start()

    let presentation = try #require(model.presentation)
    #expect(presentation.pinnedDaysText == "Mon, Wed")
    #expect(presentation.metadataText == "2 posts · Weekly, Mon, Wed")
    #expect(presentation.currentStreakText == "1 week")
    #expect(presentation.currentStreakUnit == "week")
    #expect(presentation.bestStreakText == "2 weeks")
    #expect(presentation.bestStreakUnit == "weeks")
    #expect(presentation.currentStreakRiskText == nil)
    #expect(presentation.dailyLeadingFillerCount == 0)
    #expect(presentation.dailyTrailingFillerCount == 0)
    #expect(presentation.history.map(\.key) == ["2025-W53", "2026-W02"])
    #expect(
      presentation.history.map(\.dateText) == [
        "Dec 29, 2025 – Jan 4, 2026",
        "Jan 5, 2026 – Jan 11, 2026",
      ])
  }

  @Test("open and grace facts preserve met and unmet provisional standing")
  func preservesEveryProvisionalStanding() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 8, unit: "steps")
    let history = [
      HabitHistoryPeriod(
        key: "open-met",
        start: try fixture.instant("2026-01-05T00:00:00Z"),
        end: try fixture.instant("2026-01-06T00:00:00Z"),
        state: .open,
        progress: 8,
        target: 8,
        unit: "steps",
        isRequirementMet: true
      ),
      HabitHistoryPeriod(
        key: "open-unmet",
        start: try fixture.instant("2026-01-06T00:00:00Z"),
        end: try fixture.instant("2026-01-07T00:00:00Z"),
        state: .open,
        progress: 3,
        target: 8,
        unit: "steps",
        isRequirementMet: false
      ),
      HabitHistoryPeriod(
        key: "grace-met",
        start: try fixture.instant("2026-01-07T00:00:00Z"),
        end: try fixture.instant("2026-01-08T00:00:00Z"),
        state: .grace,
        progress: 9,
        target: 8,
        unit: "steps",
        isRequirementMet: true
      ),
      HabitHistoryPeriod(
        key: "grace-unmet",
        start: try fixture.instant("2026-01-08T00:00:00Z"),
        end: try fixture.instant("2026-01-09T00:00:00Z"),
        state: .grace,
        progress: 2,
        target: 8,
        unit: "steps",
        isRequirementMet: false
      ),
    ]
    let snapshot = fixture.snapshot(
      habitID: habit.id,
      cadence: .daily,
      selectedMonth: try fixture.instant("2026-01-01T00:00:00Z"),
      history: history
    )
    let model = fixture.model(
      habit: habit,
      operations: HabitDetailOperations(snapshot: { _, _, _, _ in snapshot })
    )

    model.start()

    let facts = try #require(model.presentation?.history)
    #expect(facts.map(\.isRequirementMet) == [true, false, true, false])
    #expect(facts.map(\.progress) == [8, 3, 9, 2])
    #expect(facts.map(\.target) == [8, 8, 8, 8])
    #expect(facts.map(\.unit) == ["steps", "steps", "steps", "steps"])
    #expect(
      facts.map(\.progressText) == [
        "8 of 8 steps",
        "3 of 8 steps",
        "9 of 8 steps",
        "2 of 8 steps",
      ])
    #expect(
      facts.map(\.calloutText) == [
        "Monday, January 5, 2026 · Open · Requirement met · 8 of 8 steps",
        "Tuesday, January 6, 2026 · Open · Requirement not met · 3 of 8 steps",
        "Wednesday, January 7, 2026 · Grace · Requirement met · 9 of 8 steps",
        "Thursday, January 8, 2026 · Grace · Requirement not met · 2 of 8 steps",
      ])
    #expect(
      facts.map(\.accessibilityLabel) == [
        "Monday, January 5, 2026, Open, requirement met, 8 of 8 steps",
        "Tuesday, January 6, 2026, Open, requirement not met, 3 of 8 steps",
        "Wednesday, January 7, 2026, Grace, requirement met, 9 of 8 steps",
        "Thursday, January 8, 2026, Grace, requirement not met, 2 of 8 steps",
      ])
  }

  @Test("failed first load retains captured owner identity and retries the same month")
  func retriesFailedFirstLoadWithoutLosingOwnerContext() throws {
    let fixture = try HabitDetailFixture()
    let longOwnerName = "A habit name long enough to remain the only trustworthy owner context"
    let habit = Habit(name: longOwnerName, cadence: .daily, target: 1)
    let january = try fixture.instant("2026-01-01T00:00:00Z")
    let success = fixture.snapshot(
      habitID: habit.id,
      cadence: .daily,
      selectedMonth: january
    )
    var requestedMonths: [Date] = []
    var shouldFail = true
    let model = fixture.model(
      habit: habit,
      operations: HabitDetailOperations(snapshot: { _, month, _, _ in
        requestedMonths.append(month)
        if shouldFail {
          throw HabitDetailTestError.unavailable
        }
        return success
      })
    )

    model.start()

    #expect(model.presentation == nil)
    #expect(model.selectedHistory == nil)
    #expect(model.loadFailure?.message == "This habit is unavailable right now.")
    #expect(model.loadFailure?.retryTitle == "Try again")
    #expect(model.habitID == habit.id)
    #expect(model.habitName == longOwnerName)
    #expect(model.selectedMonth == january)

    shouldFail = false
    habit.name = "Updated owner name"
    model.retryLoad()

    #expect(requestedMonths == [january, january])
    #expect(model.loadFailure == nil)
    #expect(model.presentation?.name == "Updated owner name")
    #expect(model.habitName == "Updated owner name")
  }

  @Test("month navigation uses injected calendar arithmetic and clamps at snapshot bounds")
  func navigatesWithinVerifiedMonthBounds() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let november = try fixture.instant("2025-11-01T00:00:00Z")
    let january = try fixture.instant("2026-01-01T00:00:00Z")
    let march = try fixture.instant("2026-03-01T00:00:00Z")
    var requestedMonths: [Date] = []
    let operations = HabitDetailOperations(snapshot: { _, month, _, _ in
      requestedMonths.append(month)
      return fixture.snapshot(
        habitID: habit.id,
        cadence: .daily,
        earliestMonth: november,
        selectedMonth: month,
        latestMonth: march
      )
    })
    let model = fixture.model(habit: habit, operations: operations)

    model.start()
    #expect(model.canSelectPreviousMonth)
    #expect(model.canSelectNextMonth)

    model.selectPreviousMonth()
    model.selectPreviousMonth()
    #expect(model.selectedMonth == november)
    #expect(!model.canSelectPreviousMonth)
    model.selectPreviousMonth()
    #expect(requestedMonths.count == 3)

    model.selectNextMonth()
    model.selectNextMonth()
    model.selectNextMonth()
    model.selectNextMonth()

    #expect(
      requestedMonths == [
        january,
        try fixture.instant("2025-12-01T00:00:00Z"),
        november,
        try fixture.instant("2025-12-01T00:00:00Z"),
        january,
        try fixture.instant("2026-02-01T00:00:00Z"),
        march,
      ])
    #expect(model.selectedMonth == march)
    #expect(!model.canSelectNextMonth)
  }

  @Test("history selection toggles, replaces, dismisses, and clears on navigation and stop")
  func managesHistoryCalloutState() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let january = try fixture.instant("2026-01-01T00:00:00Z")
    let history = [
      try fixture.dailyPeriod(day: 5, state: .met),
      try fixture.dailyPeriod(day: 6, state: .missed),
    ]
    let operations = HabitDetailOperations(snapshot: { _, month, _, _ in
      fixture.snapshot(
        habitID: habit.id,
        cadence: .daily,
        earliestMonth: january,
        selectedMonth: month,
        latestMonth: try fixture.instant("2026-02-01T00:00:00Z"),
        history: history
      )
    })
    let model = fixture.model(habit: habit, operations: operations)

    model.start()
    model.selectHistory("2026-01-05")
    #expect(model.selectedHistory?.key == "2026-01-05")
    model.selectHistory("2026-01-05")
    #expect(model.selectedHistory == nil)
    model.selectHistory("2026-01-05")
    model.selectHistory("2026-01-06")
    #expect(model.selectedHistory?.key == "2026-01-06")
    model.dismissHistoryCallout()
    #expect(model.selectedHistory == nil)
    model.selectHistory("missing")
    #expect(model.selectedHistory == nil)
    model.selectHistory("2026-01-05")
    model.selectNextMonth()
    #expect(model.selectedHistory == nil)
    model.selectHistory("2026-01-05")
    model.stop()
    #expect(model.selectedHistory == nil)
  }

  @Test("failed page replacement clears every derived value and retains its request for retry")
  func clearsStalePresentationAfterFailedPageLoad() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let january = try fixture.instant("2026-01-01T00:00:00Z")
    let february = try fixture.instant("2026-02-01T00:00:00Z")
    var failFebruary = true
    var requests: [Date] = []
    let operations = HabitDetailOperations(snapshot: { _, month, _, _ in
      requests.append(month)
      if month == february, failFebruary {
        throw HabitDetailTestError.unavailable
      }
      return fixture.snapshot(
        habitID: habit.id,
        cadence: .daily,
        earliestMonth: january,
        selectedMonth: month,
        latestMonth: february,
        history: [try fixture.dailyPeriod(day: 5, state: .met)]
      )
    })
    let model = fixture.model(habit: habit, operations: operations)

    model.start()
    model.selectHistory("2026-01-05")
    model.selectNextMonth()

    #expect(model.presentation == nil)
    #expect(model.selectedHistory == nil)
    #expect(model.loadFailure?.retryTitle == "Try again")
    #expect(model.selectedMonth == february)

    failFebruary = false
    model.retryLoad()

    #expect(requests == [january, february, february])
    #expect(model.presentation?.selectedMonth == february)
    #expect(model.loadFailure == nil)
  }

  @Test("refresh after persisted habit deletion never rereads detached owner state")
  func handlesDetachedHabitFailureSafely() throws {
    let fixture = try HabitDetailFixture()
    let container = try TendModelContainer.inMemory()
    let context = container.mainContext
    let management = HabitManagementOperations(context: context)
    let habit = try management.create(
      fields: HabitEditableFields(
        name: "Persisted owner name",
        target: 1,
        unit: "times"
      ),
      cadence: .daily,
      at: fixture.now,
      timeZone: fixture.timeZone
    )
    let capturedID = habit.id
    let capturedName = habit.name
    let success = fixture.snapshot(
      habitID: capturedID,
      cadence: .daily,
      selectedMonth: try fixture.instant("2026-01-01T00:00:00Z")
    )
    var attempt = 0
    let model = fixture.model(
      habit: habit,
      operations: HabitDetailOperations(snapshot: { _, _, _, _ in
        attempt += 1
        if attempt > 1 {
          throw HabitDetailTestError.unavailable
        }
        return success
      })
    )
    model.start()
    #expect(model.presentation != nil)
    context.delete(habit)
    try context.save()

    model.refresh()

    #expect(model.presentation == nil)
    #expect(model.selectedHistory == nil)
    #expect(model.habitID == capturedID)
    #expect(model.habitName == capturedName)
    #expect(model.loadFailure?.message == "This habit is unavailable right now.")
    #expect(model.loadFailure?.retryTitle == "Try again")
  }

  @Test("initial month and snapshot share one sampled dependency context")
  func initialLoadSamplesDependenciesOnce() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let firstInstant = try fixture.instant("2026-01-31T23:59:59Z")
    let secondInstant = try fixture.instant("2026-02-01T00:00:00Z")
    let january = try fixture.instant("2026-01-01T00:00:00Z")
    var nowValues = [firstInstant, secondInstant]
    var nowCalls = 0
    var timeZoneCalls = 0
    var calendarCalls = 0
    var localeCalls = 0
    var receivedMonth: Date?
    var receivedInstant: Date?
    let operations = HabitDetailOperations(snapshot: { _, month, instant, _ in
      receivedMonth = month
      receivedInstant = instant
      return fixture.snapshot(
        habitID: habit.id,
        cadence: .daily,
        selectedMonth: month
      )
    })
    let model = HabitDetailModel(
      habit: habit,
      operations: operations,
      now: {
        nowCalls += 1
        return nowValues.removeFirst()
      },
      timeZone: {
        timeZoneCalls += 1
        return fixture.timeZone
      },
      calendar: {
        calendarCalls += 1
        return fixture.calendar
      },
      locale: {
        localeCalls += 1
        return fixture.locale
      }
    )

    model.start()

    #expect(nowCalls == 1)
    #expect(timeZoneCalls == 1)
    #expect(calendarCalls == 1)
    #expect(localeCalls == 1)
    #expect(receivedMonth == january)
    #expect(receivedInstant == firstInstant)
  }

  @Test("non-Gregorian calendar injection stays aligned to Gregorian detail months")
  func normalizesDetailNavigationToGregorianMonths() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let january = try fixture.instant("2026-01-01T00:00:00Z")
    let february = try fixture.instant("2026-02-01T00:00:00Z")
    var requestedMonths: [Date] = []
    let operations = HabitDetailOperations(snapshot: { _, month, _, _ in
      requestedMonths.append(month)
      let dayCount = try #require(
        fixture.calendar.range(of: .day, in: .month, for: month)?.count
      )
      let history = try (0..<dayCount).map { offset in
        let start = try #require(
          fixture.calendar.date(byAdding: .day, value: offset, to: month)
        )
        let end = try #require(
          fixture.calendar.date(byAdding: .day, value: 1, to: start)
        )
        return HabitHistoryPeriod(
          key: "day-\(offset)",
          start: start,
          end: end,
          state: .future
        )
      }
      return fixture.snapshot(
        habitID: habit.id,
        cadence: .daily,
        earliestMonth: january,
        selectedMonth: month,
        latestMonth: february,
        history: history
      )
    })
    let model = HabitDetailModel(
      habit: habit,
      operations: operations,
      now: { fixture.now },
      timeZone: { fixture.timeZone },
      calendar: { Calendar(identifier: .hebrew) },
      locale: { fixture.locale }
    )

    model.start()
    let januaryPresentation = try #require(model.presentation)
    #expect(requestedMonths == [january])
    #expect(januaryPresentation.monthTitle == "January 2026")
    #expect(januaryPresentation.dailyLeadingFillerCount == 3)
    #expect(januaryPresentation.dailyTrailingFillerCount == 1)

    model.selectNextMonth()

    let februaryPresentation = try #require(model.presentation)
    #expect(requestedMonths == [january, february])
    #expect(februaryPresentation.monthTitle == "February 2026")
    #expect(februaryPresentation.dailyLeadingFillerCount == 6)
    #expect(februaryPresentation.dailyTrailingFillerCount == 1)
  }

  @Test("time-zone changes preserve the selected civil Gregorian month")
  func rebasesSelectedCivilMonthAcrossTimeZones() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let februaryInstant = try fixture.instant("2026-02-15T12:00:00Z")
    var selectedTimeZone = fixture.timeZone
    var requests: [(month: Date, timeZone: TimeZone)] = []
    let model = HabitDetailModel(
      habit: habit,
      operations: HabitDetailOperations(snapshot: { _, month, _, timeZone in
        requests.append((month, timeZone))
        if requests.count == 2 {
          throw HabitDetailTestError.unavailable
        }
        return fixture.snapshot(
          habitID: habit.id,
          cadence: .daily,
          selectedMonth: month
        )
      }),
      now: { februaryInstant },
      timeZone: { selectedTimeZone },
      calendar: { fixture.calendar },
      locale: { fixture.locale },
      boundaryScheduling: .disabled
    )

    model.start()
    selectedTimeZone = losAngeles
    model.sceneBecameActive()
    #expect(model.presentation == nil)
    #expect(model.loadFailure != nil)
    model.retryLoad()

    #expect(requests.count == 3)
    #expect(requests[0].timeZone == fixture.timeZone)
    #expect(requests[1].timeZone == losAngeles)
    #expect(requests[2].timeZone == losAngeles)
    var losAngelesCalendar = fixture.calendar
    losAngelesCalendar.timeZone = losAngeles
    let components = losAngelesCalendar.dateComponents(
      [.year, .month, .day, .hour],
      from: requests[2].month
    )
    #expect(components.year == 2026)
    #expect(components.month == 2)
    #expect(components.day == 1)
    #expect(components.hour == 0)
    #expect(model.presentation?.monthTitle == "February 2026")
  }

  @Test("environment synchronization drives first load and refresh without duplicate schedules")
  func synchronizesEnvironmentDependencies() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let scheduler = HabitDetailBoundaryRecorder()
    var snapshotCalls = 0
    var receivedTimeZones: [TimeZone] = []
    let model = HabitDetailModel(
      habit: habit,
      operations: HabitDetailOperations(snapshot: { _, month, _, timeZone in
        snapshotCalls += 1
        receivedTimeZones.append(timeZone)
        return fixture.snapshot(
          habitID: habit.id,
          cadence: .daily,
          selectedMonth: month
        )
      }),
      now: { fixture.now },
      timeZone: { fixture.timeZone },
      calendar: { fixture.calendar },
      locale: { fixture.locale },
      boundaryScheduling: scheduler.scheduling
    )
    var environmentCalendar = fixture.calendar
    environmentCalendar.timeZone = losAngeles
    let english = Locale(identifier: "en_US")

    model.synchronizeEnvironment(
      calendar: environmentCalendar,
      locale: english,
      timeZone: losAngeles
    )
    #expect(snapshotCalls == 0)
    #expect(scheduler.records.isEmpty)

    model.start()
    #expect(snapshotCalls == 1)
    #expect(receivedTimeZones == [losAngeles])
    #expect(scheduler.records.count == 1)
    #expect(scheduler.activeCount == 1)

    model.synchronizeEnvironment(
      calendar: environmentCalendar,
      locale: english,
      timeZone: losAngeles
    )
    #expect(snapshotCalls == 1)
    #expect(scheduler.records.count == 1)

    model.synchronizeEnvironment(
      calendar: environmentCalendar,
      locale: Locale(identifier: "fr_FR"),
      timeZone: losAngeles
    )
    #expect(snapshotCalls == 2)
    #expect(receivedTimeZones == [losAngeles, losAngeles])
    #expect(scheduler.records.count == 2)
    #expect(scheduler.activeCount == 1)
    #expect(model.presentation?.monthTitle == "janvier 2026")
  }

  @Test("entry accessibility combines locale-formatted facts with its localized action")
  func localizesEntryAccessibilityLabel() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let entry = HabitEditableEntry(
      id: UUID(),
      timestamp: try fixture.instant("2026-01-05T09:05:00Z"),
      amount: 12_345,
      bucketKey: "2026-01-05",
      unit: "pas",
      bucketStart: try fixture.instant("2026-01-05T00:00:00Z"),
      bucketEnd: try fixture.instant("2026-01-06T00:00:00Z")
    )
    let snapshot = fixture.snapshot(
      habitID: habit.id,
      cadence: .daily,
      selectedMonth: try fixture.instant("2026-01-01T00:00:00Z"),
      editableEntries: [entry]
    )
    let model = HabitDetailModel(
      habit: habit,
      operations: HabitDetailOperations(snapshot: { _, _, _, _ in snapshot }),
      now: { fixture.now },
      timeZone: { fixture.timeZone },
      calendar: { fixture.calendar },
      locale: { Locale(identifier: "fr_FR") }
    )

    model.start()

    let fact = try #require(model.presentation?.entries.first)
    #expect(
      fact.accessibilityLabel
        == "\(fact.scopeText), \(fact.timeText), \(fact.amountText), Delete entry"
    )
    #expect(fact.scopeText == "lundi 5 janvier 2026")
    #expect(fact.amountText == "12 345 pas")
  }

  @Test("entry deletion is authorized, nonreentrant, retryable, and fully refreshed")
  func guardsAndRetriesEntryDeletion() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let entryID = UUID()
    let january = try fixture.instant("2026-01-01T00:00:00Z")
    let projectedEntry = HabitEditableEntry(
      id: entryID,
      timestamp: fixture.now,
      amount: 1,
      bucketKey: "2026-01-15",
      unit: "times",
      bucketStart: try fixture.instant("2026-01-15T00:00:00Z"),
      bucketEnd: try fixture.instant("2026-01-16T00:00:00Z")
    )
    var snapshotCalls = 0
    var deleteCalls: [UUID] = []
    var shouldFail = true
    var model: HabitDetailModel!
    let operations = HabitDetailOperations(
      snapshot: { _, _, _, _ in
        snapshotCalls += 1
        return fixture.snapshot(
          habitID: habit.id,
          cadence: .daily,
          selectedMonth: january,
          editableEntries: snapshotCalls == 1 || shouldFail ? [projectedEntry] : []
        )
      },
      deleteEntry: { id, _, _, _ in
        deleteCalls.append(id)
        model.deleteEntry(id: id)
        if shouldFail {
          throw HabitDetailTestError.unavailable
        }
        return .deleted
      }
    )
    model = fixture.model(habit: habit, operations: operations)
    model.start()
    let verifiedPresentation = model.presentation

    model.deleteEntry(id: entryID)

    #expect(deleteCalls == [entryID])
    #expect(snapshotCalls == 1)
    #expect(model.presentation == verifiedPresentation)
    #expect(model.operationFailure?.placement == .entries)
    #expect(model.operationFailure?.retryTitle == "Try again")
    #expect(!model.isOperationInFlight)

    shouldFail = false
    model.retryOperation()

    #expect(deleteCalls == [entryID, entryID])
    #expect(snapshotCalls == 2)
    #expect(model.presentation?.entries.isEmpty == true)
    #expect(model.operationFailure == nil)
    #expect(!model.isOperationInFlight)
  }

  @Test("mutation retry survives an intervening load failure and reconciliation")
  func preservesMutationRetryAcrossLoadFailure() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let entryID = UUID()
    let entry = HabitEditableEntry(
      id: entryID,
      timestamp: fixture.now,
      amount: 1,
      bucketKey: "2026-01-15",
      unit: "times",
      bucketStart: try fixture.instant("2026-01-15T00:00:00Z"),
      bucketEnd: try fixture.instant("2026-01-16T00:00:00Z")
    )
    var snapshotCalls = 0
    var deleteCalls = 0
    var mutationShouldFail = true
    let model = fixture.model(
      habit: habit,
      operations: HabitDetailOperations(
        snapshot: { _, month, _, _ in
          snapshotCalls += 1
          if snapshotCalls == 2 {
            throw HabitDetailTestError.unavailable
          }
          return fixture.snapshot(
            habitID: habit.id,
            cadence: .daily,
            selectedMonth: month,
            editableEntries: mutationShouldFail ? [entry] : []
          )
        },
        deleteEntry: { _, _, _, _ in
          deleteCalls += 1
          if mutationShouldFail {
            throw HabitDetailTestError.unavailable
          }
          return .deleted
        }
      )
    )
    model.start()
    model.deleteEntry(id: entryID)
    let originalFailure = model.operationFailure

    model.sceneBecameActive()

    #expect(model.presentation == nil)
    #expect(model.loadFailure != nil)
    #expect(model.operationFailure == originalFailure)

    model.retryLoad()

    #expect(model.presentation?.entries.map(\.id) == [entryID])
    #expect(model.loadFailure == nil)
    #expect(model.operationFailure == originalFailure)

    mutationShouldFail = false
    model.retryOperation()

    #expect(deleteCalls == 2)
    #expect(snapshotCalls == 4)
    #expect(model.presentation?.entries.isEmpty == true)
    #expect(model.operationFailure == nil)
  }

  @Test("unprojected entry identifiers never dispatch or refresh")
  func refusesUnprojectedEntryDeletion() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let projectedID = UUID()
    let finalID = UUID()
    let exemptID = UUID()
    let missingID = UUID()
    let projectedEntry = HabitEditableEntry(
      id: projectedID,
      timestamp: fixture.now,
      amount: 1,
      bucketKey: "2026-01-15",
      unit: "times",
      bucketStart: try fixture.instant("2026-01-15T00:00:00Z"),
      bucketEnd: try fixture.instant("2026-01-16T00:00:00Z")
    )
    var snapshotCalls = 0
    var deleteCalls = 0
    let model = fixture.model(
      habit: habit,
      operations: HabitDetailOperations(
        snapshot: { _, _, _, _ in
          snapshotCalls += 1
          return fixture.snapshot(
            habitID: habit.id,
            cadence: .daily,
            selectedMonth: try fixture.instant("2026-01-01T00:00:00Z"),
            editableEntries: [projectedEntry]
          )
        },
        deleteEntry: { _, _, _, _ in
          deleteCalls += 1
          return .deleted
        }
      )
    )
    model.start()

    model.deleteEntry(id: finalID)
    model.deleteEntry(id: exemptID)
    model.deleteEntry(id: missingID)

    #expect(deleteCalls == 0)
    #expect(snapshotCalls == 1)
    #expect(model.presentation?.entries.map(\.id) == [projectedID])
    #expect(model.operationFailure == nil)
  }

  @Test("live deletion refreshes for vanished, foreign-only, and ambiguous owned matches")
  func liveDeletionNeverSubstitutesAnEntry() throws {
    let fixture = try HabitDetailFixture()
    let container = try TendModelContainer.inMemory()
    let context = container.mainContext
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let foreignHabit = Habit(name: "Read", cadence: .daily, target: 1)
    context.insert(habit)
    context.insert(foreignHabit)
    let selectedID = UUID()
    let owned = LogEntry(
      id: selectedID,
      timestamp: fixture.now,
      amount: 1,
      habit: habit
    )
    let foreign = LogEntry(
      id: selectedID,
      timestamp: fixture.now,
      amount: 1,
      habit: foreignHabit
    )
    context.insert(owned)
    context.insert(foreign)
    try context.save()
    let projectedEntry = HabitEditableEntry(
      id: selectedID,
      timestamp: fixture.now,
      amount: 1,
      bucketKey: "2026-01-15",
      unit: "times",
      bucketStart: try fixture.instant("2026-01-15T00:00:00Z"),
      bucketEnd: try fixture.instant("2026-01-16T00:00:00Z")
    )
    var snapshotCalls = 0
    let operations = HabitDetailOperations.live(
      context: context,
      snapshot: { _, _, _, _ in
        snapshotCalls += 1
        return fixture.snapshot(
          habitID: habit.id,
          cadence: .daily,
          selectedMonth: try fixture.instant("2026-01-01T00:00:00Z"),
          editableEntries: snapshotCalls == 1 ? [projectedEntry] : []
        )
      }
    )
    let model = fixture.model(habit: habit, operations: operations)
    model.start()
    context.delete(owned)
    try context.save()

    model.deleteEntry(id: selectedID)

    let foreignID = foreign.persistentModelID
    let foreignStillExists = try context.fetch(
      FetchDescriptor<LogEntry>(
        predicate: #Predicate { $0.id == selectedID }
      )
    )
    #expect(snapshotCalls == 2)
    #expect(foreignStillExists.map(\.persistentModelID) == [foreignID])
    #expect(model.presentation?.entries.isEmpty == true)
    #expect(model.operationFailure == nil)

    let ambiguousID = UUID()
    let firstOwned = LogEntry(
      id: ambiguousID,
      timestamp: fixture.now,
      amount: 1,
      habit: habit
    )
    let secondOwned = LogEntry(
      id: ambiguousID,
      timestamp: fixture.now,
      amount: 1,
      habit: habit
    )
    context.insert(firstOwned)
    context.insert(secondOwned)
    try context.save()
    snapshotCalls = 0
    let ambiguousEntry = HabitEditableEntry(
      id: ambiguousID,
      timestamp: fixture.now,
      amount: 1,
      bucketKey: "2026-01-15",
      unit: "times",
      bucketStart: try fixture.instant("2026-01-15T00:00:00Z"),
      bucketEnd: try fixture.instant("2026-01-16T00:00:00Z")
    )
    let ambiguousModel = fixture.model(
      habit: habit,
      operations: .live(
        context: context,
        snapshot: { _, _, _, _ in
          snapshotCalls += 1
          return fixture.snapshot(
            habitID: habit.id,
            cadence: .daily,
            selectedMonth: try fixture.instant("2026-01-01T00:00:00Z"),
            editableEntries: snapshotCalls == 1 ? [ambiguousEntry] : []
          )
        }
      )
    )
    ambiguousModel.start()

    ambiguousModel.deleteEntry(id: ambiguousID)

    let ambiguousMatches = try context.fetch(
      FetchDescriptor<LogEntry>(
        predicate: #Predicate { $0.id == ambiguousID }
      )
    )
    #expect(snapshotCalls == 2)
    #expect(ambiguousMatches.count == 2)
    #expect(ambiguousModel.operationFailure == nil)
  }

  @Test("Edit cancel preserves facts while one successful save recomputes")
  func refreshesOnlyAfterSavedEdit() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    var snapshotCalls = 0
    let model = fixture.model(
      habit: habit,
      operations: HabitDetailOperations(snapshot: { _, month, _, _ in
        snapshotCalls += 1
        return fixture.snapshot(
          habitID: habit.id,
          cadence: .daily,
          selectedMonth: month
        )
      })
    )
    model.start()

    model.presentEdit()
    #expect(model.isPresentingEdit)
    #expect(model.habitForEditing === habit)
    model.editCancelled()
    #expect(!model.isPresentingEdit)
    #expect(snapshotCalls == 1)

    model.presentEdit()
    habit.name = "Evening walk"
    model.editSaved()
    model.editSaved()

    #expect(!model.isPresentingEdit)
    #expect(snapshotCalls == 2)
    #expect(model.presentation?.name == "Evening walk")
  }

  @Test("lifecycle mutations sample once, reject reentry, flip facts, and retry failures")
  func dispatchesAndRetriesLifecycleMutations() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    var snapshotCalls = 0
    var archiveCalls: [(Date, TimeZone)] = []
    var reactivateCalls: [(Date, TimeZone)] = []
    var archiveShouldFail = true
    var reactivateShouldFail = true
    var nowCalls = 0
    var timeZoneCalls = 0
    var model: HabitDetailModel!
    let operations = HabitDetailOperations(
      snapshot: { _, month, _, _ in
        snapshotCalls += 1
        return fixture.snapshot(
          habitID: habit.id,
          cadence: .daily,
          selectedMonth: month
        )
      },
      deactivate: { selectedHabit, instant, zone in
        archiveCalls.append((instant, zone))
        model.archive()
        if archiveShouldFail {
          throw HabitDetailTestError.unavailable
        }
        selectedHabit.isActive = false
      },
      reactivate: { selectedHabit, instant, zone in
        reactivateCalls.append((instant, zone))
        model.reactivate()
        if reactivateShouldFail {
          throw HabitDetailTestError.unavailable
        }
        selectedHabit.isActive = true
      }
    )
    model = HabitDetailModel(
      habit: habit,
      operations: operations,
      now: {
        nowCalls += 1
        return fixture.now
      },
      timeZone: {
        timeZoneCalls += 1
        return fixture.timeZone
      },
      calendar: { fixture.calendar },
      locale: { fixture.locale },
      boundaryScheduling: .disabled
    )
    model.start()
    nowCalls = 0
    timeZoneCalls = 0
    let verifiedPresentation = model.presentation

    model.archive()

    #expect(archiveCalls.count == 1)
    #expect(archiveCalls.first?.0 == fixture.now)
    #expect(archiveCalls.first?.1 == fixture.timeZone)
    #expect(nowCalls == 1)
    #expect(timeZoneCalls == 1)
    #expect(snapshotCalls == 1)
    #expect(model.presentation == verifiedPresentation)
    #expect(model.operationFailure?.placement == .lifecycle)

    archiveShouldFail = false
    model.retryOperation()

    #expect(archiveCalls.count == 2)
    #expect(snapshotCalls == 2)
    #expect(model.presentation?.isActive == false)
    #expect(model.operationFailure == nil)

    nowCalls = 0
    timeZoneCalls = 0
    model.reactivate()

    #expect(reactivateCalls.count == 1)
    #expect(reactivateCalls.first?.0 == fixture.now)
    #expect(reactivateCalls.first?.1 == fixture.timeZone)
    #expect(nowCalls == 1)
    #expect(timeZoneCalls == 1)
    #expect(snapshotCalls == 2)
    #expect(model.presentation?.isActive == false)
    #expect(model.operationFailure?.placement == .lifecycle)

    reactivateShouldFail = false
    model.retryOperation()

    #expect(reactivateCalls.count == 2)
    #expect(snapshotCalls == 3)
    #expect(model.presentation?.isActive == true)
    #expect(model.operationFailure == nil)
  }

  @Test("successful mutation followed by refresh failure clears stale derived facts")
  func clearsFactsWhenPostMutationRefreshFails() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let entryID = UUID()
    let entry = HabitEditableEntry(
      id: entryID,
      timestamp: fixture.now,
      amount: 1,
      bucketKey: "2026-01-15",
      unit: "times",
      bucketStart: try fixture.instant("2026-01-15T00:00:00Z"),
      bucketEnd: try fixture.instant("2026-01-16T00:00:00Z")
    )
    var snapshotCalls = 0
    let model = fixture.model(
      habit: habit,
      operations: HabitDetailOperations(
        snapshot: { _, month, _, _ in
          snapshotCalls += 1
          if snapshotCalls > 1 {
            throw HabitDetailTestError.unavailable
          }
          return fixture.snapshot(
            habitID: habit.id,
            cadence: .daily,
            selectedMonth: month,
            editableEntries: [entry]
          )
        },
        deleteEntry: { _, _, _, _ in .deleted }
      )
    )
    model.start()

    model.deleteEntry(id: entryID)

    #expect(snapshotCalls == 2)
    #expect(model.presentation == nil)
    #expect(model.selectedHistory == nil)
    #expect(model.loadFailure?.retryTitle == "Try again")
    #expect(model.operationFailure == nil)
  }

  @Test("boundary scheduling replaces one token across start, fire, activation, and stop")
  func replacesLocalMidnightSchedule() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let scheduler = HabitDetailBoundaryRecorder()
    var currentNow = fixture.now
    var snapshotCalls = 0
    let january16Boundary = try fixture.instant("2026-01-16T00:00:00Z")
    let january17Boundary = try fixture.instant("2026-01-17T00:00:00Z")
    let january18Boundary = try fixture.instant("2026-01-18T00:00:00Z")
    let model = HabitDetailModel(
      habit: habit,
      operations: HabitDetailOperations(snapshot: { _, month, _, _ in
        snapshotCalls += 1
        return fixture.snapshot(
          habitID: habit.id,
          cadence: .daily,
          selectedMonth: month
        )
      }),
      now: { currentNow },
      timeZone: { fixture.timeZone },
      calendar: { fixture.calendar },
      locale: { fixture.locale },
      boundaryScheduling: scheduler.scheduling
    )

    model.start()
    #expect(scheduler.records.map(\.date) == [january16Boundary])
    #expect(scheduler.activeCount == 1)

    model.start()
    #expect(scheduler.records.count == 2)
    #expect(scheduler.records[0].isCancelled)
    #expect(scheduler.activeCount == 1)

    currentNow = try fixture.instant("2026-01-16T12:00:00Z")
    scheduler.records[1].fire()
    #expect(snapshotCalls == 3)
    #expect(scheduler.records.count == 3)
    #expect(scheduler.records[1].isCancelled)
    #expect(scheduler.records[2].date == january17Boundary)
    #expect(scheduler.activeCount == 1)

    currentNow = try fixture.instant("2026-01-17T18:00:00Z")
    model.sceneBecameActive()
    #expect(snapshotCalls == 4)
    #expect(scheduler.records.count == 4)
    #expect(scheduler.records[2].isCancelled)
    #expect(scheduler.records[3].date == january18Boundary)
    #expect(scheduler.activeCount == 1)

    model.stop()
    #expect(scheduler.records[3].isCancelled)
    #expect(scheduler.activeCount == 0)
  }

  @Test("next local boundary follows spring DST and rollover preserves a valid older page")
  func schedulesAcrossDSTAndClampsOnlyFromComputation() throws {
    let fixture = try HabitDetailFixture()
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    var localCalendar = Calendar(identifier: .gregorian)
    localCalendar.timeZone = losAngeles
    localCalendar.locale = fixture.locale
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let scheduler = HabitDetailBoundaryRecorder()
    var currentNow = try fixture.instant("2024-03-09T20:00:00Z")
    var shouldClamp = false
    let january = try fixture.instant("2024-01-01T08:00:00Z")
    let march = try fixture.instant("2024-03-01T08:00:00Z")
    let february = try fixture.instant("2024-02-01T08:00:00Z")
    let springForwardBoundary = try fixture.instant("2024-03-10T08:00:00Z")
    let postDSTBoundary = try fixture.instant("2024-03-11T07:00:00Z")
    let model = HabitDetailModel(
      habit: habit,
      operations: HabitDetailOperations(snapshot: { _, requestedMonth, _, _ in
        fixture.snapshot(
          habitID: habit.id,
          cadence: .daily,
          earliestMonth: january,
          selectedMonth: shouldClamp ? march : requestedMonth,
          latestMonth: march
        )
      }),
      now: { currentNow },
      timeZone: { losAngeles },
      calendar: { localCalendar },
      locale: { fixture.locale },
      boundaryScheduling: scheduler.scheduling
    )

    model.start()
    #expect(model.selectedMonth == march)
    #expect(scheduler.records[0].date == springForwardBoundary)

    model.selectPreviousMonth()
    #expect(model.selectedMonth == february)
    currentNow = try fixture.instant("2024-03-10T19:00:00Z")
    scheduler.records[0].fire()

    #expect(model.selectedMonth == february)
    #expect(scheduler.records[1].date == postDSTBoundary)
    #expect(scheduler.activeCount == 1)

    shouldClamp = true
    currentNow = try fixture.instant("2024-03-11T19:00:00Z")
    scheduler.records[1].fire()

    #expect(model.selectedMonth == march)
    #expect(scheduler.activeCount == 1)
  }

  @Test("successful refresh clears a failed deletion retry when the entry disappears")
  func clearsStaleDeletionRetryAfterRefresh() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let entryID = UUID()
    let entry = HabitEditableEntry(
      id: entryID,
      timestamp: fixture.now,
      amount: 1,
      bucketKey: "2026-01-15",
      unit: "times",
      bucketStart: try fixture.instant("2026-01-15T00:00:00Z"),
      bucketEnd: try fixture.instant("2026-01-16T00:00:00Z")
    )
    var snapshotCalls = 0
    var deleteCalls = 0
    let model = fixture.model(
      habit: habit,
      operations: HabitDetailOperations(
        snapshot: { _, month, _, _ in
          snapshotCalls += 1
          return fixture.snapshot(
            habitID: habit.id,
            cadence: .daily,
            selectedMonth: month,
            editableEntries: snapshotCalls == 1 ? [entry] : []
          )
        },
        deleteEntry: { _, _, _, _ in
          deleteCalls += 1
          throw HabitDetailTestError.unavailable
        }
      )
    )
    model.start()
    model.deleteEntry(id: entryID)
    #expect(model.operationFailure?.placement == .entries)

    model.sceneBecameActive()

    #expect(snapshotCalls == 2)
    #expect(model.presentation?.entries.isEmpty == true)
    #expect(model.operationFailure == nil)
    model.retryOperation()
    #expect(deleteCalls == 1)
  }

  @Test("successful refresh clears a lifecycle retry after the lifecycle flips")
  func clearsStaleLifecycleRetryAfterRefresh() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    var snapshotCalls = 0
    var archiveCalls = 0
    let model = fixture.model(
      habit: habit,
      operations: HabitDetailOperations(
        snapshot: { _, month, _, _ in
          snapshotCalls += 1
          return fixture.snapshot(
            habitID: habit.id,
            cadence: .daily,
            selectedMonth: month
          )
        },
        deactivate: { _, _, _ in
          archiveCalls += 1
          throw HabitDetailTestError.unavailable
        }
      )
    )
    model.start()
    model.archive()
    #expect(model.operationFailure?.placement == .lifecycle)
    habit.isActive = false

    model.sceneBecameActive()

    #expect(snapshotCalls == 2)
    #expect(model.presentation?.isActive == false)
    #expect(model.operationFailure == nil)
    model.retryOperation()
    #expect(archiveCalls == 1)
  }

  @Test("April rollover preserves an older valid page until computation clamps it")
  func preservesOlderPageAcrossMonthRollover() throws {
    let fixture = try HabitDetailFixture()
    let habit = Habit(name: "Walk", cadence: .daily, target: 1)
    let scheduler = HabitDetailBoundaryRecorder()
    let february = try fixture.instant("2026-02-01T00:00:00Z")
    let april = try fixture.instant("2026-04-01T00:00:00Z")
    var currentNow = try fixture.instant("2026-03-31T20:00:00Z")
    var shouldClamp = false
    let model = HabitDetailModel(
      habit: habit,
      operations: HabitDetailOperations(snapshot: { _, requestedMonth, _, _ in
        fixture.snapshot(
          habitID: habit.id,
          cadence: .daily,
          earliestMonth: february,
          selectedMonth: shouldClamp ? april : requestedMonth,
          latestMonth: april
        )
      }),
      now: { currentNow },
      timeZone: { fixture.timeZone },
      calendar: { fixture.calendar },
      locale: { fixture.locale },
      boundaryScheduling: scheduler.scheduling
    )
    model.start()
    model.selectPreviousMonth()
    #expect(model.selectedMonth == february)
    #expect(scheduler.records[0].date == april)

    currentNow = try fixture.instant("2026-04-01T12:00:00Z")
    scheduler.records[0].fire()

    #expect(model.selectedMonth == february)
    #expect(scheduler.activeCount == 1)

    shouldClamp = true
    currentNow = try fixture.instant("2026-04-02T12:00:00Z")
    scheduler.records[1].fire()

    #expect(model.selectedMonth == april)
    #expect(scheduler.activeCount == 1)
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }
}

@MainActor
private struct HabitDetailFixture {
  let timeZone: TimeZone
  let calendar: Calendar
  let locale: Locale
  let now: Date

  init() throws {
    timeZone = try #require(TimeZone(identifier: "UTC"))
    locale = Locale(identifier: "en_US")
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    calendar.timeZone = timeZone
    self.calendar = calendar
    now = try #require(
      ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")
    )
  }

  func model(
    habit: Habit,
    operations: HabitDetailOperations
  ) -> HabitDetailModel {
    HabitDetailModel(
      habit: habit,
      operations: operations,
      now: { now },
      timeZone: { timeZone },
      calendar: { calendar },
      locale: { locale },
      boundaryScheduling: .disabled
    )
  }

  func snapshot(
    habitID: UUID,
    cadence: HabitCadence,
    earliestMonth: Date? = nil,
    selectedMonth: Date,
    latestMonth: Date? = nil,
    streak: HabitStreakState? = nil,
    history: [HabitHistoryPeriod] = [],
    editableEntries: [HabitEditableEntry] = []
  ) -> HabitDetailSnapshot {
    HabitDetailSnapshot(
      habitID: habitID,
      cadence: cadence,
      monthRange: HabitDetailMonthRange(
        earliest: earliestMonth ?? selectedMonth,
        selected: selectedMonth,
        latest: latestMonth ?? selectedMonth
      ),
      streak: streak
        ?? HabitStreakState(
          currentStreak: 0,
          bestStreak: 0,
          isAtRisk: false,
          cadence: cadence
        ),
      history: history,
      editableEntries: editableEntries
    )
  }

  func dailyPeriod(
    day: Int,
    state: HabitHistoryState,
    progress: Int? = nil,
    target: Int? = nil,
    unit: String? = nil,
    isRequirementMet: Bool? = nil
  ) throws -> HabitHistoryPeriod {
    let start = try instant(String(format: "2026-01-%02dT00:00:00Z", day))
    let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
    return HabitHistoryPeriod(
      key: String(format: "2026-01-%02d", day),
      start: start,
      end: end,
      state: state,
      progress: progress,
      target: target,
      unit: unit,
      isRequirementMet: isRequirementMet
    )
  }

  func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }
}

@MainActor
extension HabitDetailBoundaryScheduling {
  fileprivate static var disabled: Self {
    Self { _, _ in HabitDetailBoundaryCancellation {} }
  }
}

@MainActor
private final class HabitDetailBoundaryRecorder {
  @MainActor
  final class Record {
    let date: Date
    private let action: @MainActor () -> Void
    var isCancelled = false

    init(date: Date, action: @escaping @MainActor () -> Void) {
      self.date = date
      self.action = action
    }

    func fire() {
      guard !isCancelled else { return }
      action()
    }
  }

  private(set) var records: [Record] = []

  var scheduling: HabitDetailBoundaryScheduling {
    HabitDetailBoundaryScheduling { [weak self] date, action in
      guard let self else {
        return HabitDetailBoundaryCancellation {}
      }
      let record = Record(date: date, action: action)
      records.append(record)
      return HabitDetailBoundaryCancellation {
        record.isCancelled = true
      }
    }
  }

  var activeCount: Int {
    records.count { !$0.isCancelled }
  }
}

private enum HabitDetailTestError: Error {
  case unavailable
}
