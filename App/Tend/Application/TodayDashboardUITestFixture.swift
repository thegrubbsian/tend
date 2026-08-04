#if DEBUG
  import Foundation
  import SwiftData
  import TendCore

  enum TodayDashboardUITestFixtureError: Error, Equatable {
    case unexpectedState(String)
  }

  @MainActor
  enum TodayDashboardUITestFixture {
    enum Variant {
      case mixed
      case allTended
      case inactive
      case failure
    }

    static let malformedCadenceRawValue = "unsupported-today-fixture"

    static func seed(
      _ variant: Variant,
      context: ModelContext,
      at launchInstant: Date,
      timeZone: TimeZone
    ) throws {
      let seeder = Seeder(
        context: context,
        launchInstant: launchInstant,
        timeZone: timeZone
      )
      switch variant {
      case .mixed:
        try seeder.seedMixed()
      case .allTended:
        try seeder.seedAllTended()
      case .inactive:
        try seeder.seedInactive()
      case .failure:
        try seeder.seedFailure()
      }
    }

    private struct Seeder {
      let context: ModelContext
      let launchInstant: Date
      let timeZone: TimeZone
      let schedule: CalendarBucketSchedule
      let calendar: Calendar
      let management: HabitManagementOperations
      let activity: HabitActivityOperations
      let logging: LogEntryOperations
      let today: HabitTodayComputation

      init(
        context: ModelContext,
        launchInstant: Date,
        timeZone: TimeZone
      ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4

        self.context = context
        self.launchInstant = launchInstant
        self.timeZone = timeZone
        schedule = CalendarBucketSchedule(timeZone: timeZone)
        self.calendar = calendar
        management = HabitManagementOperations(context: context)
        activity = HabitActivityOperations(context: context)
        logging = LogEntryOperations(context: context)
        today = HabitTodayComputation(context: context)
      }

      func seedMixed() throws {
        let exerciseCreation = try localNoon(daysFromLaunch: -13)
        let exercise = try create(
          name: "Exercise",
          target: 8_000,
          unit: "steps",
          cadence: .daily,
          at: exerciseCreation
        )
        for offset in -13 ... -2 {
          try logging.append(
            amount: 8_000,
            to: exercise,
            at: try localNoon(daysFromLaunch: offset),
            timeZone: timeZone
          )
        }
        try logging.append(
          amount: 2_000,
          to: exercise,
          at: launchInstant,
          timeZone: timeZone
        )
        try logging.append(
          amount: 3_200,
          to: exercise,
          at: launchInstant,
          timeZone: timeZone
        )

        let meditate = try create(
          name: "Meditate",
          target: 1,
          unit: "time",
          cadence: .daily,
          at: launchInstant
        )
        let checkIn = try create(
          name: "Check in",
          target: 3,
          unit: "times",
          cadence: .weekly,
          pinnedWeekdays: .monday,
          at: launchInstant
        )
        try logging.append(
          amount: 1,
          to: checkIn,
          at: launchInstant,
          timeZone: timeZone
        )

        let read = try create(
          name: "Read",
          target: 20,
          unit: "pages",
          cadence: .daily,
          at: launchInstant
        )
        try logging.append(
          amount: 20,
          to: read,
          at: launchInstant,
          timeZone: timeZone
        )

        let water = try create(
          name: "Water seedlings",
          target: 3,
          unit: "times",
          cadence: .daily,
          at: launchInstant
        )
        try logging.append(
          amount: 2,
          to: water,
          at: launchInstant,
          timeZone: timeZone
        )
        try logging.append(
          amount: 3,
          to: water,
          at: launchInstant,
          timeZone: timeZone
        )

        try verify(
          exercise,
          equals: snapshot(
            progress: 5_200,
            target: 8_000,
            unit: "steps",
            cadence: .daily,
            currentStreak: 12,
            isAtRisk: true,
            isMet: false
          )
        )
        try verify(
          meditate,
          equals: snapshot(
            progress: 0,
            target: 1,
            unit: "time",
            cadence: .daily,
            currentStreak: 0,
            isAtRisk: false,
            isMet: false
          )
        )
        try verify(
          checkIn,
          equals: snapshot(
            progress: 1,
            target: 3,
            unit: "times",
            cadence: .weekly,
            currentStreak: 0,
            isAtRisk: false,
            isMet: false
          )
        )
        try verify(
          read,
          equals: snapshot(
            progress: 20,
            target: 20,
            unit: "pages",
            cadence: .daily,
            currentStreak: 1,
            isAtRisk: false,
            isMet: true
          )
        )
        try verify(
          water,
          equals: snapshot(
            progress: 5,
            target: 3,
            unit: "times",
            cadence: .daily,
            currentStreak: 1,
            isAtRisk: false,
            isMet: true
          )
        )
      }

      func seedAllTended() throws {
        let water = try create(
          name: "Drink water",
          target: 1,
          unit: "time",
          cadence: .daily,
          at: launchInstant
        )
        try logging.append(
          amount: 1,
          to: water,
          at: launchInstant,
          timeZone: timeZone
        )
        let review = try create(
          name: "Weekly review",
          target: 2,
          unit: "times",
          cadence: .weekly,
          pinnedWeekdays: .friday,
          at: launchInstant
        )
        try logging.append(
          amount: 2,
          to: review,
          at: launchInstant,
          timeZone: timeZone
        )

        try verify(
          water,
          equals: snapshot(
            progress: 1,
            target: 1,
            unit: "time",
            cadence: .daily,
            currentStreak: 1,
            isAtRisk: false,
            isMet: true
          )
        )
        try verify(
          review,
          equals: snapshot(
            progress: 2,
            target: 2,
            unit: "times",
            cadence: .weekly,
            currentStreak: 1,
            isAtRisk: false,
            isMet: true
          )
        )
      }

      func seedInactive() throws {
        let priorDay = try localNoon(daysFromLaunch: -1)
        let journal = try create(
          name: "Dormant journal",
          target: 1,
          unit: "page",
          cadence: .daily,
          at: priorDay
        )
        try logging.append(
          amount: 1,
          to: journal,
          at: priorDay,
          timeZone: timeZone
        )
        _ = try today.snapshot(
          for: journal,
          at: priorDay,
          timeZone: timeZone
        )
        try activity.deactivate(
          journal,
          at: launchInstant,
          timeZone: timeZone
        )
        guard !journal.isActive else {
          throw TodayDashboardUITestFixtureError.unexpectedState("today-inactive")
        }
        do {
          _ = try today.snapshot(
            for: journal,
            at: launchInstant,
            timeZone: timeZone
          )
          throw TodayDashboardUITestFixtureError.unexpectedState("today-inactive")
        } catch HabitTodayComputationError.inactiveHabit {
          return
        }
      }

      func seedFailure() throws {
        let met = try create(
          name: "Failure met",
          target: 1,
          unit: "time",
          cadence: .daily,
          at: launchInstant
        )
        try logging.append(
          amount: 1,
          to: met,
          at: launchInstant,
          timeZone: timeZone
        )
        let open = try create(
          name: "Failure open",
          target: 2,
          unit: "times",
          cadence: .weekly,
          at: launchInstant
        )
        try logging.append(
          amount: 1,
          to: open,
          at: launchInstant,
          timeZone: timeZone
        )
        let malformed = try create(
          name: "Malformed cadence",
          target: 1,
          unit: "time",
          cadence: .daily,
          at: launchInstant
        )

        _ = try today.snapshot(for: met, at: launchInstant, timeZone: timeZone)
        _ = try today.snapshot(for: open, at: launchInstant, timeZone: timeZone)
        _ = try today.snapshot(for: malformed, at: launchInstant, timeZone: timeZone)

        malformed.cadenceRawValue =
          TodayDashboardUITestFixture.malformedCadenceRawValue
        try context.save()

        _ = try today.snapshot(for: met, at: launchInstant, timeZone: timeZone)
        _ = try today.snapshot(for: open, at: launchInstant, timeZone: timeZone)
        do {
          _ = try today.snapshot(
            for: malformed,
            at: launchInstant,
            timeZone: timeZone
          )
          throw TodayDashboardUITestFixtureError.unexpectedState("today-failure")
        } catch BucketEvaluationError.unsupportedCadence(let rawValue)
          where rawValue == TodayDashboardUITestFixture.malformedCadenceRawValue
        {
          return
        }
      }

      private func create(
        name: String,
        target: Int,
        unit: String,
        cadence: HabitCadence,
        pinnedWeekdays: PinnedWeekdays = .none,
        at instant: Date
      ) throws -> Habit {
        try management.create(
          fields: HabitEditableFields(
            name: name,
            target: target,
            unit: unit,
            pinnedWeekdays: pinnedWeekdays
          ),
          cadence: cadence,
          at: instant,
          timeZone: timeZone
        )
      }

      private func snapshot(
        progress: Int,
        target: Int,
        unit: String,
        cadence: HabitCadence,
        currentStreak: Int,
        isAtRisk: Bool,
        isMet: Bool
      ) throws -> HabitTodaySnapshot {
        HabitTodaySnapshot(
          periodKey: try schedule.period(
            containing: launchInstant,
            cadence: cadence
          ).key,
          progress: progress,
          target: target,
          unit: unit,
          cadence: cadence,
          currentStreak: currentStreak,
          isAtRisk: isAtRisk,
          isMet: isMet
        )
      }

      private func verify(
        _ habit: Habit,
        equals expected: HabitTodaySnapshot
      ) throws {
        let actual = try today.snapshot(
          for: habit,
          at: launchInstant,
          timeZone: timeZone
        )
        guard actual == expected else {
          throw TodayDashboardUITestFixtureError.unexpectedState(habit.name)
        }
      }

      private func localNoon(daysFromLaunch offset: Int) throws -> Date {
        let launchDay = calendar.startOfDay(for: launchInstant)
        guard
          let day = calendar.date(
            byAdding: .day,
            value: offset,
            to: launchDay
          ),
          let noon = calendar.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: day
          )
        else {
          throw CalendarBucketScheduleError.calendarCalculationFailed
        }
        return noon
      }
    }
  }
#endif
