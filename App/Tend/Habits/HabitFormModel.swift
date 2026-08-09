import Foundation
import Observation
import SwiftData
import TendCore

enum HabitFormMode {
    case new
    case edit(Habit)
}

enum HabitFormField: Hashable {
    case name
    case target
    case unit
}

enum HabitFormValidationError: Error, Equatable {
    case emptyName
    case invalidTarget
    case emptyUnit
}

enum HabitFormConfigurationError: CaseIterable, Hashable {
    case unsupportedCadence
    case invalidPinnedWeekdays
    case invalidReminderTime

    var message: String {
        switch self {
        case .unsupportedCadence:
            "This habit has an unsupported stored cadence and can’t be edited."
        case .invalidPinnedWeekdays:
            "This habit has invalid stored pinned days and can’t be edited."
        case .invalidReminderTime:
            "This habit has an invalid stored reminder time and can’t be edited."
        }
    }
}

@MainActor
struct HabitFormPersistence {
    typealias Create = (
        _ fields: HabitEditableFields,
        _ cadence: HabitCadence,
        _ instant: Date,
        _ timeZone: TimeZone
    ) throws -> Habit
    typealias Update = (
        _ habit: Habit,
        _ fields: HabitEditableFields,
        _ instant: Date,
        _ timeZone: TimeZone
    ) throws -> Void

    let create: Create
    let update: Update

    static func live(context: ModelContext) -> Self {
        let operations = HabitManagementOperations(context: context)
        return Self(
            create: { fields, cadence, instant, timeZone in
                try operations.create(
                    fields: fields,
                    cadence: cadence,
                    at: instant,
                    timeZone: timeZone
                )
            },
            update: { habit, fields, instant, timeZone in
                try operations.update(
                    habit,
                    fields: fields,
                    at: instant,
                    timeZone: timeZone
                )
            }
        )
    }
}

enum HabitFormWeekday: CaseIterable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    struct LocalizedLabel {
        let weekday: HabitFormWeekday
        let short: String
        let abbreviated: String
        let accessibility: String
    }

    static func localizedLabels(calendar: Calendar, locale: Locale) -> [LocalizedLabel] {
        var calendar = calendar
        calendar.locale = locale
        let shortSymbols = calendar.veryShortStandaloneWeekdaySymbols
        let abbreviatedSymbols = calendar.shortStandaloneWeekdaySymbols
        let fullSymbols = calendar.standaloneWeekdaySymbols

        return allCases.map { weekday in
            LocalizedLabel(
                weekday: weekday,
                short: shortSymbols[weekday.calendarIndex],
                abbreviated: abbreviatedSymbols[weekday.calendarIndex],
                accessibility: fullSymbols[weekday.calendarIndex]
            )
        }
    }

    var pinnedWeekday: PinnedWeekdays {
        switch self {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }

    private var calendarIndex: Int {
        switch self {
        case .sunday: 0
        case .monday: 1
        case .tuesday: 2
        case .wednesday: 3
        case .thursday: 4
        case .friday: 5
        case .saturday: 6
        }
    }
}

enum HabitFormReminderDateAdapter {
    private static let defaultMinuteOfDay = 9 * 60
    private static let referenceDate = Date(timeIntervalSinceReferenceDate: 12 * 60 * 60)

    static func date(
        for reminderTime: ReminderTime?,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Date {
        var calendar = calendar
        calendar.timeZone = timeZone
        let minuteOfDay = reminderTime?.rawValue ?? defaultMinuteOfDay
        return calendar.startOfDay(for: referenceDate)
            .addingTimeInterval(TimeInterval(minuteOfDay * 60))
    }

    static func reminderTime(
        from date: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> ReminderTime? {
        var calendar = calendar
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }
        return ReminderTime(hour: hour, minute: minute)
    }
}

@MainActor
@Observable
final class HabitFormModel {
    let mode: HabitFormMode

    var name = ""
    private(set) var cadence: HabitCadence = .daily {
        didSet {
            if cadence == .daily {
                pinnedWeekdays = .none
            }
        }
    }
    var targetText = "1"
    var unit = "times"
    var pinnedWeekdays: PinnedWeekdays = .none
    var reminderTime: ReminderTime?
    private(set) var persistenceError: String?
    private(set) var configurationErrors: Set<HabitFormConfigurationError> = []

    private var interactedFields: Set<HabitFormField> = []
    private let sourceHadReminder: Bool
    private let reminderRefresh: ReminderRefreshSignal
    private var didRequestReminderPermission = false

    init(
        mode: HabitFormMode,
        reminderRefresh: @escaping ReminderRefreshSignal = {}
    ) {
        self.mode = mode
        self.reminderRefresh = reminderRefresh
        sourceHadReminder =
            if case .edit(let habit) = mode {
                habit.reminderMinuteOfDay != nil
            } else {
                false
            }

        guard case .edit(let habit) = mode else {
            return
        }

        name = habit.name
        targetText = String(habit.target)
        unit = habit.unit
        interactedFields.formUnion([.name, .target, .unit])

        let persistedCadence = HabitCadence(rawValue: habit.cadenceRawValue)
        if let persistedCadence {
            cadence = persistedCadence
        } else {
            configurationErrors.insert(.unsupportedCadence)
        }

        if let persistedCadence {
            if persistedCadence == .daily {
                if habit.pinnedWeekdaysRawValue != PinnedWeekdays.none.rawValue {
                    configurationErrors.insert(.invalidPinnedWeekdays)
                }
            } else if let persistedPinnedWeekdays = PinnedWeekdays(
                rawValue: habit.pinnedWeekdaysRawValue
            ) {
                pinnedWeekdays = persistedPinnedWeekdays
            } else {
                configurationErrors.insert(.invalidPinnedWeekdays)
            }
        } else if PinnedWeekdays(rawValue: habit.pinnedWeekdaysRawValue) == nil {
            configurationErrors.insert(.invalidPinnedWeekdays)
        }

        if let reminderMinuteOfDay = habit.reminderMinuteOfDay {
            if let persistedReminderTime = ReminderTime(rawValue: reminderMinuteOfDay) {
                reminderTime = persistedReminderTime
            } else {
                configurationErrors.insert(.invalidReminderTime)
            }
        }
    }

    var title: String {
        switch mode {
        case .new: "New habit"
        case .edit: "Edit habit"
        }
    }

    var cadenceDisplayName: String {
        guard !configurationErrors.contains(.unsupportedCadence) else {
            return "Unsupported cadence"
        }
        return switch cadence {
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }

    var configurationErrorMessage: String? {
        let messages = HabitFormConfigurationError.allCases
            .filter(configurationErrors.contains)
            .map(\.message)
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    var isCadenceLocked: Bool {
        if case .edit = mode {
            true
        } else {
            false
        }
    }

    var hasReminder: Bool {
        reminderTime != nil
    }

    var showsPinnedWeekdays: Bool {
        cadence == .weekly && !configurationErrors.contains(.invalidPinnedWeekdays)
    }

    var showsReminderControl: Bool {
        !configurationErrors.contains(.invalidReminderTime)
    }

    var showsUnscheduledReminderWarning: Bool {
        showsPinnedWeekdays && pinnedWeekdays == .none && hasReminder
    }

    var canSave: Bool {
        configurationErrors.isEmpty
            && validationError(for: .name) == nil
            && validationError(for: .target) == nil
            && validationError(for: .unit) == nil
    }

    func markInteracted(with field: HabitFormField) {
        interactedFields.insert(field)
    }

    func error(for field: HabitFormField) -> HabitFormValidationError? {
        guard interactedFields.contains(field) else {
            return nil
        }
        return validationError(for: field)
    }

    func selectCadence(_ cadence: HabitCadence) {
        guard !isCadenceLocked else {
            return
        }
        self.cadence = cadence
    }

    func togglePinnedWeekday(_ weekday: HabitFormWeekday) {
        guard cadence == .weekly else {
            return
        }
        pinnedWeekdays =
            PinnedWeekdays(
                rawValue: pinnedWeekdays.rawValue ^ weekday.pinnedWeekday.rawValue
            ) ?? .none
    }

    func isPinned(_ weekday: HabitFormWeekday) -> Bool {
        pinnedWeekdays.contains(weekday.pinnedWeekday)
    }

    @discardableResult
    func setReminderEnabled(_ isEnabled: Bool) -> Bool {
        let wasEnabled = reminderTime != nil
        if isEnabled {
            reminderTime = reminderTime ?? ReminderTime(hour: 9, minute: 0)
        } else {
            reminderTime = nil
        }

        guard
            isEnabled,
            !wasEnabled,
            !sourceHadReminder,
            !didRequestReminderPermission
        else {
            return false
        }
        didRequestReminderPermission = true
        return true
    }

    @discardableResult
    func enableReminder(
        requestAuthorization: @escaping ReminderAuthorizationRequest
    ) -> Task<Void, Never>? {
        guard setReminderEnabled(true) else { return nil }
        return Task {
            await requestAuthorization()
        }
    }

    func save(
        using persistence: HabitFormPersistence,
        at instant: Date,
        timeZone: TimeZone
    ) -> Habit? {
        interactedFields.formUnion([.name, .target, .unit])
        persistenceError = nil

        guard configurationErrors.isEmpty else {
            return nil
        }

        guard let fields = try? validatedFields() else {
            return nil
        }

        do {
            let savedHabit: Habit
            switch mode {
            case .new:
                savedHabit = try persistence.create(fields, cadence, instant, timeZone)
            case .edit(let habit):
                try persistence.update(habit, fields, instant, timeZone)
                savedHabit = habit
            }
            reminderRefresh()
            return savedHabit
        } catch {
            persistenceError = persistenceMessage(for: error)
            return nil
        }
    }

    func validatedFields() throws -> HabitEditableFields {
        if let error = validationError(for: .name) {
            throw error
        }
        if let error = validationError(for: .target) {
            throw error
        }
        if let error = validationError(for: .unit) {
            throw error
        }

        return HabitEditableFields(
            name: normalized(name),
            target: try target(),
            unit: normalized(unit),
            pinnedWeekdays: cadence == .daily ? .none : pinnedWeekdays,
            reminderTime: reminderTime
        )
    }

    private func validationError(for field: HabitFormField) -> HabitFormValidationError? {
        switch field {
        case .name:
            normalized(name).isEmpty ? .emptyName : nil
        case .target:
            (try? target()) == nil ? .invalidTarget : nil
        case .unit:
            normalized(unit).isEmpty ? .emptyUnit : nil
        }
    }

    private func target() throws -> Int {
        guard
            !targetText.isEmpty,
            targetText.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
            let target = Int(targetText),
            target > 0
        else {
            throw HabitFormValidationError.invalidTarget
        }
        return target
    }

    private func persistenceMessage(for error: Error) -> String {
    if let localizedError = error as? LocalizedError,
            let description = localizedError.errorDescription,
            !description.isEmpty
        {
            return description
        }
        return "We couldn’t save this habit. Your changes are still here."
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
