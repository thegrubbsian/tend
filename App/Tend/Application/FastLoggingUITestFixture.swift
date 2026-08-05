#if DEBUG
  import Foundation
  import SwiftData
  import TendCore

  enum FastLoggingUITestFixtureError: Error, Equatable {
    case unexpectedState(String)
  }

  @MainActor
  enum FastLoggingUITestFixture {
    enum Variant {
      case daily
      case weekly
    }

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
      case .daily:
        try seeder.seedDaily()
      case .weekly:
        try seeder.seedWeekly()
      }
    }

    private struct Seeder {
      let launchInstant: Date
      let timeZone: TimeZone
      let schedule: CalendarBucketSchedule
      let calendar: Calendar
      let management: HabitManagementOperations
      let logging: LogEntryOperations
      let loggingComputation: HabitLoggingComputation
      let todayComputation: HabitTodayComputation

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

        self.launchInstant = launchInstant
        self.timeZone = timeZone
        schedule = CalendarBucketSchedule(timeZone: timeZone)
        self.calendar = calendar
        management = HabitManagementOperations(context: context)
        logging = LogEntryOperations(context: context)
        loggingComputation = HabitLoggingComputation(context: context)
        todayComputation = HabitTodayComputation(context: context)
      }

      func seedDaily() throws {
        let current = try schedule.period(containing: launchInstant, cadence: .daily)
        let grace = try period(before: current)
        let twoDaysBefore = try period(before: grace)
        let threeDaysBefore = try period(before: twoDaysBefore)
        let fourDaysBefore = try period(before: threeDaysBefore)

        let targetOne = try create(
          name: "Feed the cat",
          target: 1,
          unit: "times",
          cadence: .daily,
          at: launchInstant
        )
        let exactTime = try create(
          name: "Meditate",
          target: 10,
          unit: "time",
          cadence: .daily,
          at: launchInstant
        )
        let multiCount = try create(
          name: "Posture checks",
          target: 4,
          unit: "times",
          cadence: .daily,
          at: launchInstant
        )
        let multiCountEntry = try logging.append(
          amount: 1,
          to: multiCount,
          at: launchInstant,
          timeZone: timeZone
        )
        let completedQuantity = try create(
          name: "Read 20 pages",
          target: 20,
          unit: "pages",
          cadence: .daily,
          at: launchInstant
        )
        let completedEntry = try logging.append(
          amount: 20,
          to: completedQuantity,
          at: launchInstant,
          timeZone: timeZone
        )

        let partialQuantity = try create(
          name: "Walk 8K steps",
          target: 8_000,
          unit: "steps",
          cadence: .daily,
          at: try noon(in: fourDaysBefore)
        )
        for period in [fourDaysBefore, threeDaysBefore, twoDaysBefore] {
          try logging.append(
            amount: 8_000,
            to: partialQuantity,
            at: try noon(in: period),
            timeZone: timeZone
          )
        }
        let graceEntry = try logging.append(
          amount: 3_000,
          to: partialQuantity,
          at: try noon(in: grace),
          timeZone: timeZone
        )
        let currentEntries = try [
          logging.append(
            amount: 2_000,
            to: partialQuantity,
            at: launchInstant,
            timeZone: timeZone
          ),
          logging.append(
            amount: 2_000,
            to: partialQuantity,
            at: launchInstant,
            timeZone: timeZone
          ),
        ]

        try verify(
          targetOne,
          cadence: .daily,
          target: 1,
          unit: "times",
          currentPeriod: current,
          currentProgress: 0,
          currentEntries: [],
          grace: nil,
          currentStreak: 0,
          isAtRisk: false,
          isMet: false
        )
        try verify(
          exactTime,
          cadence: .daily,
          target: 10,
          unit: "time",
          currentPeriod: current,
          currentProgress: 0,
          currentEntries: [],
          grace: nil,
          currentStreak: 0,
          isAtRisk: false,
          isMet: false
        )
        try verify(
          multiCount,
          cadence: .daily,
          target: 4,
          unit: "times",
          currentPeriod: current,
          currentProgress: 1,
          currentEntries: [multiCountEntry],
          grace: nil,
          currentStreak: 0,
          isAtRisk: false,
          isMet: false
        )
        try verify(
          completedQuantity,
          cadence: .daily,
          target: 20,
          unit: "pages",
          currentPeriod: current,
          currentProgress: 20,
          currentEntries: [completedEntry],
          grace: nil,
          currentStreak: 1,
          isAtRisk: false,
          isMet: true
        )
        try verify(
          partialQuantity,
          cadence: .daily,
          target: 8_000,
          unit: "steps",
          currentPeriod: current,
          currentProgress: 4_000,
          currentEntries: currentEntries,
          grace: ExpectedGrace(
            period: grace,
            progress: 3_000,
            entries: [graceEntry]
          ),
          currentStreak: 3,
          isAtRisk: true,
          isMet: false
        )
      }

      func seedWeekly() throws {
        let current = try schedule.period(containing: launchInstant, cadence: .weekly)
        let grace = try period(before: current)
        let graceInstant = try noon(in: grace)

        let checkIns = try create(
          name: "Weekly check-ins",
          target: 3,
          unit: "times",
          cadence: .weekly,
          pinnedWeekdays: .monday,
          at: graceInstant
        )
        let checkInsGraceEntry = try logging.append(
          amount: 1,
          to: checkIns,
          at: graceInstant,
          timeZone: timeZone
        )
        let checkInsCurrentEntry = try logging.append(
          amount: 1,
          to: checkIns,
          at: launchInstant,
          timeZone: timeZone
        )

        let fieldNotes = try create(
          name: "Weekly field notes",
          target: 100,
          unit: "pages",
          cadence: .weekly,
          pinnedWeekdays: .friday,
          at: graceInstant
        )
        let notesGraceEntry = try logging.append(
          amount: 30,
          to: fieldNotes,
          at: graceInstant,
          timeZone: timeZone
        )
        let notesCurrentEntries = try [
          logging.append(
            amount: 20,
            to: fieldNotes,
            at: launchInstant,
            timeZone: timeZone
          ),
          logging.append(
            amount: 20,
            to: fieldNotes,
            at: launchInstant,
            timeZone: timeZone
          ),
        ]

        try verify(
          checkIns,
          cadence: .weekly,
          target: 3,
          unit: "times",
          pinnedWeekdays: .monday,
          currentPeriod: current,
          currentProgress: 1,
          currentEntries: [checkInsCurrentEntry],
          grace: ExpectedGrace(
            period: grace,
            progress: 1,
            entries: [checkInsGraceEntry]
          ),
          currentStreak: 0,
          isAtRisk: false,
          isMet: false
        )
        try verify(
          fieldNotes,
          cadence: .weekly,
          target: 100,
          unit: "pages",
          pinnedWeekdays: .friday,
          currentPeriod: current,
          currentProgress: 40,
          currentEntries: notesCurrentEntries,
          grace: ExpectedGrace(
            period: grace,
            progress: 30,
            entries: [notesGraceEntry]
          ),
          currentStreak: 0,
          isAtRisk: false,
          isMet: false
        )
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

      private func verify(
        _ habit: Habit,
        cadence: HabitCadence,
        target: Int,
        unit: String,
        pinnedWeekdays: PinnedWeekdays = .none,
        currentPeriod: CalendarBucketPeriod,
        currentProgress: Int,
        currentEntries: [LogEntry],
        grace: ExpectedGrace?,
        currentStreak: Int,
        isAtRisk: Bool,
        isMet: Bool
      ) throws {
        guard habit.cadenceRawValue == cadence.rawValue,
          habit.target == target,
          habit.unit == unit,
          habit.pinnedWeekdaysRawValue == pinnedWeekdays.rawValue
        else {
          throw FastLoggingUITestFixtureError.unexpectedState(habit.name)
        }

        let loggingSnapshot = try loggingComputation.snapshot(
          for: habit,
          at: launchInstant,
          timeZone: timeZone
        )
        let expectedGrace = grace.map {
          ExpectedBucketFacts(
            periodKey: $0.period.key,
            phase: .grace,
            progress: $0.progress,
            target: target,
            unit: unit,
            isMet: $0.progress >= target,
            entries: entryFacts($0.entries)
          )
        }
        guard loggingSnapshot.habitID == habit.persistentModelID,
          loggingSnapshot.name == habit.name,
          loggingSnapshot.cadence == cadence,
          loggingSnapshot.target == target,
          loggingSnapshot.unit == unit,
          bucketFacts(loggingSnapshot.current)
            == ExpectedBucketFacts(
              periodKey: currentPeriod.key,
              phase: .open,
              progress: currentProgress,
              target: target,
              unit: unit,
              isMet: isMet,
              entries: entryFacts(currentEntries)
            ),
          graceFacts(loggingSnapshot.grace) == expectedGrace
        else {
          throw FastLoggingUITestFixtureError.unexpectedState(habit.name)
        }

        let todaySnapshot = try todayComputation.snapshot(
          for: habit,
          at: launchInstant,
          timeZone: timeZone
        )
        let expectedToday = HabitTodaySnapshot(
          periodKey: currentPeriod.key,
          progress: currentProgress,
          target: target,
          unit: unit,
          cadence: cadence,
          currentStreak: currentStreak,
          isAtRisk: isAtRisk,
          isMet: isMet
        )
        guard todaySnapshot == expectedToday else {
          throw FastLoggingUITestFixtureError.unexpectedState(habit.name)
        }
      }

      private func graceFacts(
        _ grace: HabitLoggingBucketSnapshot?
      ) -> ExpectedBucketFacts? {
        grace.map(bucketFacts)
      }

      private func bucketFacts(
        _ bucket: HabitLoggingBucketSnapshot
      ) -> ExpectedBucketFacts {
        ExpectedBucketFacts(
          periodKey: bucket.periodKey,
          phase: bucket.phase,
          progress: bucket.progress,
          target: bucket.target,
          unit: bucket.unit,
          isMet: bucket.isMet,
          entries: bucket.entries.map {
            ExpectedEntryFacts(
              id: $0.id,
              uuid: $0.uuid,
              timestamp: $0.timestamp,
              amount: $0.amount
            )
          }
        )
      }

      private func entryFacts(_ entries: [LogEntry]) -> [ExpectedEntryFacts] {
        entries
          .sorted { first, second in
            if first.timestamp != second.timestamp {
              return first.timestamp > second.timestamp
            }
            return first.persistentModelID < second.persistentModelID
          }
          .map {
            ExpectedEntryFacts(
              id: $0.persistentModelID,
              uuid: $0.id,
              timestamp: $0.timestamp,
              amount: $0.amount
            )
          }
      }

      private func period(
        before period: CalendarBucketPeriod
      ) throws -> CalendarBucketPeriod {
        try schedule.period(
          containing: period.start.addingTimeInterval(-1),
          cadence: period.cadence
        )
      }

      private func noon(in period: CalendarBucketPeriod) throws -> Date {
        guard
          let noon = calendar.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: period.start
          )
        else {
          throw CalendarBucketScheduleError.calendarCalculationFailed
        }
        return noon
      }
    }

    private struct ExpectedGrace {
      let period: CalendarBucketPeriod
      let progress: Int
      let entries: [LogEntry]
    }

    private struct ExpectedBucketFacts: Equatable {
      let periodKey: String
      let phase: BucketPhase
      let progress: Int
      let target: Int
      let unit: String
      let isMet: Bool
      let entries: [ExpectedEntryFacts]
    }

    private struct ExpectedEntryFacts: Equatable {
      let id: PersistentIdentifier
      let uuid: UUID
      let timestamp: Date
      let amount: Int
    }
  }
#endif
