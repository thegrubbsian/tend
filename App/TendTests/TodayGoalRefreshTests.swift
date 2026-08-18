import Foundation
import SwiftData
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Today Goal atomic refresh")
struct TodayGoalRefreshTests {
  @Test("query mutation closure reopening and deletion replace one complete generation")
  func queryAndLifecycleMutationsReplaceGeneration() throws {
    let store = try makeStore()
    let due = try #require(GoalDate(rawValue: "2026-08-20"))
    let first = try insertGoal(in: store, name: "First", deadline: due)
    let second = try insertGoal(in: store, name: "Second", deadline: due)
    let model = makeModel { goal, _ in
      if let closure = try goal.checkedClosure { return .closed(closure) }
      return .open(self.facts(standing: .behind, deadline: goalDate(goal)))
    }
    let context = refreshContext(on: try #require(GoalDate(rawValue: "2026-08-18")))

    model.refresh(habits: [], goals: [first], context: context)
    #expect(model.goalRows.map(\.name) == ["First"])

    model.refresh(habits: [], goals: [first, second], context: context)
    #expect(Set(model.goalRows.map(\.name)) == Set(["First", "Second"]))

    first.closureRawValue = GoalClosure.harvested.rawValue
    try store.save()
    model.refresh(habits: [], goals: [first, second], context: context)
    #expect(model.goalRows.map(\.name) == ["Second"])

    first.closureRawValue = nil
    try store.save()
    model.refresh(habits: [], goals: [first, second], context: context)
    #expect(Set(model.goalRows.map(\.name)) == Set(["First", "Second"]))

    model.refresh(habits: [], goals: [first], context: context)
    #expect(model.goalRows.map(\.name) == ["First"])
  }

  @Test("scene environment day and transition refreshes use fresh contexts")
  func refreshTriggersUseFreshContextsAndEligibility() throws {
    let store = try makeStore()
    let distantDue = try #require(GoalDate(rawValue: "2026-09-01"))
    let nearDue = try #require(GoalDate(rawValue: "2026-08-20"))
    let changing = try insertGoal(in: store, name: "Changing", deadline: distantDue)
    let near = try insertGoal(in: store, name: "Near", deadline: nearDue)
    let scene = refreshContext(on: try #require(GoalDate(rawValue: "2026-08-18")))
    let environment = refreshContext(
      on: try #require(GoalDate(rawValue: "2026-08-18")),
      timeZone: "America/Los_Angeles", locale: "sv_SE"
    )
    let nextDay = refreshContext(
      on: try #require(GoalDate(rawValue: "2026-08-19")),
      timeZone: "America/Los_Angeles", locale: "sv_SE"
    )
    var actual = 0.75
    var contexts: [TodayRefreshContext] = []
    let model = makeModel { goal, context in
      contexts.append(context)
      let standing: GoalStanding
      if goal === changing {
        standing = actual < 0.5 ? .behind : .onPace
      } else {
        standing = .onPace
      }
      return .open(
        self.facts(
          standing: standing,
          deadline: goalDate(goal),
          normalizedProgress: actual,
          next: goal === changing ? context.instant.addingTimeInterval(60) : nil
        ))
    }

    model.refresh(habits: [], goals: [changing, near], context: scene)
    #expect(model.goalRows.map(\.name) == ["Near"])
    let standingTransition = try #require(model.nextGoalTransition)
    actual = 0.25
    let transitionEntry = refreshContext(
      instant: standingTransition,
      timeZone: scene.timeZone.identifier
    )
    model.refresh(habits: [], goals: [changing, near], context: transitionEntry)
    #expect(Set(model.goalRows.map(\.name)) == Set(["Changing", "Near"]))

    model.refresh(habits: [], goals: [changing, near], context: environment)
    model.refresh(habits: [], goals: [changing, near], context: nextDay)
    #expect(Set(model.goalRows.map(\.name)) == Set(["Changing", "Near"]))

    actual = 0.75
    let transitionExit = refreshContext(
      instant: try #require(model.nextGoalTransition),
      timeZone: nextDay.timeZone.identifier,
      locale: "sv_SE"
    )
    model.refresh(habits: [], goals: [changing, near], context: transitionExit)
    #expect(model.goalRows.map(\.name) == ["Near"])
    #expect(contexts.suffix(2) == [transitionExit, transitionExit])
  }


  @Test("publication never exposes a mixed habit and Goal generation")
  func publicationIsAtomic() throws {
    let store = try makeStore()
    let habit = try insertHabit(in: store, name: "Habit")
    let goals = try ["A", "B", "C"].map { try insertGoal(in: store, name: $0) }
    var generation = 1
    var model: TodayModel!
    let operations = TodayOperations(
      snapshot: { _, _ in
        if generation == 2 {
          let visible = model.goalRows.compactMap { row -> Int? in
            guard case .accumulate(let progress)? = row.facts?.progress else { return nil }
            return progress.total
          }
          #expect(visible == [1, 1, 1])
          guard case .dashboard(let dashboard)? = model.presentation else {
            Issue.record("Expected published dashboard during replacement")
            return self.habitSnapshot(progress: 2)
          }
          #expect(dashboard.fractionText == "0 of 1")
        }
        return self.habitSnapshot(progress: generation)
      },
      goalFacts: { _, _ in
        if generation == 2 {
          #expect(model.goalRows.compactMap { $0.normalizedProgress } == [0.25, 0.25, 0.25])
        }
        return .open(
          self.facts(
            standing: .behind,
            deadline: nil,
            normalizedProgress: Double(generation) / 4
          ))
      }
    )
    model = TodayModel(operations: operations)
    let context = refreshContext(on: try #require(GoalDate(rawValue: "2026-08-18")))
    model.refresh(habits: [habit], goals: goals, context: context)

    generation = 2
    model.refresh(habits: [habit], goals: goals, context: context)

    #expect(model.goalRows.compactMap { $0.normalizedProgress } == [0.5, 0.5, 0.5])
    guard case .dashboard(let dashboard)? = model.presentation else {
      Issue.record("Expected replacement dashboard")
      return
    }
    #expect(dashboard.goalRows.compactMap { $0.normalizedProgress } == [0.5, 0.5, 0.5])
    #expect(dashboard.toTendRows.first?.facts?.snapshot.progress == 2)
  }

  @Test("retry retains failure then replaces or removes the exact persistent identity")
  func retryRetentionReplacementAndRemoval() throws {
    let store = try makeStore()
    let sharedID = UUID()
    let failed = try insertGoal(in: store, id: sharedID, name: "Failed")
    let sibling = try insertGoal(in: store, id: sharedID, name: "Sibling")
    var mode = 0
    var calls: [PersistentIdentifier: Int] = [:]
    let model = makeModel { goal, _ in
      calls[goal.persistentModelID, default: 0] += 1
      if goal === failed {
        if mode < 2 { throw FixtureError.unavailable }
        if mode == 3 { return .closed(.harvested) }
      }
      return .open(self.facts(standing: .behind, deadline: nil))
    }
    let goals = [failed, sibling]
    let context = refreshContext(on: try #require(GoalDate(rawValue: "2026-08-18")))
    model.refresh(habits: [], goals: goals, context: context)
    let retainedFailure = try #require(model.goalRows.first { $0.id == failed.persistentModelID }?.failure)

    mode = 1
    model.retry(goalID: failed.persistentModelID, habits: [], goals: goals, context: context)
    #expect(model.goalRows.first { $0.id == failed.persistentModelID }?.failure == retainedFailure)
    #expect(calls[sibling.persistentModelID] == 1)

    mode = 2
    model.retry(goalID: failed.persistentModelID, habits: [], goals: goals, context: context)
    #expect(model.goalRows.first { $0.id == failed.persistentModelID }?.facts != nil)
    #expect(model.goalRows.count == 2)
    #expect(calls[sibling.persistentModelID] == 1)

    mode = 0
    model.refresh(habits: [], goals: goals, context: context)
    mode = 3
    model.retry(goalID: failed.persistentModelID, habits: [], goals: goals, context: context)
    #expect(model.goalRows.map(\.id) == [sibling.persistentModelID])
    #expect(calls[sibling.persistentModelID] == 3)

    mode = 0
    model.refresh(habits: [], goals: goals, context: context)
    model.retry(
      goalID: failed.persistentModelID,
      habits: [],
      goals: [sibling],
      context: context
    )
    #expect(model.goalRows.map(\.id) == [sibling.persistentModelID])
    #expect(calls[sibling.persistentModelID] == 5)
  }

  @Test("failed Goal retry refreshes after removing the sole inactive habit")
  func retryRefreshesInactiveHabitRemoval() throws {
    try exerciseInactiveHabitRetry(initiallyIncludesInactiveHabit: true)
  }

  @Test("failed Goal retry refreshes after adding the sole inactive habit")
  func retryRefreshesInactiveHabitInsertion() throws {
    try exerciseInactiveHabitRetry(initiallyIncludesInactiveHabit: false)
  }


  @Test("retry graph or eligibility changes trigger a full refresh")
  func retryGraphAndEligibilityChangesRefreshEverything() throws {
    let store = try makeStore()
    let failed = try insertGoal(in: store, name: "Failed")
    let sibling = try insertGoal(in: store, name: "Sibling")
    var shouldFail = true
    var siblingCalls = 0
    let model = makeModel { goal, _ in
      if goal === sibling { siblingCalls += 1 }
      if goal === failed, shouldFail { throw FixtureError.unavailable }
      return .open(self.facts(standing: goal === failed ? .onPace : .behind, deadline: nil))
    }
    let context = refreshContext(on: try #require(GoalDate(rawValue: "2026-08-18")))
    model.refresh(habits: [], goals: [failed, sibling], context: context)

    let graphEntry = GoalEntry(
      amount: 1,
      assignedDate: try #require(GoalDate(rawValue: "2026-08-18")),
      appendedAt: context.instant,
      appendSequence: 0,
      goal: failed
    )
    store.insert(graphEntry)
    try store.save()
    shouldFail = false
    model.retry(
      goalID: failed.persistentModelID,
      habits: [], goals: [failed, sibling], context: context
    )

    #expect(model.goalRows.map(\.name) == ["Sibling"])
    #expect(siblingCalls == 2)
  }

  @Test("all open goals contribute only valid future earliest transitions")
  func earliestTransitionIncludesCurrentlyIneligibleGoals() throws {
    let store = try makeStore()
    let today = try #require(GoalDate(rawValue: "2026-08-18"))
    let distant = try insertGoal(
      in: store, name: "Distant", deadline: try addingDays(8, to: today)
    )
    let visible = try insertGoal(in: store, name: "Visible", deadline: nil)
    let stale = try insertGoal(in: store, name: "Stale", deadline: nil)
    let context = refreshContext(on: today)
    let early = context.instant.addingTimeInterval(60)
    let late = context.instant.addingTimeInterval(120)
    let model = makeModel { goal, _ in
      if goal === distant {
        return .open(self.facts(standing: .onPace, deadline: goalDate(goal), next: early))
      }
      if goal === stale {
        return .open(self.facts(standing: .behind, deadline: nil, next: context.instant))
      }
      return .open(self.facts(standing: .behind, deadline: nil, next: late))
    }

    model.refresh(habits: [], goals: [visible, distant, stale], context: context)

    #expect(Set(model.goalRows.map(\.name)) == Set(["Visible", "Stale"]))
    #expect(model.nextGoalTransition == early)
  }

  @Test("projection performs no persistence write reminder or notification work")
  func projectionHasNoSideEffects() throws {
    let store = try makeStore()
    let due = try #require(GoalDate(rawValue: "2026-08-20"))
    let goal = try insertGoal(in: store, name: "Unchanged", deadline: due)
    let original = (
      goal.name, goal.target, goal.deadlineKey, goal.closureRawValue,
      goal.entries?.count, goal.readings?.count
    )
    let model = TodayModel(context: store)

    model.refresh(
      habits: [], goals: [goal],
      context: refreshContext(on: try #require(GoalDate(rawValue: "2026-08-18")))
    )

    #expect(model.goalRows.map(\.name) == ["Unchanged"])
    #expect(!store.hasChanges)
    #expect(
      goal.name == original.0 && goal.target == original.1
        && goal.deadlineKey == original.2 && goal.closureRawValue == original.3
        && goal.entries?.count == original.4 && goal.readings?.count == original.5
    )
  }

  @Test("one schedule merges transition and midnight without loops and can be replaced")
  func scheduleSequencesAndReplacement() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let start = try date(2026, 3, 7, 12, calendar: calendar)
    let midnight = try date(2026, 3, 8, 0, calendar: calendar)
    let nextMidnight = try date(2026, 3, 9, 0, calendar: calendar)
    let earlier = start.addingTimeInterval(60)

    #expect(entries(calendar: calendar, start: start, transition: nil, count: 3) == [start, midnight, nextMidnight])
    #expect(entries(calendar: calendar, start: start, transition: earlier, count: 4) == [start, earlier, midnight, nextMidnight])
    #expect(entries(calendar: calendar, start: start, transition: midnight, count: 3) == [start, midnight, nextMidnight])
    #expect(entries(calendar: calendar, start: start, transition: start, count: 3) == [start, midnight, nextMidnight])
    #expect(entries(calendar: calendar, start: start, transition: start.addingTimeInterval(-1), count: 3) == [start, midnight, nextMidnight])
    #expect(midnight.timeIntervalSince(nextMidnight) == -(23 * 60 * 60))

    let replacement = start.addingTimeInterval(120)
    let rebuilt = entries(calendar: calendar, start: start, transition: replacement, count: 3)
    #expect(rebuilt == [start, replacement, midnight])
    #expect(!rebuilt.contains(earlier))
    let fallStart = try date(2026, 10, 31, 12, calendar: calendar)
    let fallMidnight = try date(2026, 11, 1, 0, calendar: calendar)
    let fallBackMidnight = try date(2026, 11, 2, 0, calendar: calendar)
    let ordinaryMidnight = try date(2026, 11, 3, 0, calendar: calendar)
    let fallEntries = entries(
      calendar: calendar,
      start: fallStart,
      transition: nil,
      count: 4
    )
    #expect(
      fallEntries
        == [fallStart, fallMidnight, fallBackMidnight, ordinaryMidnight]
    )
    #expect(fallBackMidnight.timeIntervalSince(fallMidnight) == 25 * 60 * 60)
    #expect(ordinaryMidnight.timeIntervalSince(fallBackMidnight) == 24 * 60 * 60)
  }

  private func entries(
    calendar: Calendar,
    start: Date,
    transition: Date?,
    count: Int
  ) -> [Date] {
    var iterator = LocalDayTimelineSchedule(
      calendar: calendar,
      earlierTransition: transition
    ).entries(from: start, mode: .normal).makeIterator()
    return (0..<count).compactMap { _ in iterator.next() }
  }

  private func makeModel(goalFacts: @escaping TodayOperations.GoalFacts) -> TodayModel {
    TodayModel(
      operations: TodayOperations(
        snapshot: { _, _ in self.habitSnapshot(progress: 0) },
        goalFacts: goalFacts
      ))
  }

  private func facts(
    standing: GoalStanding,
    deadline: GoalDate?,
    normalizedProgress: Double = 0.25,
    next: Date? = nil
  ) -> TodayGoalFacts {
    let total = Int(normalizedProgress * 4)
    let progress: GoalProgressSnapshot = .accumulate(
      AccumulateGoalProgress(
        total: total, target: 4, unit: "times", normalizedProgress: normalizedProgress
      ))
    return TodayGoalFacts(
      progress: progress,
      standing: GoalStandingSnapshot(
        standing: standing,
        actualNormalizedProgress: normalizedProgress,
        expectedNormalizedProgress: deadline == nil ? nil : (standing == .pastDue ? 1 : 0.5),
        deadlineBoundary: deadline.flatMap { try? $0.next().start(in: TimeZone(secondsFromGMT: 0)!) },
        nextTimeRefresh: next
      ),
      deadline: deadline
    )
  }

  private func habitSnapshot(progress: Int) -> HabitTodaySnapshot {
    HabitTodaySnapshot(
      periodKey: "day:2026-08-18", progress: progress, target: 4, unit: "times",
      cadence: .daily, currentStreak: 0, isAtRisk: false, isMet: false
    )
  }

  private func makeStore() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func insertGoal(
    in context: ModelContext,
    id: UUID = UUID(),
    name: String,
    deadline: GoalDate? = nil
  ) throws -> Goal {
    let goal = Goal(
      id: id, name: name, kind: .accumulate, target: 4,
      deadline: deadline, createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    context.insert(goal)
    try context.save()
    return goal
  }

  private func exerciseInactiveHabitRetry(
    initiallyIncludesInactiveHabit: Bool
  ) throws {
    let store = try makeStore()
    let failed = try insertGoal(in: store, name: "Failed")
    let inactive = try insertHabit(in: store, name: "Inactive", isActive: false)
    var shouldFail = true
    let model = makeModel { _, _ in
      if shouldFail { throw FixtureError.unavailable }
      return .open(self.facts(standing: .behind, deadline: nil))
    }
    let context = refreshContext(on: try #require(GoalDate(rawValue: "2026-08-18")))
    let initialHabits = initiallyIncludesInactiveHabit ? [inactive] : []
    let retryHabits = initiallyIncludesInactiveHabit ? [] : [inactive]
    model.refresh(habits: initialHabits, goals: [failed], context: context)

    shouldFail = false
    model.retry(
      goalID: failed.persistentModelID,
      habits: retryHabits,
      goals: [failed],
      context: context
    )

    if initiallyIncludesInactiveHabit {
      guard case .firstLaunch? = model.presentation else {
        Issue.record("Expected first-launch after inactive habit removal")
        return
      }
    } else {
      guard case .inactiveOnly? = model.presentation else {
        Issue.record("Expected inactive-only after inactive habit insertion")
        return
      }
    }
  }

  private func insertHabit(
    in context: ModelContext,
    name: String,
    isActive: Bool = true
  ) throws -> Habit {
    let habit = Habit(
      name: name,
      cadence: .daily,
      target: 4,
      unit: "times",
      isActive: isActive
    )
    context.insert(habit)
    try context.save()
    return habit
  }

  private func goalDate(_ goal: Goal) -> GoalDate? {
    goal.deadlineKey.flatMap(GoalDate.init(rawValue:))
  }

  private func addingDays(_ count: Int, to date: GoalDate) throws -> GoalDate {
    var result = date
    for _ in 0..<count { result = try result.next() }
    return result
  }

  private func refreshContext(
    on day: GoalDate,
    timeZone identifier: String = "UTC",
    locale localeIdentifier: String = "en_US"
  ) -> TodayRefreshContext {
    let zone = TimeZone(identifier: identifier)!
    return refreshContext(
      instant: try! day.start(in: zone).addingTimeInterval(12 * 60 * 60),
      timeZone: identifier,
      locale: localeIdentifier
    )
  }

  private func refreshContext(
    instant: Date,
    timeZone identifier: String,
    locale localeIdentifier: String = "en_US"
  ) -> TodayRefreshContext {
    let zone = TimeZone(identifier: identifier)!
    let locale = Locale(identifier: localeIdentifier)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    calendar.locale = locale
    return TodayRefreshContext(
      instant: instant, timeZone: zone, calendar: calendar, locale: locale
    )
  }

  private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    calendar: Calendar
  ) throws -> Date {
    try #require(
      calendar.date(
        from: DateComponents(
          calendar: calendar, timeZone: calendar.timeZone,
          year: year, month: month, day: day, hour: hour
        ))
    )
  }

  private enum FixtureError: Error, LocalizedError {
    case unavailable
    var errorDescription: String? { "Fixture unavailable." }
  }
}
