import Foundation
import SwiftData
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Today Journal invitation projection")
struct TodayJournalInvitationModelTests {
  @Test("entry existence alone selects invitation or complete")
  func entryExistenceSelectsInvitationOrComplete() throws {
    let day = try #require(LocalDate(rawValue: "2026-08-18"))
    let context = refreshContext(on: day)
    var entryExists = false
    var projectedDays: [LocalDate] = []
    let model = TodayModel(
      operations: TodayOperations(
        snapshot: { _, _ in self.habitSnapshot(isMet: false) },
        journalEntryExists: { projectedDay, receivedContext in
          projectedDays.append(projectedDay)
          #expect(receivedContext == context)
          return entryExists
        }
      )
    )

    model.refresh(habits: [], goals: [], journalEntries: [], context: context)
    #expect(model.journalInvitation == .invitation(day: day))

    entryExists = true
    model.refresh(habits: [], goals: [], journalEntries: [], context: context)
    #expect(model.journalInvitation == .complete)
    #expect(projectedDays == [day, day])
  }

  @Test("Journal failure is isolated from Habit Goal and All tended truth")
  func failureIsIsolatedFromDailyTruth() throws {
    let store = try makeStore()
    let habit = try insertHabit(in: store)
    let goal = try insertGoal(in: store)
    let day = try #require(LocalDate(rawValue: "2026-08-18"))
    let context = refreshContext(on: day)
    var journalFails = true
    var habitCalls = 0
    var goalCalls = 0
    let model = TodayModel(
      operations: TodayOperations(
        snapshot: { _, _ in
          habitCalls += 1
          return self.habitSnapshot(isMet: true)
        },
        goalFacts: { _, _ in
          goalCalls += 1
          return .open(self.goalFacts())
        },
        journalEntryExists: { _, _ in
          if journalFails { throw FixtureError.unavailable }
          return false
        }
      )
    )

    model.refresh(
      habits: [habit],
      goals: [goal],
      journalEntries: [],
      context: context
    )
    let unavailableDashboard = try requireDashboard(model)
    guard case .unavailable(let failure)? = model.journalInvitation else {
      Issue.record("Expected unavailable Journal invitation")
      return
    }
    #expect(failure.retryTitle == "Try again")
    let stableDailyTruth = DailyTruth(dashboard: unavailableDashboard)

    journalFails = false
    model.retryJournal(
      habits: [habit],
      goals: [goal],
      journalEntries: [],
      context: context
    )

    #expect(model.journalInvitation == .invitation(day: day))
    #expect(DailyTruth(dashboard: try requireDashboard(model)) == stableDailyTruth)
    #expect(habitCalls == 1)
    #expect(goalCalls == 1)
  }

  @Test("Journal state never changes Goal transition or Habit partitioning")
  func stateNeverChangesOtherProjectionSemantics() throws {
    let store = try makeStore()
    let habits = try [
      insertHabit(in: store, name: "Open", isMet: false),
      insertHabit(in: store, name: "Met", isMet: true),
    ]
    let goal = try insertGoal(in: store)
    let context = refreshContext(on: try #require(LocalDate(rawValue: "2026-08-18")))
    let transition = context.instant.addingTimeInterval(60)
    var entryExists = false
    let model = TodayModel(
      operations: TodayOperations(
        snapshot: { habit, _ in
          self.habitSnapshot(isMet: habit.name == "Met")
        },
        goalFacts: { _, _ in
          .open(self.goalFacts(nextTransition: transition))
        },
        journalEntryExists: { _, _ in entryExists }
      )
    )

    model.refresh(habits: habits, goals: [goal], journalEntries: [], context: context)
    let invitationTruth = DailyTruth(dashboard: try requireDashboard(model))

    entryExists = true
    model.refresh(habits: habits, goals: [goal], journalEntries: [], context: context)

    #expect(model.journalInvitation == .complete)
    #expect(DailyTruth(dashboard: try requireDashboard(model)) == invitationTruth)
    #expect(model.nextGoalTransition == transition)
  }

  private func makeStore() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func insertHabit(
    in context: ModelContext,
    name: String = "Habit",
    isMet: Bool = false
  ) throws -> Habit {
    let habit = Habit(name: name, cadence: .daily, target: 1, unit: "time")
    context.insert(habit)
    try context.save()
    return habit
  }

  private func insertGoal(in context: ModelContext) throws -> Goal {
    let goal = Goal(name: "Goal", kind: .accumulate, target: 4, unit: "times")
    context.insert(goal)
    try context.save()
    return goal
  }

  private func habitSnapshot(isMet: Bool) -> HabitTodaySnapshot {
    HabitTodaySnapshot(
      periodKey: "day:2026-08-18",
      progress: isMet ? 1 : 0,
      target: 1,
      unit: "time",
      cadence: .daily,
      currentStreak: isMet ? 1 : 0,
      isAtRisk: false,
      isMet: isMet
    )
  }

  private func goalFacts(nextTransition: Date? = nil) -> TodayGoalFacts {
    TodayGoalFacts(
      progress: .accumulate(
        AccumulateGoalProgress(
          total: 0,
          target: 4,
          unit: "times",
          normalizedProgress: 0
        )
      ),
      standing: GoalStandingSnapshot(
        standing: .behind,
        actualNormalizedProgress: 0,
        expectedNormalizedProgress: nil,
        deadlineBoundary: nil,
        nextTimeRefresh: nextTransition
      ),
      deadline: nil
    )
  }

  private func refreshContext(on day: LocalDate) -> TodayRefreshContext {
    let timeZone = TimeZone(secondsFromGMT: 0)!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return TodayRefreshContext(
      instant: (try? day.start(in: timeZone).addingTimeInterval(12 * 60 * 60)) ?? .distantPast,
      timeZone: timeZone,
      calendar: calendar,
      locale: Locale(identifier: "en_US")
    )
  }

  private func requireDashboard(_ model: TodayModel) throws -> TodayDashboardPresentation {
    guard case .dashboard(let dashboard)? = model.presentation else {
      Issue.record("Expected dashboard")
      throw FixtureError.unavailable
    }
    return dashboard
  }

  @MainActor
  private struct DailyTruth: Equatable {
    let toTendIDs: [PersistentIdentifier]
    let tendedIDs: [PersistentIdentifier]
    let goalIDs: [PersistentIdentifier]
    let fractionText: String
    let showsAllTended: Bool
    let nextGoalTransition: Date?

    init(dashboard: TodayDashboardPresentation) {
      toTendIDs = dashboard.toTendRows.map(\.id)
      tendedIDs = dashboard.tendedRows.map(\.id)
      goalIDs = dashboard.goalRows.map(\.id)
      fractionText = dashboard.fractionText
      showsAllTended = dashboard.showsAllTended
      nextGoalTransition = dashboard.nextGoalTransition
    }
  }

  private enum FixtureError: Error {
    case unavailable
  }
}
