import Foundation
import Observation
import SwiftData
import TendCore

struct HabitDetailLoadFailure: Equatable, Sendable {
    let message: String
    let retryTitle: String
}

struct HabitDetailHistoryFact: Equatable, Identifiable, Sendable {
    let key: String
    let start: Date
    let end: Date
    let state: HabitHistoryState
    let progress: Int?
    let target: Int?
    let unit: String?
    let isRequirementMet: Bool?
    let dateText: String
    let stateText: String
    let progressText: String?
    let calloutText: String
    let accessibilityLabel: String

    var id: String { key }
}

struct HabitDetailEntryFact: Equatable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let amount: Int
    let bucketKey: String
    let unit: String
    let bucketStart: Date
    let bucketEnd: Date
    let scopeText: String
    let timeText: String
    let amountText: String
    let accessibilityLabel: String
}

struct HabitDetailPresentation: Equatable, Sendable {
    let habitID: UUID
    let name: String
    let isActive: Bool
    let cadence: HabitCadence
    let requirementText: String
    let cadenceText: String
    let pinnedDaysText: String?
    let reminderText: String?
    let metadataText: String
    let currentStreak: Int
    let currentStreakText: String
    let currentStreakUnit: String
    let bestStreak: Int
    let bestStreakText: String
    let bestStreakUnit: String
    let isAtRisk: Bool
    let earliestMonth: Date
    let selectedMonth: Date
    let latestMonth: Date
    let monthTitle: String
    let history: [HabitDetailHistoryFact]
    let dailyLeadingFillerCount: Int
    let dailyTrailingFillerCount: Int
    let entries: [HabitDetailEntryFact]
}

@MainActor
struct HabitDetailOperations {
    typealias Snapshot = (
        _ habit: Habit,
        _ selectedMonth: Date,
        _ instant: Date,
        _ timeZone: TimeZone
    ) throws -> HabitDetailSnapshot

    let snapshot: Snapshot

    // Task 3 extends this boundary with mutation closures. Retaining the live
    // operation objects here keeps every detail operation on one ModelContext.
    private let logEntryOperations: LogEntryOperations?
    private let activityOperations: HabitActivityOperations?

    init(snapshot: @escaping Snapshot) {
        self.snapshot = snapshot
        logEntryOperations = nil
        activityOperations = nil
    }

    private init(
        snapshot: @escaping Snapshot,
        logEntryOperations: LogEntryOperations,
        activityOperations: HabitActivityOperations
    ) {
        self.snapshot = snapshot
        self.logEntryOperations = logEntryOperations
        self.activityOperations = activityOperations
    }

    static func live(context: ModelContext) -> Self {
        let computation = HabitDetailComputation(context: context)
        let logEntryOperations = LogEntryOperations(context: context)
        let activityOperations = HabitActivityOperations(context: context)
        return Self(
            snapshot: { habit, selectedMonth, instant, timeZone in
                try computation.snapshot(
                    for: habit,
                    selectedMonth: selectedMonth,
                    at: instant,
                    timeZone: timeZone
                )
            },
            logEntryOperations: logEntryOperations,
            activityOperations: activityOperations
        )
    }
}

@MainActor
@Observable
final class HabitDetailModel {
    let habitID: UUID
    private(set) var habitName: String
    private(set) var presentation: HabitDetailPresentation?
    private(set) var loadFailure: HabitDetailLoadFailure?
    private(set) var selectedMonth: Date?

    var canSelectPreviousMonth: Bool {
        guard let presentation else { return false }
        return !isSameMonth(presentation.selectedMonth, presentation.earliestMonth)
    }

    var canSelectNextMonth: Bool {
        guard let presentation else { return false }
        return !isSameMonth(presentation.selectedMonth, presentation.latestMonth)
    }

    var selectedHistory: HabitDetailHistoryFact? {
        guard let selectedHistoryKey else { return nil }
        return presentation?.history.first { $0.key == selectedHistoryKey }
    }

    @ObservationIgnored private let habit: Habit
    @ObservationIgnored private let operations: HabitDetailOperations
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: () -> TimeZone
    @ObservationIgnored private let calendar: () -> Calendar
    @ObservationIgnored private let locale: () -> Locale
    private var selectedHistoryKey: String?

    convenience init(
        habit: Habit,
        context: ModelContext,
        now: @escaping () -> Date = Date.init,
        timeZone: @escaping () -> TimeZone = { TimeZone.current },
        calendar: @escaping () -> Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = 2
            calendar.minimumDaysInFirstWeek = 4
            return calendar
        },
        locale: @escaping () -> Locale = { Locale.current }
    ) {
        self.init(
            habit: habit,
            operations: .live(context: context),
            now: now,
            timeZone: timeZone,
            calendar: calendar,
            locale: locale
        )
    }

    init(
        habit: Habit,
        operations: HabitDetailOperations,
        now: @escaping () -> Date,
        timeZone: @escaping () -> TimeZone,
        calendar: @escaping () -> Calendar,
        locale: @escaping () -> Locale
    ) {
        habitID = habit.id
        habitName = habit.name
        self.habit = habit
        self.operations = operations
        self.now = now
        self.timeZone = timeZone
        self.calendar = calendar
        self.locale = locale
    }

    func start() {
        let context = makeLoadContext()
        if selectedMonth == nil {
            guard let month = monthContaining(
                context.instant,
                calendar: context.calendar
            ) else {
                failLoad(locale: context.locale)
                return
            }
            selectedMonth = month
        }
        loadSelectedMonth(using: context)
    }

    func refresh() {
        guard selectedMonth != nil else {
            start()
            return
        }
        loadSelectedMonth(using: makeLoadContext())
    }

    func retryLoad() {
        guard loadFailure != nil, selectedMonth != nil else { return }
        loadSelectedMonth(using: makeLoadContext())
    }

    func selectPreviousMonth() {
        navigateMonth(by: -1)
    }

    func selectNextMonth() {
        navigateMonth(by: 1)
    }

    func selectHistory(_ key: String) {
        guard presentation?.history.contains(where: { $0.key == key }) == true else {
            selectedHistoryKey = nil
            return
        }
        selectedHistoryKey = selectedHistoryKey == key ? nil : key
    }

    func dismissHistoryCallout() {
        selectedHistoryKey = nil
    }

    func stop() {
        selectedHistoryKey = nil
    }

    private func navigateMonth(by offset: Int) {
        guard let presentation else { return }
        let context = makeLoadContext()
        let bound = offset < 0
            ? presentation.earliestMonth
            : presentation.latestMonth
        guard !context.calendar.isDate(
            presentation.selectedMonth,
            equalTo: bound,
            toGranularity: .month
        ), let requestedMonth = context.calendar.date(
            byAdding: .month,
            value: offset,
            to: presentation.selectedMonth
        ) else { return }
        selectedHistoryKey = nil
        selectedMonth = requestedMonth
        loadSelectedMonth(using: context)
    }

    private func loadSelectedMonth(using context: LoadContext) {
        guard let requestedMonth = selectedMonth else { return }

        do {
            let snapshot = try operations.snapshot(
                habit,
                requestedMonth,
                context.instant,
                context.timeZone
            )
            guard snapshot.habitID == habitID else {
                throw ProjectionError.unexpectedHabit(snapshot.habitID)
            }

            let ownerFacts = OwnerFacts(habit: habit)
            let formatter = HabitPresentationFormatter(
                calendar: context.calendar,
                locale: context.locale,
                timeZone: context.timeZone
            )
            let replacement = Self.presentation(
                snapshot: snapshot,
                ownerFacts: ownerFacts,
                calendar: context.calendar,
                locale: context.locale,
                formatter: formatter
            )

            presentation = replacement
            selectedMonth = snapshot.monthRange.selected
            habitName = ownerFacts.name
            loadFailure = nil
            if let selectedHistoryKey,
               !replacement.history.contains(where: { $0.key == selectedHistoryKey }) {
                self.selectedHistoryKey = nil
            }
        } catch {
            failLoad(locale: context.locale)
        }
    }

    private func failLoad(locale: Locale) {
        presentation = nil
        selectedHistoryKey = nil
        loadFailure = HabitDetailLoadFailure(
            message: String(
                localized: "This habit is unavailable right now.",
                locale: locale
            ),
            retryTitle: String(localized: "Try again", locale: locale)
        )
    }

    private func makeLoadContext() -> LoadContext {
        let instant = now()
        let sampledTimeZone = timeZone()
        let fixedTimeZone = TimeZone(identifier: sampledTimeZone.identifier)
            ?? sampledTimeZone
        let sampledLocale = locale()
        let fixedLocale = Locale(identifier: sampledLocale.identifier)
        let calendar = detailCalendar(
            from: self.calendar(),
            timeZone: fixedTimeZone,
            locale: fixedLocale
        )
        return LoadContext(
            instant: instant,
            timeZone: fixedTimeZone,
            calendar: calendar,
            locale: fixedLocale
        )
    }

    private func monthContaining(_ date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .month, for: date)?.start
    }

    private func isSameMonth(_ lhs: Date, _ rhs: Date) -> Bool {
        let sampledTimeZone = timeZone()
        let fixedTimeZone = TimeZone(identifier: sampledTimeZone.identifier)
            ?? sampledTimeZone
        let fixedLocale = Locale(identifier: locale().identifier)
        let calendar = detailCalendar(
            from: self.calendar(),
            timeZone: fixedTimeZone,
            locale: fixedLocale
        )
        return calendar.isDate(lhs, equalTo: rhs, toGranularity: .month)
    }

    private func detailCalendar(
        from injected: Calendar,
        timeZone: TimeZone,
        locale: Locale
    ) -> Calendar {
        var calendar = injected.identifier == .gregorian
            ? injected
            : Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }
}

private extension HabitDetailModel {
    struct LoadContext {
        let instant: Date
        let timeZone: TimeZone
        let calendar: Calendar
        let locale: Locale
    }

    struct OwnerFacts {
        let name: String
        let target: Int
        let unit: String
        let cadenceRawValue: String
        let pinnedWeekdaysRawValue: Int
        let reminderMinuteOfDay: Int?
        let isActive: Bool

        init(habit: Habit) {
            name = habit.name
            target = habit.target
            unit = habit.unit
            cadenceRawValue = habit.cadenceRawValue
            pinnedWeekdaysRawValue = habit.pinnedWeekdaysRawValue
            reminderMinuteOfDay = habit.reminderMinuteOfDay
            isActive = habit.isActive
        }
    }

    enum ProjectionError: Error {
        case unexpectedHabit(UUID)
    }

    static func presentation(
        snapshot: HabitDetailSnapshot,
        ownerFacts: OwnerFacts,
        calendar: Calendar,
        locale: Locale,
        formatter: HabitPresentationFormatter
    ) -> HabitDetailPresentation {
        let cadence = snapshot.cadence
        let requirementText = formatter.requirement(
            target: ownerFacts.target,
            unit: ownerFacts.unit
        )
        let cadenceText = formatter.cadence(
            cadence,
            fallback: ownerFacts.cadenceRawValue
        )
        let pinnedDaysText = cadence == .weekly
            ? formatter.pinnedDays(rawValue: ownerFacts.pinnedWeekdaysRawValue)
            : nil
        let cadenceAndPins = [cadenceText, pinnedDaysText]
            .compactMap { $0 }
            .joined(separator: ", ")
        let reminderText = ownerFacts.reminderMinuteOfDay.map(formatter.reminder)
        let metadataText = [requirementText, cadenceAndPins, reminderText]
            .compactMap { $0 }
            .joined(separator: " · ")
        let history = snapshot.history.map {
            historyFact(
                $0,
                cadence: cadence,
                locale: locale,
                formatter: formatter
            )
        }
        let fillerCounts = dailyFillerCounts(
            cadence: cadence,
            selectedMonth: snapshot.monthRange.selected,
            historyCount: history.count,
            calendar: calendar
        )
        let entries = snapshot.editableEntries.map {
            entryFact(
                $0,
                cadence: cadence,
                locale: locale,
                formatter: formatter
            )
        }
        let streak = snapshot.streak

        return HabitDetailPresentation(
            habitID: snapshot.habitID,
            name: ownerFacts.name,
            isActive: ownerFacts.isActive,
            cadence: cadence,
            requirementText: requirementText,
            cadenceText: cadenceText,
            pinnedDaysText: pinnedDaysText,
            reminderText: reminderText,
            metadataText: metadataText,
            currentStreak: streak.currentStreak,
            currentStreakText: formatter.streak(
                value: streak.currentStreak,
                cadence: cadence
            ),
            currentStreakUnit: formatter.streakUnit(
                value: streak.currentStreak,
                cadence: cadence
            ),
            bestStreak: streak.bestStreak,
            bestStreakText: formatter.streak(
                value: streak.bestStreak,
                cadence: cadence
            ),
            bestStreakUnit: formatter.streakUnit(
                value: streak.bestStreak,
                cadence: cadence
            ),
            isAtRisk: streak.isAtRisk,
            earliestMonth: snapshot.monthRange.earliest,
            selectedMonth: snapshot.monthRange.selected,
            latestMonth: snapshot.monthRange.latest,
            monthTitle: formatter.month(snapshot.monthRange.selected),
            history: history,
            dailyLeadingFillerCount: fillerCounts.leading,
            dailyTrailingFillerCount: fillerCounts.trailing,
            entries: entries
        )
    }

    static func historyFact(
        _ period: HabitHistoryPeriod,
        cadence: HabitCadence,
        locale: Locale,
        formatter: HabitPresentationFormatter
    ) -> HabitDetailHistoryFact {
        let dateText = cadence == .daily
            ? formatter.day(period.start)
            : formatter.week(start: period.start, endExclusive: period.end)
        let stateText = historyStateText(period.state, locale: locale)
        let standingText = period.isRequirementMet.map {
            $0
                ? String(localized: "Requirement met", locale: locale)
                : String(localized: "Requirement not met", locale: locale)
        }
        let accessibilityStandingText = period.isRequirementMet.map {
            $0
                ? String(localized: "requirement met", locale: locale)
                : String(localized: "requirement not met", locale: locale)
        }
        let progressText: String?
        if let progress = period.progress,
           let target = period.target,
           let unit = period.unit {
            let localizedProgress = progress.formatted(.number.locale(locale))
            progressText = "\(localizedProgress) of \(formatter.requirement(target: target, unit: unit))"
        } else {
            progressText = nil
        }
        let calloutText = [dateText, stateText, standingText, progressText]
            .compactMap { $0 }
            .joined(separator: " · ")
        let accessibilityLabel = [
            dateText,
            stateText,
            accessibilityStandingText,
            progressText,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")

        return HabitDetailHistoryFact(
            key: period.key,
            start: period.start,
            end: period.end,
            state: period.state,
            progress: period.progress,
            target: period.target,
            unit: period.unit,
            isRequirementMet: period.isRequirementMet,
            dateText: dateText,
            stateText: stateText,
            progressText: progressText,
            calloutText: calloutText,
            accessibilityLabel: accessibilityLabel
        )
    }

    static func entryFact(
        _ entry: HabitEditableEntry,
        cadence: HabitCadence,
        locale: Locale,
        formatter: HabitPresentationFormatter
    ) -> HabitDetailEntryFact {
        let scopeText = cadence == .daily
            ? formatter.day(entry.bucketStart)
            : formatter.week(start: entry.bucketStart, endExclusive: entry.bucketEnd)
        let timeText = formatter.time(entry.timestamp)
        let amountText = formatter.amount(entry.amount, unit: entry.unit)
        return HabitDetailEntryFact(
            id: entry.id,
            timestamp: entry.timestamp,
            amount: entry.amount,
            bucketKey: entry.bucketKey,
            unit: entry.unit,
            bucketStart: entry.bucketStart,
            bucketEnd: entry.bucketEnd,
            scopeText: scopeText,
            timeText: timeText,
            amountText: amountText,
            accessibilityLabel: [
                scopeText,
                timeText,
                amountText,
                String(localized: "Delete entry", locale: locale),
            ].joined(separator: ", ")
        )
    }

    static func dailyFillerCounts(
        cadence: HabitCadence,
        selectedMonth: Date,
        historyCount: Int,
        calendar: Calendar
    ) -> (leading: Int, trailing: Int) {
        guard cadence == .daily else { return (0, 0) }
        let weekday = calendar.component(.weekday, from: selectedMonth)
        let leading = (weekday + 5) % 7
        let trailing = (7 - ((leading + historyCount) % 7)) % 7
        return (leading, trailing)
    }

    static func historyStateText(
        _ state: HabitHistoryState,
        locale: Locale
    ) -> String {
        switch state {
        case .met:
            String(localized: "Met", locale: locale)
        case .missed:
            String(localized: "Missed", locale: locale)
        case .open:
            String(localized: "Open", locale: locale)
        case .grace:
            String(localized: "Grace", locale: locale)
        case .inactive:
            String(localized: "Inactive", locale: locale)
        case .beforeCreation:
            String(localized: "Before creation", locale: locale)
        case .future:
            String(localized: "Future", locale: locale)
        }
    }
}
