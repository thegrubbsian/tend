#if DEBUG
  import Foundation
  import SwiftData
  import TendCore

  @MainActor
  enum HabitDetailUITestFixture {
    static func seed(
      context: ModelContext,
      at launchInstant: Date,
      timeZone: TimeZone
    ) throws {
      var calendar = Calendar(identifier: .gregorian)
      calendar.locale = Locale(identifier: "en_US_POSIX")
      calendar.timeZone = timeZone
      calendar.firstWeekday = 2
      calendar.minimumDaysInFirstWeek = 4

      let management = HabitManagementOperations(context: context)
      let reconciler = BucketReconciler(context: context)
      let logging = LogEntryOperations(context: context)
      let activity = HabitActivityOperations(context: context)
      let streaks = HabitStreakComputation(context: context)
      let details = HabitDetailComputation(context: context)

      try seedDailyGarden(
        management: management,
        reconciler: reconciler,
        logging: logging,
        activity: activity,
        streaks: streaks,
        details: details,
        launchInstant: launchInstant,
        timeZone: timeZone,
        calendar: calendar
      )
      try seedWeeklyFieldNotes(
        management: management,
        reconciler: reconciler,
        logging: logging,
        streaks: streaks,
        details: details,
        launchInstant: launchInstant,
        timeZone: timeZone,
        calendar: calendar
      )
      try seedDormantReading(
        management: management,
        logging: logging,
        activity: activity,
        streaks: streaks,
        details: details,
        launchInstant: launchInstant,
        timeZone: timeZone,
        calendar: calendar
      )
    }

    private static func seedDailyGarden(
      management: HabitManagementOperations,
      reconciler: BucketReconciler,
      logging: LogEntryOperations,
      activity: HabitActivityOperations,
      streaks: HabitStreakComputation,
      details: HabitDetailComputation,
      launchInstant: Date,
      timeZone: TimeZone,
      calendar: Calendar
    ) throws {
      let creationInstant = try localNoon(
        daysFrom: -12,
        relativeTo: launchInstant,
        calendar: calendar
      )
      let habit = try management.create(
        fields: HabitEditableFields(name: "Daily garden", target: 2, unit: "times"),
        cadence: .daily,
        at: creationInstant,
        timeZone: timeZone
      )
      try logging.append(
        amount: 2,
        to: habit,
        at: creationInstant,
        timeZone: timeZone
      )

      let elevenDaysBefore = try localNoon(
        daysFrom: -11,
        relativeTo: launchInstant,
        calendar: calendar
      )
      try logging.append(
        amount: 2,
        to: habit,
        at: elevenDaysBefore,
        timeZone: timeZone
      )
      try reconciler.reconcile(
        habit: habit,
        at: try localNoon(
          daysFrom: -10,
          relativeTo: launchInstant,
          calendar: calendar
        ),
        timeZone: timeZone
      )
      for offset in [-9, -8] {
        try logging.append(
          amount: 2,
          to: habit,
          at: try localNoon(
            daysFrom: offset,
            relativeTo: launchInstant,
            calendar: calendar
          ),
          timeZone: timeZone
        )
      }

      try activity.deactivate(
        habit,
        at: try localNoon(
          daysFrom: -7,
          relativeTo: launchInstant,
          calendar: calendar
        ),
        timeZone: timeZone
      )
      let reactivationInstant = try localNoon(
        daysFrom: -4,
        relativeTo: launchInstant,
        calendar: calendar
      )
      try activity.reactivate(
        habit,
        at: reactivationInstant,
        timeZone: timeZone
      )
      for offset in [-4, -3, -2] {
        try logging.append(
          amount: 2,
          to: habit,
          at: try localNoon(
            daysFrom: offset,
            relativeTo: launchInstant,
            calendar: calendar
          ),
          timeZone: timeZone
        )
      }

      let yesterday = try localNoon(
        daysFrom: -1,
        relativeTo: launchInstant,
        calendar: calendar
      )
      try logging.append(
        amount: 1,
        to: habit,
        at: yesterday,
        timeZone: timeZone
      )
      try logging.append(
        amount: 1,
        to: habit,
        at: launchInstant,
        timeZone: timeZone
      )
      let yesterdayKey = try CalendarBucketSchedule(timeZone: timeZone).period(
        containing: yesterday,
        cadence: .daily
      ).key
      try logging.append(
        amount: 1,
        to: habit,
        destination: .periodKey(yesterdayKey),
        at: launchInstant,
        timeZone: timeZone
      )

      _ = try streaks.compute(
        habit: habit,
        at: launchInstant,
        timeZone: timeZone
      )
      _ = try details.snapshot(
        for: habit,
        selectedMonth: launchInstant,
        at: launchInstant,
        timeZone: timeZone
      )
    }

    private static func seedWeeklyFieldNotes(
      management: HabitManagementOperations,
      reconciler: BucketReconciler,
      logging: LogEntryOperations,
      streaks: HabitStreakComputation,
      details: HabitDetailComputation,
      launchInstant: Date,
      timeZone: TimeZone,
      calendar: Calendar
    ) throws {
      let currentWeek = try CalendarBucketSchedule(timeZone: timeZone).period(
        containing: launchInstant,
        cadence: .weekly
      )
      func weeklyNoon(_ weeksFromCurrent: Int) throws -> Date {
        try localNoon(
          daysFrom: weeksFromCurrent * 7,
          relativeTo: currentWeek.start,
          calendar: calendar
        )
      }

      let creationInstant = try weeklyNoon(-8)
      let habit = try management.create(
        fields: HabitEditableFields(
          name: "Weekly field notes",
          target: 2,
          unit: "pages"
        ),
        cadence: .weekly,
        at: creationInstant,
        timeZone: timeZone
      )
      try logging.append(
        amount: 2,
        to: habit,
        at: creationInstant,
        timeZone: timeZone
      )
      try logging.append(
        amount: 2,
        to: habit,
        at: try weeklyNoon(-7),
        timeZone: timeZone
      )
      try reconciler.reconcile(
        habit: habit,
        at: try weeklyNoon(-6),
        timeZone: timeZone
      )
      for offset in [-5, -4] {
        try logging.append(
          amount: 2,
          to: habit,
          at: try weeklyNoon(offset),
          timeZone: timeZone
        )
      }
      try reconciler.reconcile(
        habit: habit,
        at: try weeklyNoon(-3),
        timeZone: timeZone
      )
      try logging.append(
        amount: 2,
        to: habit,
        at: try weeklyNoon(-2),
        timeZone: timeZone
      )
      try logging.append(
        amount: 1,
        to: habit,
        at: try weeklyNoon(-1),
        timeZone: timeZone
      )
      try logging.append(
        amount: 1,
        to: habit,
        at: launchInstant,
        timeZone: timeZone
      )
      try reconciler.reconcile(
        habit: habit,
        at: launchInstant,
        timeZone: timeZone
      )

      _ = try streaks.compute(
        habit: habit,
        at: launchInstant,
        timeZone: timeZone
      )
      _ = try details.snapshot(
        for: habit,
        selectedMonth: launchInstant,
        at: launchInstant,
        timeZone: timeZone
      )
    }

    private static func seedDormantReading(
      management: HabitManagementOperations,
      logging: LogEntryOperations,
      activity: HabitActivityOperations,
      streaks: HabitStreakComputation,
      details: HabitDetailComputation,
      launchInstant: Date,
      timeZone: TimeZone,
      calendar: Calendar
    ) throws {
      let creationInstant = try localNoon(
        daysFrom: -8,
        relativeTo: launchInstant,
        calendar: calendar
      )
      let habit = try management.create(
        fields: HabitEditableFields(
          name: "Dormant reading",
          target: 1,
          unit: "chapter"
        ),
        cadence: .daily,
        at: creationInstant,
        timeZone: timeZone
      )
      for offset in -8 ... -6 {
        try logging.append(
          amount: 1,
          to: habit,
          at: try localNoon(
            daysFrom: offset,
            relativeTo: launchInstant,
            calendar: calendar
          ),
          timeZone: timeZone
        )
      }
      try activity.deactivate(
        habit,
        at: try localNoon(
          daysFrom: -5,
          relativeTo: launchInstant,
          calendar: calendar
        ),
        timeZone: timeZone
      )

      _ = try streaks.compute(
        habit: habit,
        at: launchInstant,
        timeZone: timeZone
      )
      _ = try details.snapshot(
        for: habit,
        selectedMonth: launchInstant,
        at: launchInstant,
        timeZone: timeZone
      )
    }

    private static func localNoon(
      daysFrom offset: Int,
      relativeTo instant: Date,
      calendar: Calendar
    ) throws -> Date {
      let origin = calendar.startOfDay(for: instant)
      guard
        let day = calendar.date(byAdding: .day, value: offset, to: origin),
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)
      else {
        throw CalendarBucketScheduleError.calendarCalculationFailed
      }
      return noon
    }
  }
#endif
