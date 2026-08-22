import Foundation
import SwiftData
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Today Journal atomic refresh")
struct TodayJournalRefreshTests {
  @Test("real create and delete mutations remove and restore today's invitation")
  func realMutationsReplaceInvitation() throws {
    let store = try makeStore()
    let today = try #require(LocalDate(rawValue: "2026-08-18"))
    let yesterday = try today.previous()
    let context = refreshContext(on: today)
    let model = TodayModel(context: store)

    refresh(model, store: store, context: context)
    #expect(model.journalInvitation == .invitation(day: today))

    _ = try insertEntry(in: store, day: yesterday, body: "Older page")
    refresh(model, store: store, context: context)
    #expect(model.journalInvitation == .invitation(day: today))

    let todayEntry = try insertEntry(in: store, day: today, body: "")
    refresh(model, store: store, context: context)
    #expect(model.journalInvitation == .complete)

    store.delete(todayEntry)
    try store.save()
    refresh(model, store: store, context: context)
    #expect(model.journalInvitation == .invitation(day: today))

    refresh(model, store: store, context: context)
    #expect(model.journalInvitation == .invitation(day: today))
    #expect(!store.hasChanges)
  }

  @Test("malformed and duplicate Journal days remain one isolated unavailable state")
  func malformedAndDuplicateDaysAreUnavailable() throws {
    let store = try makeStore()
    let today = try #require(LocalDate(rawValue: "2026-08-18"))
    let context = refreshContext(on: today)
    let model = TodayModel(context: store)
    let malformed = try insertEntry(in: store, day: today, body: "Malformed")
    malformed.dayKey = "not-a-day"
    try store.save()

    refresh(model, store: store, context: context)
    guard case .unavailable? = model.journalInvitation else {
      Issue.record("Expected malformed Journal data to be unavailable")
      return
    }

    store.delete(malformed)
    try store.save()
    _ = try insertEntry(in: store, day: today, body: "First")
    _ = try insertEntry(in: store, day: today, body: "Second")

    refresh(model, store: store, context: context)
    guard case .unavailable(let failure)? = model.journalInvitation else {
      Issue.record("Expected duplicate Journal data to be unavailable")
      return
    }
    #expect(failure.retryTitle == "Try again")
  }

  @Test("the same instant uses the owner time zone's current local day")
  func ownerTimeZoneControlsEligibility() throws {
    let store = try makeStore()
    let august18 = try #require(LocalDate(rawValue: "2026-08-18"))
    let august19 = try #require(LocalDate(rawValue: "2026-08-19"))
    _ = try insertEntry(in: store, day: august18, body: "Pacific page")
    let instant = try self.instant("2026-08-19T00:30:00Z")
    let model = TodayModel(context: store)

    refresh(
      model,
      store: store,
      context: refreshContext(instant: instant, timeZone: "UTC")
    )
    #expect(model.journalInvitation == .invitation(day: august19))

    refresh(
      model,
      store: store,
      context: refreshContext(instant: instant, timeZone: "America/Los_Angeles")
    )
    #expect(model.journalInvitation == .complete)
  }

  @Test("retry deduplicates repeated identities and refreshes changed graphs atomically")
  func retryFingerprintingIsIdentitySafe() throws {
    let store = try makeStore()
    let habit = try insertHabit(in: store)
    let today = try #require(LocalDate(rawValue: "2026-08-18"))
    let older = try insertEntry(
      in: store,
      day: try today.previous(),
      body: "Older"
    )
    let context = refreshContext(on: today)
    var journalFails = true
    var habitCalls = 0
    var journalCalls = 0
    let model = TodayModel(
      operations: TodayOperations(
        snapshot: { _, _ in
          habitCalls += 1
          return self.habitSnapshot()
        },
        journalEntryExists: { projectedDay, receivedContext in
          journalCalls += 1
          #expect(projectedDay == today)
          #expect(receivedContext == context)
          if journalFails { throw FixtureError.unavailable }
          return false
        }
      )
    )

    model.refresh(
      habits: [habit],
      goals: [],
      journalEntries: [older],
      context: context
    )
    guard case .unavailable? = model.journalInvitation else {
      Issue.record("Expected initial unavailable Journal state")
      return
    }

    journalFails = false
    model.retryJournal(
      habits: [habit],
      goals: [],
      journalEntries: [older, older],
      context: context
    )
    #expect(model.journalInvitation == .invitation(day: today))
    #expect(habitCalls == 1)
    #expect(journalCalls == 2)

    journalFails = true
    model.refresh(
      habits: [habit],
      goals: [],
      journalEntries: [older],
      context: context
    )
    let another = try insertEntry(
      in: store,
      day: try olderDay(before: today),
      body: "Oldest"
    )
    journalFails = false
    model.retryJournal(
      habits: [habit],
      goals: [],
      journalEntries: [older, another],
      context: context
    )
    #expect(model.journalInvitation == .invitation(day: today))
    #expect(habitCalls == 3)
    #expect(journalCalls == 4)
  }

  @Test("Habit retry refreshes after a live Journal graph mutation")
  func habitRetryUsesLiveJournalGraph() throws {
    let store = try makeStore()
    let habit = try insertHabit(in: store)
    let today = try #require(LocalDate(rawValue: "2026-08-18"))
    let context = refreshContext(on: today)
    let query = JournalEntryQuery(context: store)
    var habitFails = true
    var habitCalls = 0
    let model = TodayModel(
      operations: TodayOperations(
        snapshot: { _, _ in
          habitCalls += 1
          if habitFails { throw FixtureError.unavailable }
          return self.habitSnapshot()
        },
        journalEntryExists: { day, _ in
          try query.entry(on: day) != nil
        }
      )
    )
    model.refresh(
      habits: [habit],
      goals: [],
      journalEntries: [],
      context: context
    )

    _ = try insertEntry(in: store, day: today, body: "Created elsewhere")
    habitFails = false
    model.retry(
      habitID: habit.persistentModelID,
      habits: [habit],
      journalEntries: entries(in: store),
      context: context
    )

    #expect(model.journalInvitation == .complete)
    #expect(habitCalls == 2)
  }

  @Test("Goal retry refreshes after a live Journal graph mutation")
  func goalRetryUsesLiveJournalGraph() throws {
    let store = try makeStore()
    let goal = try insertGoal(in: store)
    let today = try #require(LocalDate(rawValue: "2026-08-18"))
    let context = refreshContext(on: today)
    let query = JournalEntryQuery(context: store)
    var goalFails = true
    var goalCalls = 0
    let model = TodayModel(
      operations: TodayOperations(
        snapshot: { _, _ in self.habitSnapshot() },
        goalFacts: { _, _ in
          goalCalls += 1
          if goalFails { throw FixtureError.unavailable }
          return .open(self.goalFacts())
        },
        journalEntryExists: { day, _ in
          try query.entry(on: day) != nil
        }
      )
    )
    model.refresh(
      habits: [],
      goals: [goal],
      journalEntries: [],
      context: context
    )

    _ = try insertEntry(in: store, day: today, body: "Created elsewhere")
    goalFails = false
    model.retry(
      goalID: goal.persistentModelID,
      habits: [],
      goals: [goal],
      journalEntries: entries(in: store),
      context: context
    )

    #expect(model.journalInvitation == .complete)
    #expect(goalCalls == 2)
  }

  private func refresh(
    _ model: TodayModel,
    store: ModelContext,
    context: TodayRefreshContext
  ) {
    model.refresh(
      habits: [],
      goals: [],
      journalEntries: entries(in: store),
      context: context
    )
  }

  private func entries(in context: ModelContext) -> [JournalEntry] {
    (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []
  }

  private func makeStore() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func insertEntry(
    in context: ModelContext,
    day: LocalDate,
    body: String
  ) throws -> JournalEntry {
    let instant = try day.start(in: TimeZone(secondsFromGMT: 0)!)
    let entry = JournalEntry(
      day: day,
      body: body,
      createdAt: instant,
      editedAt: instant
    )
    context.insert(entry)
    try context.save()
    return entry
  }

  private func insertGoal(in context: ModelContext) throws -> Goal {
    let goal = Goal(name: "Goal", kind: .accumulate, target: 4, unit: "times")
    context.insert(goal)
    try context.save()
    return goal
  }

  private func goalFacts() -> TodayGoalFacts {
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
        nextTimeRefresh: nil
      ),
      deadline: nil
    )
  }

  private func insertHabit(in context: ModelContext) throws -> Habit {
    let habit = Habit(name: "Habit", cadence: .daily, target: 1, unit: "time")
    context.insert(habit)
    try context.save()
    return habit
  }

  private func habitSnapshot() -> HabitTodaySnapshot {
    HabitTodaySnapshot(
      periodKey: "day:2026-08-18",
      progress: 0,
      target: 1,
      unit: "time",
      cadence: .daily,
      currentStreak: 0,
      isAtRisk: false,
      isMet: false
    )
  }

  private func refreshContext(on day: LocalDate) -> TodayRefreshContext {
    let timeZone = TimeZone(secondsFromGMT: 0)!
    return refreshContext(
      instant: (try? day.start(in: timeZone).addingTimeInterval(12 * 60 * 60)) ?? .distantPast,
      timeZone: timeZone.identifier
    )
  }

  private func refreshContext(
    instant: Date,
    timeZone identifier: String
  ) -> TodayRefreshContext {
    let timeZone = TimeZone(identifier: identifier)!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return TodayRefreshContext(
      instant: instant,
      timeZone: timeZone,
      calendar: calendar,
      locale: Locale(identifier: "en_US")
    )
  }

  private func olderDay(before today: LocalDate) throws -> LocalDate {
    try today.previous().previous()
  }

  private func instant(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    return try #require(formatter.date(from: value))
  }

  private enum FixtureError: Error {
    case unavailable
  }
}
