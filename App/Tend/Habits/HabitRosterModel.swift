import Foundation
import Observation
import SwiftData
import TendCore

enum HabitRosterAction: CaseIterable, Equatable {
    case edit
    case archive
    case reactivate
    case delete

    var title: String {
        switch self {
        case .edit: "Edit"
        case .archive: "Archive"
        case .reactivate: "Reactivate"
        case .delete: "Delete"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .edit: "Opens this habit for editing."
        case .archive: "Stops tracking and holds its streak."
        case .reactivate: "Resumes tracking immediately."
        case .delete: "Permanently deletes this habit and its history."
        }
    }

    var systemImage: String {
        switch self {
        case .edit: "pencil"
        case .archive: "archivebox"
        case .reactivate: "arrow.counterclockwise"
        case .delete: "trash"
        }
    }

    var isDestructive: Bool {
        self == .delete
    }
}

enum HabitRosterStreakTone: Equatable {
    case normal
    case atRisk
    case inactive
    case unavailable
}

struct HabitRosterRow: Identifiable {
    let habit: Habit
    let name: String
    let requirementText: String
    let cadenceText: String
    let pinnedDaysText: String?
    let metadataText: String
    let streakText: String
    let streakTone: HabitRosterStreakTone
    let isStreakRetryAvailable: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let availableActions: [HabitRosterAction]

    var id: PersistentIdentifier {
        habit.persistentModelID
    }
}

struct HabitRosterStreakSnapshot: Equatable {
    let currentStreak: Int
    let isAtRisk: Bool
}

@MainActor
struct HabitRosterOperations {
    typealias FetchHabits = () throws -> [Habit]
    typealias ComputeStreak = (
        _ habit: Habit,
        _ instant: Date,
        _ timeZone: TimeZone
    ) throws -> HabitRosterStreakSnapshot
    typealias LifecycleMutation = (
        _ habit: Habit,
        _ instant: Date,
        _ timeZone: TimeZone
    ) throws -> Void
    typealias Delete = (_ habit: Habit) throws -> Void

    let fetchHabits: FetchHabits
    let computeStreak: ComputeStreak
    let deactivate: LifecycleMutation
    let reactivate: LifecycleMutation
    let delete: Delete

    static func live(context: ModelContext) -> Self {
        let streakComputation = HabitStreakComputation(context: context)
        let activityOperations = HabitActivityOperations(context: context)
        let managementOperations = HabitManagementOperations(context: context)
        return Self(
            fetchHabits: {
                try context.fetch(FetchDescriptor<Habit>())
            },
            computeStreak: { habit, instant, timeZone in
                let state = try streakComputation.compute(
                    habit: habit,
                    at: instant,
                    timeZone: timeZone
                )
                return HabitRosterStreakSnapshot(
                    currentStreak: state.currentStreak,
                    isAtRisk: state.isAtRisk
                )
            },
            deactivate: { habit, instant, timeZone in
                try activityOperations.deactivate(
                    habit,
                    at: instant,
                    timeZone: timeZone
                )
            },
            reactivate: { habit, instant, timeZone in
                try activityOperations.reactivate(
                    habit,
                    at: instant,
                    timeZone: timeZone
                )
            },
            delete: { habit in
                try managementOperations.delete(habit)
            }
        )
    }
}

struct HabitRosterDeletionConfirmation: Identifiable {
    let habit: Habit
    let name: String
    let activityPeriodCount: Int
    let bucketCount: Int
    let logEntryCount: Int
    let offersArchiveAlternative: Bool

    var id: PersistentIdentifier {
        habit.persistentModelID
    }

    var title: String {
        "Delete \(name)?"
    }

    var consequenceText: String {
        let activityPeriods = Self.count(
            activityPeriodCount,
            singular: "activity period",
            plural: "activity periods"
        )
        let buckets = Self.count(bucketCount, singular: "bucket", plural: "buckets")
        let entries = Self.count(logEntryCount, singular: "log entry", plural: "log entries")
        let archivedState = offersArchiveAlternative ? "" : "\(name) is already archived. "
        return "\(archivedState)Deleting \(name) also removes \(activityPeriods), \(buckets), and \(entries). This can't be undone."
    }

    private static func count(_ value: Int, singular: String, plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }
}

struct HabitRosterOperationFailure {
    let habitID: PersistentIdentifier
    let message: String
    let retryTitle: String
}

@MainActor
@Observable
final class HabitRosterModel {
    private(set) var activeRows: [HabitRosterRow] = []
    private(set) var inactiveRows: [HabitRosterRow] = []
    private(set) var rosterErrorMessage: String?
    private(set) var operationError: HabitRosterOperationFailure?
    private(set) var mutatingHabitID: PersistentIdentifier?
    private(set) var deletionConfirmation: HabitRosterDeletionConfirmation?

    @ObservationIgnored private let operations: HabitRosterOperations
    @ObservationIgnored private var lastRefreshContext: RefreshContext?
    @ObservationIgnored private var failedMutation: MutationRequest?

    init(context: ModelContext) {
        operations = .live(context: context)
    }

    init(operations: HabitRosterOperations) {
        self.operations = operations
    }

    func refresh(
        at instant: Date,
        timeZone: TimeZone,
        calendar: Calendar,
        locale: Locale
    ) {
        _ = reload(using: RefreshContext(
            instant: instant,
            timeZone: timeZone,
            calendar: calendar,
            locale: locale
        ))
    }

    func retryRefresh() {
        guard let context = lastRefreshContext else { return }
        _ = reload(using: context)
    }

    func archive(
        _ habit: Habit,
        at instant: Date,
        timeZone: TimeZone,
        calendar: Calendar,
        locale: Locale
    ) {
        performMutation(MutationRequest(
            habit: habit,
            kind: .archive,
            refreshContext: RefreshContext(
                instant: instant,
                timeZone: timeZone,
                calendar: calendar,
                locale: locale
            )
        ))
    }

    func reactivate(
        _ habit: Habit,
        at instant: Date,
        timeZone: TimeZone,
        calendar: Calendar,
        locale: Locale
    ) {
        performMutation(MutationRequest(
            habit: habit,
            kind: .reactivate,
            refreshContext: RefreshContext(
                instant: instant,
                timeZone: timeZone,
                calendar: calendar,
                locale: locale
            )
        ))
    }

    func requestDeletion(of habit: Habit) {
        guard mutatingHabitID == nil else { return }
        operationError = nil
        failedMutation = nil
        deletionConfirmation = HabitRosterDeletionConfirmation(
            habit: habit,
            name: habit.name,
            activityPeriodCount: habit.activityPeriods?.count ?? 0,
            bucketCount: habit.buckets?.count ?? 0,
            logEntryCount: habit.entries?.count ?? 0,
            offersArchiveAlternative: habit.isActive
        )
    }

    func cancelDeletion() {
        if failedMutation?.kind == .delete {
            failedMutation = nil
            operationError = nil
        }
        deletionConfirmation = nil
    }

    func confirmDeletion(
        at instant: Date,
        timeZone: TimeZone,
        calendar: Calendar,
        locale: Locale
    ) {
        guard let deletionConfirmation else { return }
        performMutation(MutationRequest(
            habit: deletionConfirmation.habit,
            kind: .delete,
            refreshContext: RefreshContext(
                instant: instant,
                timeZone: timeZone,
                calendar: calendar,
                locale: locale
            )
        ))
    }

    func archiveInsteadOfDeleting(
        at instant: Date,
        timeZone: TimeZone,
        calendar: Calendar,
        locale: Locale
    ) {
        guard let deletionConfirmation,
              deletionConfirmation.offersArchiveAlternative
        else {
            return
        }
        archive(
            deletionConfirmation.habit,
            at: instant,
            timeZone: timeZone,
            calendar: calendar,
            locale: locale
        )
        if operationError == nil, !deletionConfirmation.habit.isActive {
            self.deletionConfirmation = nil
        }
    }

    func isMutationInFlight(for habit: Habit) -> Bool {
        mutatingHabitID == habit.persistentModelID
    }

    func retryOperation(
        at instant: Date,
        timeZone: TimeZone,
        calendar: Calendar,
        locale: Locale
    ) {
        guard let failedMutation else { return }
        let retryRequest = MutationRequest(
            habit: failedMutation.habit,
            kind: failedMutation.kind,
            refreshContext: RefreshContext(
                instant: instant,
                timeZone: timeZone,
                calendar: calendar,
                locale: locale
            )
        )
        let dismissesDeletionConfirmation = retryRequest.kind == .archive
            && deletionConfirmation?.id == retryRequest.habit.persistentModelID
        performMutation(retryRequest)
        if dismissesDeletionConfirmation, operationError == nil {
            deletionConfirmation = nil
        }
    }

    func dismissOperationError() {
        operationError = nil
        failedMutation = nil
    }

    @discardableResult
    private func reload(using context: RefreshContext) -> Bool {
        lastRefreshContext = context

        let habits: [Habit]
        do {
            habits = try operations.fetchHabits()
        } catch {
            rosterErrorMessage = Self.message(
                for: error,
                fallback: "We couldn't load your habits. Try again."
            )
            return false
        }

        var activeRows: [HabitRosterRow] = []
        var inactiveRows: [HabitRosterRow] = []
        activeRows.reserveCapacity(habits.count)
        inactiveRows.reserveCapacity(habits.count)
        for habit in habits {
            let streak = try? operations.computeStreak(
                habit,
                context.instant,
                context.timeZone
            )
            let row = HabitRosterFormatter.row(
                for: habit,
                streak: streak,
                timeZone: context.timeZone,
                calendar: context.calendar,
                locale: context.locale
            )
            if habit.isActive {
                activeRows.append(row)
            } else {
                inactiveRows.append(row)
            }
        }

        activeRows.sort {
            HabitRosterFormatter.isOrdered($0.habit, before: $1.habit, locale: context.locale)
        }
        inactiveRows.sort {
            HabitRosterFormatter.isOrdered($0.habit, before: $1.habit, locale: context.locale)
        }
        self.activeRows = activeRows
        self.inactiveRows = inactiveRows
        rosterErrorMessage = nil
        return true
    }

    private func performMutation(_ request: MutationRequest) {
        guard mutatingHabitID == nil else { return }
        let habitID = request.habit.persistentModelID
        mutatingHabitID = habitID
        operationError = nil
        defer { mutatingHabitID = nil }

        do {
            switch request.kind {
            case .archive:
                try operations.deactivate(
                    request.habit,
                    request.refreshContext.instant,
                    request.refreshContext.timeZone
                )
            case .reactivate:
                try operations.reactivate(
                    request.habit,
                    request.refreshContext.instant,
                    request.refreshContext.timeZone
                )
            case .delete:
                try operations.delete(request.habit)
            }
        } catch {
            failedMutation = request
            operationError = HabitRosterOperationFailure(
                habitID: habitID,
                message: Self.message(for: error, fallback: request.fallbackMessage),
                retryTitle: "Try again"
            )
            return
        }

        failedMutation = nil
        if request.kind == .delete {
            deletionConfirmation = nil
        }
        if !reload(using: request.refreshContext) {
            preserveSuccessfulMutation(request, habitID: habitID)
        }
    }

    private func preserveSuccessfulMutation(
        _ request: MutationRequest,
        habitID: PersistentIdentifier
    ) {
        activeRows.removeAll { $0.habit.persistentModelID == habitID }
        inactiveRows.removeAll { $0.habit.persistentModelID == habitID }
        guard request.kind != .delete else { return }

        let context = request.refreshContext
        let streak = try? operations.computeStreak(
            request.habit,
            context.instant,
            context.timeZone
        )
        let row = HabitRosterFormatter.row(
            for: request.habit,
            streak: streak,
            timeZone: context.timeZone,
            calendar: context.calendar,
            locale: context.locale
        )
        if request.habit.isActive {
            activeRows.append(row)
            activeRows.sort {
                HabitRosterFormatter.isOrdered($0.habit, before: $1.habit, locale: context.locale)
            }
        } else {
            inactiveRows.append(row)
            inactiveRows.sort {
                HabitRosterFormatter.isOrdered($0.habit, before: $1.habit, locale: context.locale)
            }
        }
    }


    private static func message(for error: Error, fallback: String) -> String {
        guard let localizedError = error as? LocalizedError,
              let description = localizedError.errorDescription,
              !description.isEmpty
        else {
            return fallback
        }
        return description
    }
}

private extension HabitRosterModel {
    struct RefreshContext {
        let instant: Date
        let timeZone: TimeZone
        let calendar: Calendar
        let locale: Locale
    }

    struct MutationRequest {
        enum Kind: Equatable {
            case archive
            case reactivate
            case delete
        }

        let habit: Habit
        let kind: Kind
        let refreshContext: RefreshContext

        var fallbackMessage: String {
            switch kind {
            case .archive:
                "We couldn't archive this habit. Nothing changed."
            case .reactivate:
                "We couldn't reactivate this habit. Nothing changed."
            case .delete:
                "We couldn't delete this habit. Nothing changed."
            }
        }
    }
}

private enum HabitRosterFormatter {
    static func row(
        for habit: Habit,
        streak: HabitRosterStreakSnapshot?,
        timeZone: TimeZone,
        calendar: Calendar,
        locale: Locale
    ) -> HabitRosterRow {
        let cadence = HabitCadence(rawValue: habit.cadenceRawValue)
        let formatter = HabitPresentationFormatter(
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let requirementText = formatter.requirement(
            target: habit.target,
            unit: habit.unit
        )
        let cadenceText = formatter.cadence(
            cadence,
            fallback: habit.cadenceRawValue
        )
        let pinnedDaysText = cadence == .weekly
            ? formatter.pinnedDays(rawValue: habit.pinnedWeekdaysRawValue)
            : nil
        let cadenceAndPins = [cadenceText, pinnedDaysText]
            .compactMap { $0 }
            .joined(separator: ", ")
        var metadataComponents = [requirementText, cadenceAndPins]
        if !habit.isActive {
            metadataComponents.append("dormant")
        }
        let streakPresentation = streakPresentation(
            streak,
            cadence: cadence,
            isActive: habit.isActive,
            formatter: formatter
        )
        let metadataText = metadataComponents.joined(separator: " · ")
        let stateText: String
        switch streakPresentation.tone {
        case .atRisk:
            stateText = "At risk"
        case .inactive:
            stateText = "Inactive"
        case .normal, .unavailable:
            stateText = "Active"
        }
        return HabitRosterRow(
            habit: habit,
            name: habit.name,
            requirementText: requirementText,
            cadenceText: cadenceText,
            pinnedDaysText: pinnedDaysText,
            metadataText: metadataText,
            streakText: streakPresentation.text,
            streakTone: streakPresentation.tone,
            isStreakRetryAvailable: streak == nil,
            accessibilityLabel: habit.name,
            accessibilityValue: "\(metadataText), \(streakPresentation.text), \(stateText)",
            availableActions: habit.isActive
                ? [.edit, .archive, .delete]
                : [.edit, .reactivate, .delete]
        )
    }

    static func isOrdered(_ lhs: Habit, before rhs: Habit, locale: Locale) -> Bool {
        let nameOrder = lhs.name.compare(
            rhs.name,
            options: [.caseInsensitive],
            range: nil,
            locale: locale
        )
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }


    private static func streakPresentation(
        _ streak: HabitRosterStreakSnapshot?,
        cadence: HabitCadence?,
        isActive: Bool,
        formatter: HabitPresentationFormatter
    ) -> (text: String, tone: HabitRosterStreakTone) {
        guard let streak, let cadence else {
            return ("Streak unavailable", .unavailable)
        }
        let value = formatter.streak(value: streak.currentStreak, cadence: cadence)
        if !isActive {
            return ("held at \(value)", .inactive)
        }
        return (value, streak.isAtRisk ? .atRisk : .normal)
    }
}
