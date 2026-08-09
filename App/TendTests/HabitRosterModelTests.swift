import Foundation
import SwiftData
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Habit roster model")
struct HabitRosterModelTests {
    @Test("zero, single-section, and mixed rosters partition every habit exactly once")
    func partitionsEveryHabitExactlyOnce() throws {
        let fixture = try HabitRosterFixture()
        let instant = try fixture.instant("2026-01-05T12:00:00Z")
        let model = HabitRosterModel(context: fixture.context)

        model.refresh(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        #expect(model.activeRows.isEmpty)
        #expect(model.inactiveRows.isEmpty)

        let firstActive = try fixture.create(name: "Walk", at: instant)
        model.refresh(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
    #expect(
      model.activeRows.map { $0.habit.persistentModelID } == [
            firstActive.persistentModelID
        ])
        #expect(model.inactiveRows.isEmpty)

        let secondActive = try fixture.create(
            name: "Read",
            cadence: .weekly,
            at: instant
        )
        let inactive = try fixture.create(name: "Garden", at: instant)
        try fixture.activity.deactivate(
            inactive,
            at: instant.addingTimeInterval(60),
            timeZone: fixture.timeZone
        )
        model.refresh(
            at: instant.addingTimeInterval(120),
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

        let activeIdentifiers = model.activeRows.map { $0.habit.persistentModelID }
        let inactiveIdentifiers = model.inactiveRows.map { $0.habit.persistentModelID }
        let allIdentifiers = activeIdentifiers + inactiveIdentifiers
        let expectedIdentifiers = Set([
            firstActive.persistentModelID,
            secondActive.persistentModelID,
            inactive.persistentModelID,
        ])

        #expect(activeIdentifiers.count == 2)
        #expect(inactiveIdentifiers == [inactive.persistentModelID])
        #expect(allIdentifiers.count == expectedIdentifiers.count)
        #expect(Set(allIdentifiers) == expectedIdentifiers)
    }

    @Test("localized case-insensitive names sort by creation time then UUID")
    func localizedOrderingUsesDocumentedTieBreakers() throws {
        let fixture = try HabitRosterFixture()
        let instant = try fixture.instant("2026-01-05T12:00:00Z")
    let firstIdentifier = try #require(
      UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        ))
    let secondIdentifier = try #require(
      UUID(
            uuidString: "00000000-0000-0000-0000-000000000002"
        ))
    let thirdIdentifier = try #require(
      UUID(
            uuidString: "00000000-0000-0000-0000-000000000003"
        ))
        let first = try fixture.create(name: "ALPHA", at: instant)
        let second = try fixture.create(name: "alpha", at: instant)
        let third = try fixture.create(
            name: "Alpha",
            at: instant.addingTimeInterval(60)
        )
        let zulu = try fixture.create(name: "Zulu", at: instant)
        first.id = firstIdentifier
        second.id = secondIdentifier
        third.id = thirdIdentifier
        try fixture.context.save()
        let model = HabitRosterModel(context: fixture.context)

        model.refresh(
            at: instant.addingTimeInterval(120),
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        let firstOrder = model.activeRows.map(\.habit.id)
        model.refresh(
            at: instant.addingTimeInterval(120),
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

    #expect(
      firstOrder == [
            firstIdentifier,
            secondIdentifier,
            thirdIdentifier,
            zulu.id,
        ])
        #expect(model.activeRows.map(\.habit.id) == firstOrder)
        #expect(model.activeRows.map(\.name) == ["ALPHA", "alpha", "Alpha", "Zulu"])
    }

    @Test("requirements, cadence, pins, and streak units follow owner locale")
    func formatsRosterFacts() throws {
        let fixture = try HabitRosterFixture()
        let instant = try fixture.instant("2026-01-05T12:00:00Z")
    let mondayAndWednesday = try #require(
      PinnedWeekdays(
            rawValue: PinnedWeekdays.monday.rawValue | PinnedWeekdays.wednesday.rawValue
        ))
        let steps = try fixture.create(
            name: "Walk",
            target: 8_000,
            unit: "steps",
            at: instant
        )
        let singular = try fixture.create(name: "Meditate", at: instant)
        let weekly = try fixture.create(
            name: "Share",
            cadence: .weekly,
            target: 2,
            unit: "posts",
            pinnedWeekdays: mondayAndWednesday,
            at: instant
        )
        let customSingular = try fixture.create(
            name: "Climb",
            target: 1,
            unit: "steps",
            at: instant
        )
        let model = HabitRosterModel(context: fixture.context)

        model.refresh(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

        let stepsRow = try #require(model.row(for: steps))
        let singularRow = try #require(model.row(for: singular))
        let weeklyRow = try #require(model.row(for: weekly))
        let customRow = try #require(model.row(for: customSingular))
        #expect(stepsRow.requirementText == "8,000 steps")
        #expect(stepsRow.metadataText == "8,000 steps · Daily")
        #expect(stepsRow.streakText == "0 days")
        #expect(singularRow.requirementText == "1 time")
        #expect(customRow.requirementText == "1 steps")
        #expect(weeklyRow.cadenceText == "Weekly")
        #expect(weeklyRow.pinnedDaysText == "Mon, Wed")
        #expect(weeklyRow.metadataText == "2 posts · Weekly, Mon, Wed")
        #expect(weeklyRow.streakText == "0 weeks")
    }

    @Test("large streak values preserve raw roster interpolation")
    func largeStreakValuesRemainUngrouped() throws {
        let fixture = try HabitRosterFixture()
        let instant = try fixture.instant("2026-01-05T12:00:00Z")
        let habit = try fixture.create(name: "Long streak", at: instant)
    let model = HabitRosterModel(
      operations: HabitRosterOperations(
            fetchHabits: { [habit] },
            computeStreak: { _, _, _ in
                HabitRosterStreakSnapshot(currentStreak: 1_000, isAtRisk: false)
            },
            deactivate: { _, _, _ in },
            reactivate: { _, _, _ in },
            delete: { _ in }
        ))

        model.refresh(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

        #expect(try #require(model.row(for: habit)).streakText == "1000 days")
    }

    @Test("active, at-risk, inactive, and unavailable streaks remain truthful per row")
    func projectsTruthfulStreakStates() throws {
        let fixture = try HabitRosterFixture()
        let createdAt = try fixture.instant("2026-01-01T10:00:00Z")
        let firstLogAt = try fixture.instant("2026-01-01T11:00:00Z")
        let secondLogAt = try fixture.instant("2026-01-02T10:00:00Z")
        let actionAt = try fixture.instant("2026-01-03T00:00:00Z")
        let refreshAt = try fixture.instant("2026-01-03T12:00:00Z")
        let active = try fixture.create(name: "Active", at: createdAt)
        let atRisk = try fixture.create(name: "At risk", at: createdAt)
        let inactive = try fixture.create(name: "Inactive", at: createdAt)
        let unavailable = try fixture.create(name: "Unavailable", at: createdAt)
        for habit in [active, atRisk, inactive] {
            try fixture.log.append(
                amount: 1,
                to: habit,
                at: firstLogAt,
                timeZone: fixture.timeZone
            )
        }
        try fixture.log.append(
            amount: 1,
            to: active,
            at: secondLogAt,
            timeZone: fixture.timeZone
        )
        try fixture.activity.deactivate(
            inactive,
            at: actionAt,
            timeZone: fixture.timeZone
        )
        unavailable.target = 0
        try fixture.context.save()
        let model = HabitRosterModel(context: fixture.context)

        model.refresh(
            at: refreshAt,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

        let activeRow = try #require(model.row(for: active))
        let atRiskRow = try #require(model.row(for: atRisk))
        let inactiveRow = try #require(model.row(for: inactive))
        let unavailableRow = try #require(model.row(for: unavailable))
        #expect(activeRow.streakText == "2 days")
        #expect(activeRow.streakTone == .normal)
        #expect(atRiskRow.streakText == "1 day")
        #expect(atRiskRow.streakTone == .atRisk)
        #expect(inactiveRow.streakText == "held at 1 day")
        #expect(inactiveRow.streakTone == .inactive)
        #expect(unavailableRow.streakText == "Streak unavailable")
        #expect(unavailableRow.streakTone == .unavailable)
        #expect(unavailableRow.isStreakRetryAvailable)
        #expect(model.activeRows.count == 3)
        #expect(model.inactiveRows.count == 1)
    }

    @Test("a new local-day tick recomputes every streak from the supplied instant")
    func localDayTickRecomputesStreaks() throws {
        let fixture = try HabitRosterFixture()
        let firstInstant = try fixture.instant("2026-03-08T04:59:59Z")
        let nextLocalDay = try fixture.instant("2026-03-08T05:00:00Z")
        let habit = Habit(name: "Walk", cadence: .daily, target: 1)
        var requestedInstants: [Date] = []
        let operations = HabitRosterOperations(
            fetchHabits: { [habit] },
            computeStreak: { _, instant, _ in
                requestedInstants.append(instant)
                return HabitRosterStreakSnapshot(
                    currentStreak: instant < nextLocalDay ? 4 : 5,
                    isAtRisk: false
                )
            },
            deactivate: { _, _, _ in },
            reactivate: { _, _, _ in },
            delete: { _ in }
        )
        let model = HabitRosterModel(operations: operations)

        model.refresh(
            at: firstInstant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        #expect(model.activeRows.first?.streakText == "4 days")

        model.refresh(
            at: nextLocalDay,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        #expect(model.activeRows.first?.streakText == "5 days")
        #expect(requestedInstants == [firstInstant, nextLocalDay])
    }

    @Test("successful create and edit completions are visible on the next refresh")
    func successfulFormCompletionsRefreshRoster() throws {
        let fixture = try HabitRosterFixture()
        let instant = try fixture.instant("2026-01-05T12:00:00Z")
        let model = HabitRosterModel(context: fixture.context)
        model.refresh(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        #expect(model.activeRows.isEmpty)

        let habit = try fixture.create(name: "Seedlings", at: instant)
        model.refresh(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        #expect(model.activeRows.map(\.name) == ["Seedlings"])
        let persistedIdentifier = habit.persistentModelID

        try fixture.management.update(
            habit,
            fields: HabitEditableFields(
                name: "Garden",
                target: 2,
                unit: "beds",
                pinnedWeekdays: .none
            ),
            at: instant.addingTimeInterval(60),
            timeZone: fixture.timeZone
        )
        model.refresh(
            at: instant.addingTimeInterval(60),
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

        #expect(model.activeRows.count == 1)
        #expect(model.activeRows.first?.habit.persistentModelID == persistedIdentifier)
        #expect(model.activeRows.first?.name == "Garden")
        #expect(model.activeRows.first?.metadataText == "2 beds · Daily")
    }

    @Test("archive and reactivate use the live lifecycle boundary and preserve identity")
    func archiveAndReactivateThroughLiveBoundary() throws {
        let fixture = try HabitRosterFixture()
        let instant = try fixture.instant("2026-01-05T12:00:00Z")
        let habit = try fixture.create(name: "Garden", at: instant)
        let identifier = habit.persistentModelID
        let model = HabitRosterModel(context: fixture.context)
        model.refresh(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

        model.archive(
            habit,
            at: instant.addingTimeInterval(60),
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        #expect(!habit.isActive)
        #expect(model.activeRows.isEmpty)
        #expect(model.inactiveRows.map { $0.habit.persistentModelID } == [identifier])
        #expect(model.operationError == nil)

        model.reactivate(
            habit,
            at: instant.addingTimeInterval(120),
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        #expect(habit.isActive)
        #expect(model.activeRows.map { $0.habit.persistentModelID } == [identifier])
        #expect(model.inactiveRows.isEmpty)
        #expect(model.operationError == nil)
    }

    @Test("an in-flight lifecycle mutation refuses duplicate dispatch")
    func lifecycleMutationRefusesDuplicateDispatch() throws {
        let fixture = try HabitRosterFixture()
        let instant = try fixture.instant("2026-01-05T12:00:00Z")
        let habit = Habit(name: "Garden", cadence: .daily, target: 1)
        var deactivateCallCount = 0
        var model: HabitRosterModel!
        let operations = HabitRosterOperations(
            fetchHabits: { [habit] },
            computeStreak: { _, _, _ in
                HabitRosterStreakSnapshot(currentStreak: 0, isAtRisk: false)
            },
            deactivate: { habit, mutationInstant, timeZone in
                deactivateCallCount += 1
                model.archive(
                    habit,
                    at: mutationInstant,
                    timeZone: timeZone,
                    calendar: fixture.calendar,
                    locale: fixture.locale
                )
                habit.isActive = false
            },
            reactivate: { _, _, _ in },
            delete: { _ in }
        )
        model = HabitRosterModel(operations: operations)
        model.refresh(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

        model.archive(
            habit,
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

        #expect(deactivateCallCount == 1)
        #expect(model.inactiveRows.count == 1)
        #expect(!model.isMutationInFlight(for: habit))
    }

    @Test("failed lifecycle mutation preserves state and retries at the current boundary")
    func failedLifecycleMutationPreservesStateAndRetries() throws {
        let fixture = try HabitRosterFixture()
        let instant = try fixture.instant("2026-01-05T12:00:00Z")
        let retryInstant = try fixture.instant("2026-01-06T12:00:00Z")
        let retryTimeZone = try #require(TimeZone(identifier: "Pacific/Honolulu"))
        var retryCalendar = fixture.calendar
        retryCalendar.timeZone = retryTimeZone
        let retryLocale = Locale(identifier: "en_GB")
        let habit = Habit(name: "Garden", cadence: .daily, target: 1)
        var requestedInstants: [Date] = []
        var requestedTimeZones: [TimeZone] = []
        let operations = HabitRosterOperations(
            fetchHabits: { [habit] },
            computeStreak: { _, _, _ in
                HabitRosterStreakSnapshot(currentStreak: 0, isAtRisk: false)
            },
            deactivate: { habit, instant, timeZone in
                requestedInstants.append(instant)
                requestedTimeZones.append(timeZone)
                if requestedInstants.count == 1 {
                    throw HabitRosterTestError.stillRooted
                }
                habit.isActive = false
            },
            reactivate: { _, _, _ in },
            delete: { _ in }
        )
        let model = HabitRosterModel(operations: operations)
        model.refresh(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

        model.archive(
            habit,
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        #expect(habit.isActive)
        #expect(model.activeRows.count == 1)
        #expect(model.inactiveRows.isEmpty)
        #expect(model.operationError?.message == "The roots are still holding.")
        #expect(model.operationError?.retryTitle == "Try again")

        model.retryOperation(
            at: retryInstant,
            timeZone: retryTimeZone,
            calendar: retryCalendar,
            locale: retryLocale
        )
        #expect(!habit.isActive)
        #expect(model.activeRows.isEmpty)
        #expect(model.inactiveRows.count == 1)
        #expect(model.operationError == nil)
        #expect(requestedInstants == [instant, retryInstant])
    #expect(
      requestedTimeZones.map(\.identifier) == [
            fixture.timeZone.identifier,
            retryTimeZone.identifier,
        ])
    }

    @Test(
        "successful mutations keep the visible roster truthful when reconciliation cannot load",
        arguments: HabitRosterMutationScenario.allCases
    )
    func successfulMutationSurvivesRefreshFailure(
        _ scenario: HabitRosterMutationScenario
    ) throws {
        let fixture = try HabitRosterFixture()
        let instant = try fixture.instant("2026-01-05T12:00:00Z")
        let habit = Habit(name: "Garden", cadence: .daily, target: 1)
        habit.isActive = scenario != .reactivate
        var fetchCallCount = 0
    var reminderRefreshCount = 0
        let operations = HabitRosterOperations(
            fetchHabits: {
                fetchCallCount += 1
                if fetchCallCount > 1 {
                    throw HabitRosterTestError.stillRooted
                }
                return [habit]
            },
            computeStreak: { _, _, _ in
                HabitRosterStreakSnapshot(currentStreak: 2, isAtRisk: false)
            },
            deactivate: { habit, _, _ in
                habit.isActive = false
            },
            reactivate: { habit, _, _ in
                habit.isActive = true
            },
            delete: { _ in }
        )
    let model = HabitRosterModel(
      operations: operations,
      reminderRefresh: { reminderRefreshCount += 1 }
    )
        model.refresh(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

        switch scenario {
        case .archive:
            model.archive(
                habit,
                at: instant,
                timeZone: fixture.timeZone,
                calendar: fixture.calendar,
                locale: fixture.locale
            )
        case .reactivate:
            model.reactivate(
                habit,
                at: instant,
                timeZone: fixture.timeZone,
                calendar: fixture.calendar,
                locale: fixture.locale
            )
        case .delete:
            model.requestDeletion(of: habit)
            model.confirmDeletion(
                at: instant,
                timeZone: fixture.timeZone,
                calendar: fixture.calendar,
                locale: fixture.locale
            )
        }

        #expect(model.rosterErrorMessage == "The roots are still holding.")
        #expect(fetchCallCount == 2)
    #expect(reminderRefreshCount == 1)
        switch scenario {
        case .archive:
            #expect(model.activeRows.isEmpty)
            #expect(model.inactiveRows.map(\.habit) == [habit])
        case .reactivate:
            #expect(model.activeRows.map(\.habit) == [habit])
            #expect(model.inactiveRows.isEmpty)
        case .delete:
            #expect(model.activeRows.isEmpty)
            #expect(model.inactiveRows.isEmpty)
            #expect(model.deletionConfirmation == nil)
        }
    }

    @Test("deletion confirms consequences, offers archive, and cascades only after confirmation")
    func deletionConfirmationArchiveAlternativeAndCascade() throws {
        let fixture = try HabitRosterFixture()
        let instant = try fixture.instant("2026-01-05T12:00:00Z")
        let habit = try fixture.create(name: "Garden", at: instant)
        try fixture.log.append(
            amount: 1,
            to: habit,
            at: instant.addingTimeInterval(30),
            timeZone: fixture.timeZone
        )
        let model = HabitRosterModel(context: fixture.context)
        model.refresh(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

        model.requestDeletion(of: habit)
        #expect(model.deletionConfirmation?.offersArchiveAlternative == true)
        #expect(
            model.deletionConfirmation?.consequenceText
                == "Deleting Garden also removes 1 activity period, 1 bucket, and 1 log entry. This can't be undone."
        )

        model.cancelDeletion()
        #expect(model.deletionConfirmation == nil)
        #expect(try fixture.context.fetch(FetchDescriptor<Habit>()).count == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<HabitActivityPeriod>()).count == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<HabitBucket>()).count == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<LogEntry>()).count == 1)

        model.requestDeletion(of: habit)
        model.archiveInsteadOfDeleting(
            at: instant.addingTimeInterval(60),
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        #expect(model.deletionConfirmation == nil)
        #expect(!habit.isActive)
        #expect(model.inactiveRows.count == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<LogEntry>()).count == 1)

        model.requestDeletion(of: habit)
        #expect(model.deletionConfirmation?.offersArchiveAlternative == false)
        #expect(
            model.deletionConfirmation?.consequenceText
                == "Garden is already archived. Deleting Garden also removes 1 activity period, 1 bucket, and 1 log entry. This can't be undone."
        )
        model.confirmDeletion(
            at: instant.addingTimeInterval(120),
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

        #expect(model.deletionConfirmation == nil)
        #expect(model.activeRows.isEmpty)
        #expect(model.inactiveRows.isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<Habit>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<HabitActivityPeriod>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<HabitBucket>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<LogEntry>()).isEmpty)
    }

    @Test("failed confirmed deletion keeps the graph and retries without another prompt")
    func failedConfirmedDeletionPreservesGraphAndRetries() throws {
        let fixture = try HabitRosterFixture()
        let instant = try fixture.instant("2026-01-05T12:00:00Z")
        let habit = Habit(name: "Garden", cadence: .daily, target: 1)
        var isDeleted = false
        var deleteCallCount = 0
    var reminderRefreshCount = 0
        let operations = HabitRosterOperations(
            fetchHabits: { isDeleted ? [] : [habit] },
            computeStreak: { _, _, _ in
                HabitRosterStreakSnapshot(currentStreak: 0, isAtRisk: false)
            },
            deactivate: { _, _, _ in },
            reactivate: { _, _, _ in },
            delete: { _ in
                deleteCallCount += 1
                if deleteCallCount == 1 {
                    throw HabitRosterTestError.stillRooted
                }
                isDeleted = true
            }
        )
    let model = HabitRosterModel(
      operations: operations,
      reminderRefresh: { reminderRefreshCount += 1 }
    )
        model.refresh(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        model.requestDeletion(of: habit)

        model.confirmDeletion(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        #expect(model.deletionConfirmation != nil)
        #expect(model.activeRows.count == 1)
        #expect(model.operationError?.message == "The roots are still holding.")
        #expect(deleteCallCount == 1)
    #expect(reminderRefreshCount == 0)

        model.retryOperation(
            at: instant.addingTimeInterval(60),
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        #expect(model.deletionConfirmation == nil)
        #expect(model.activeRows.isEmpty)
        #expect(model.operationError == nil)
        #expect(deleteCallCount == 2)
    #expect(reminderRefreshCount == 1)
    }

    @Test("failed archive alternative retry dismisses confirmation after success")
    func failedArchiveAlternativeRetryDismissesConfirmation() throws {
        let fixture = try HabitRosterFixture()
        let instant = try fixture.instant("2026-01-05T12:00:00Z")
        let habit = Habit(name: "Garden", cadence: .daily, target: 1)
        var deactivateCallCount = 0
        let operations = HabitRosterOperations(
            fetchHabits: { [habit] },
            computeStreak: { _, _, _ in
                HabitRosterStreakSnapshot(currentStreak: 0, isAtRisk: false)
            },
            deactivate: { habit, _, _ in
                deactivateCallCount += 1
                if deactivateCallCount == 1 {
                    throw HabitRosterTestError.stillRooted
                }
                habit.isActive = false
            },
            reactivate: { _, _, _ in },
            delete: { _ in }
        )
        let model = HabitRosterModel(operations: operations)
        model.refresh(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        model.requestDeletion(of: habit)

        model.archiveInsteadOfDeleting(
            at: instant,
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        #expect(model.deletionConfirmation != nil)
        #expect(model.operationError != nil)

        model.retryOperation(
            at: instant.addingTimeInterval(60),
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )
        #expect(model.deletionConfirmation == nil)
        #expect(model.operationError == nil)
        #expect(model.inactiveRows.count == 1)
        #expect(deactivateCallCount == 2)
    }

    @Test("rows expose complete labels, values, and non-swipe action metadata")
    func rowsExposeAccessibleActionMetadata() throws {
        let fixture = try HabitRosterFixture()
        let instant = try fixture.instant("2026-01-05T12:00:00Z")
        let active = try fixture.create(name: "Garden", at: instant)
        let inactive = try fixture.create(name: "Read", at: instant)
        try fixture.activity.deactivate(
            inactive,
            at: instant.addingTimeInterval(60),
            timeZone: fixture.timeZone
        )
        let model = HabitRosterModel(context: fixture.context)
        model.refresh(
            at: instant.addingTimeInterval(120),
            timeZone: fixture.timeZone,
            calendar: fixture.calendar,
            locale: fixture.locale
        )

        let activeRow = try #require(model.row(for: active))
        let inactiveRow = try #require(model.row(for: inactive))
        #expect(activeRow.accessibilityLabel == "Garden")
        #expect(activeRow.accessibilityValue == "1 time · Daily, 0 days, Active")
        #expect(activeRow.availableActions == [.edit, .archive, .delete])
        #expect(inactiveRow.accessibilityLabel == "Read")
        #expect(inactiveRow.accessibilityValue == "1 time · Daily · dormant, held at 0 days, Inactive")
        #expect(inactiveRow.availableActions == [.edit, .reactivate, .delete])
        #expect(HabitRosterAction.edit.accessibilityHint == "Opens this habit for editing.")
        #expect(HabitRosterAction.archive.accessibilityHint == "Stops tracking and holds its streak.")
        #expect(HabitRosterAction.reactivate.accessibilityHint == "Resumes tracking immediately.")
        #expect(
            HabitRosterAction.delete.accessibilityHint
                == "Permanently deletes this habit and its history."
        )
        #expect(HabitRosterAction.delete.isDestructive)
        #expect(!HabitRosterAction.archive.isDestructive)
    }
}

@MainActor
private struct HabitRosterFixture {
    let container: ModelContainer
    let context: ModelContext
    let management: HabitManagementOperations
    let activity: HabitActivityOperations
    let log: LogEntryOperations
    let timeZone: TimeZone
    let calendar: Calendar
    let locale: Locale

    init() throws {
        container = try TendModelContainer.inMemory()
        context = container.mainContext
        management = HabitManagementOperations(context: context)
        activity = HabitActivityOperations(context: context)
        log = LogEntryOperations(context: context)
        timeZone = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US")
        self.calendar = calendar
        locale = Locale(identifier: "en_US")
    }

    func create(
        name: String,
        cadence: HabitCadence = .daily,
        target: Int = 1,
        unit: String = "times",
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

    func instant(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}

enum HabitRosterMutationScenario: CaseIterable {
    case archive
    case reactivate
    case delete
}

private enum HabitRosterTestError: LocalizedError {
    case stillRooted

    var errorDescription: String? {
        "The roots are still holding."
    }
}

extension HabitRosterModel {
  fileprivate func row(for habit: Habit) -> HabitRosterRow? {
        (activeRows + inactiveRows).first {
            $0.habit.persistentModelID == habit.persistentModelID
        }
    }
}
