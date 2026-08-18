import Foundation
import SwiftData
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Today Goal projection")
struct TodayGoalModelTests {
  @Test("standing and owner-calendar deadline window determine eligibility")
  func standingAndDeadlineWindowDetermineEligibility() throws {
    let store = try makeStore()
    let today = try #require(GoalDate(rawValue: "2026-03-07"))
    let dates = try (0...8).map { try addingDays($0, to: today) }
    let behindBefore = try insertGoal(in: store, name: "Behind before", deadline: nil)
    let behindInside = try insertGoal(in: store, name: "Behind inside", deadline: dates[3])
    let behindOutside = try insertGoal(in: store, name: "Behind outside", deadline: dates[8])
    let onPaceToday = try insertGoal(in: store, name: "Today", deadline: dates[0])
    let onPaceTomorrow = try insertGoal(in: store, name: "Tomorrow", deadline: dates[1])
    let onPaceSeven = try insertGoal(in: store, name: "Seven", deadline: dates[7])
    let onPaceEight = try insertGoal(in: store, name: "Eight", deadline: dates[8])
    let noDeadline = try insertGoal(in: store, name: "No deadline", deadline: nil)
    let goals = [
      behindBefore, behindInside, behindOutside, onPaceToday, onPaceTomorrow,
      onPaceSeven, onPaceEight, noDeadline,
    ]
    let model = makeModel { goal, _ in
      .open(
        facts(
          standing: goal.name.hasPrefix("Behind") ? .behind : .onPace,
          deadline: goalDate(goal)
        ))
    }

    model.refresh(
      habits: [],
      goals: goals,
      context: refreshContext(on: today, timeZone: "America/New_York")
    )

    #expect(
      Set(model.goalRows.map(\.name))
        == Set(["Behind before", "Behind inside", "Behind outside", "Today", "Tomorrow", "Seven"])
    )
  }

  @Test("past due remains eligible at the exclusive boundary and long afterward")
  func pastDueRemainsEligible() throws {
    let store = try makeStore()
    let deadline = try #require(GoalDate(rawValue: "2026-03-07"))
    let atBoundary = try insertGoal(in: store, name: "At boundary", deadline: deadline)
    let longAfter = try insertGoal(in: store, name: "Long after", deadline: deadline)
    let model = makeModel { goal, _ in
      .open(facts(standing: .pastDue, deadline: goalDate(goal), normalizedProgress: 1.25))
    }

    let timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let boundary = try deadline.next().start(in: timeZone)
    model.refresh(
      habits: [],
      goals: [atBoundary],
      context: refreshContext(instant: boundary, timeZone: timeZone.identifier)
    )
    #expect(model.goalRows.map(\.name) == ["At boundary"])

    let later = try #require(GoalDate(rawValue: "2027-12-31"))
    model.refresh(
      habits: [],
      goals: [longAfter],
      context: refreshContext(on: later, timeZone: "Pacific/Auckland")
    )
    #expect(model.goalRows.map(\.name) == ["Long after"])
    #expect(model.goalRows.first?.facts?.standing.standing == .pastDue)
    #expect(model.goalRows.first?.facts?.progress == accumulate(total: 5, target: 4))
  }

  @Test("closed goals are excluded and reopening reevaluates over-target goals")
  func lifecycleAndOverTargetEligibility() throws {
    let store = try makeStore()
    let deadline = try #require(GoalDate(rawValue: "2026-08-18"))
    let harvested = try insertGoal(in: store, name: "Harvested", deadline: deadline)
    harvested.closureRawValue = GoalClosure.harvested.rawValue
    let letGo = try insertGoal(in: store, name: "Let go", deadline: deadline)
    letGo.closureRawValue = GoalClosure.letGo.rawValue
    try store.save()
    let model = makeModel { goal, _ in
      if let closure = try goal.checkedClosure {
        return .closed(closure)
      }
      return .open(
        facts(
          standing: .onPace,
          deadline: goalDate(goal),
          normalizedProgress: 1.75
        ))
    }
    let context = refreshContext(on: deadline)

    model.refresh(habits: [], goals: [harvested, letGo], context: context)
    #expect(model.goalRows.isEmpty)

    harvested.closureRawValue = nil
    try store.save()
    model.refresh(habits: [], goals: [harvested, letGo], context: context)
    #expect(model.goalRows.map(\.name) == ["Harvested"])
    #expect(model.goalRows.first?.facts?.progress == accumulate(total: 7, target: 4))
  }

  @Test("civil dates handle DST month year and time-zone changes")
  func civilDateBoundaries() throws {
    let store = try makeStore()
    let cases: [(String, String, String, Bool)] = [
      ("2026-03-07", "2026-03-14", "America/New_York", true),
      ("2026-03-07", "2026-03-15", "America/New_York", false),
      ("2026-10-31", "2026-11-07", "America/New_York", true),
      ("2026-01-27", "2026-02-03", "UTC", true),
      ("2026-12-25", "2027-01-01", "Pacific/Auckland", true),
    ]

    for (todayKey, deadlineKey, zone, expected) in cases {
      let today = try #require(GoalDate(rawValue: todayKey))
      let deadline = try #require(GoalDate(rawValue: deadlineKey))
      let goal = try insertGoal(in: store, name: "\(todayKey)-\(zone)", deadline: deadline)
      let model = makeModel { goal, _ in
        .open(facts(standing: .onPace, deadline: goalDate(goal)))
      }
      model.refresh(habits: [], goals: [goal], context: refreshContext(on: today, timeZone: zone))
      #expect(!model.goalRows.isEmpty == expected)
    }

    let instant = try #require(
      ISO8601DateFormatter().date(from: "2026-08-17T12:30:00Z")
    )
    let deadline = try #require(GoalDate(rawValue: "2026-08-25"))
    let shifted = try insertGoal(in: store, name: "Shifted", deadline: deadline)
    let model = makeModel { goal, _ in
      .open(facts(standing: .onPace, deadline: goalDate(goal)))
    }
    model.refresh(
      habits: [], goals: [shifted],
      context: refreshContext(instant: instant, timeZone: "Pacific/Kiritimati")
    )
    #expect(model.goalRows.map(\.name) == ["Shifted"])
    var mismatchedCalendar = Calendar(identifier: .gregorian)
    mismatchedCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let ownerTimeZone = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
    model.refresh(
      habits: [],
      goals: [shifted],
      context: TodayRefreshContext(
        instant: instant,
        timeZone: ownerTimeZone,
        calendar: mismatchedCalendar,
        locale: Locale(identifier: "en_US")
      )
    )
    #expect(model.goalRows.map(\.name) == ["Shifted"])
    model.refresh(
      habits: [], goals: [shifted],
      context: refreshContext(instant: instant, timeZone: "America/Los_Angeles")
    )
    #expect(model.goalRows.isEmpty)
  }

  @Test("each persistent Goal is projected once with the captured context")
  func projectsOnceWithCapturedContextAndPersistentIdentity() throws {
    let store = try makeStore()
    let sharedUUID = UUID()
    let first = try insertGoal(in: store, id: sharedUUID, name: "First")
    let second = try insertGoal(in: store, id: sharedUUID, name: "Second")
    let expectedContext = refreshContext(on: try #require(GoalDate(rawValue: "2026-08-18")))
    var calls: [PersistentIdentifier: Int] = [:]
    var contexts: [TodayRefreshContext] = []
    let model = makeModel { goal, context in
      calls[goal.persistentModelID, default: 0] += 1
      contexts.append(context)
      return .open(facts(standing: .behind, deadline: nil))
    }

    model.refresh(
      habits: [],
      goals: [first, first, second, second],
      context: expectedContext
    )

    #expect(calls[first.persistentModelID] == 1)
    #expect(calls[second.persistentModelID] == 1)
    #expect(contexts == [expectedContext, expectedContext])
    #expect(model.goalRows.count == 2)
    #expect(Set(model.goalRows.map(\.id)).count == 2)
    #expect(Set(model.goalRows.map { $0.goal.id }).count == 1)
  }

  @Test("urgency deadline localized name creation and persistent identity order rows")
  func deterministicOrdering() throws {
    let store = try makeStore()
    let earlierDate = try #require(GoalDate(rawValue: "2026-08-19"))
    let laterDate = try #require(GoalDate(rawValue: "2026-08-20"))
    let sameCreation = Date(timeIntervalSince1970: 100)
    let unavailable = try insertGoal(in: store, name: "Unavailable", deadline: laterDate)
    let pastDue = try insertGoal(in: store, name: "Past", deadline: earlierDate)
    let behindLater = try insertGoal(in: store, name: "A", deadline: laterDate)
    let behindEarlier = try insertGoal(in: store, name: "Z", deadline: earlierDate)
    let alphaFirst = try insertGoal(in: store, name: "alpha", deadline: laterDate, createdAt: sameCreation)
    let alphaSecond = try insertGoal(in: store, name: "Alpha", deadline: laterDate, createdAt: sameCreation)
    let betaEarlier = try insertGoal(in: store, name: "Beta", deadline: laterDate, createdAt: Date(timeIntervalSince1970: 1))
    let betaLater = try insertGoal(in: store, name: "beta", deadline: laterDate, createdAt: Date(timeIntervalSince1970: 2))
    let onPace = try insertGoal(in: store, name: "On pace", deadline: earlierDate)
    let alphaByID = [alphaFirst, alphaSecond].sorted { $0.persistentModelID < $1.persistentModelID }
    let model = makeModel { goal, _ in
      if goal === unavailable { throw FixtureError.unavailable }
      let standing: GoalStanding
      if goal === pastDue { standing = .pastDue }
      else if goal === onPace { standing = .onPace }
      else { standing = .behind }
      return .open(facts(standing: standing, deadline: goalDate(goal)))
    }

    model.refresh(
      habits: [],
      goals: [onPace, betaLater, alphaSecond, behindLater, unavailable, pastDue, alphaFirst, behindEarlier, betaEarlier],
      context: refreshContext(on: try #require(GoalDate(rawValue: "2026-08-18")), locale: "en_US")
    )

    #expect(
      model.goalRows.map(\.id)
        == [
          unavailable.persistentModelID,
          pastDue.persistentModelID,
          behindEarlier.persistentModelID,
          behindLater.persistentModelID,
        ]
        + alphaByID.map(\.persistentModelID)
        + [betaEarlier.persistentModelID, betaLater.persistentModelID, onPace.persistentModelID]
    )

    let zed = try insertGoal(in: store, name: "z", deadline: laterDate)
    let umlaut = try insertGoal(in: store, name: "ä", deadline: laterDate)
    model.refresh(
      habits: [],
      goals: [umlaut, zed],
      context: refreshContext(
        on: try #require(GoalDate(rawValue: "2026-08-18")),
        locale: "sv_SE"
      )
    )
    #expect(model.goalRows.map(\.name) == ["z", "ä"])
  }

  @Test("Accumulate and both Measure directions retain truthful formatted facts")
  func truthfulProgressFormatting() throws {
    let store = try makeStore()
    let due = try #require(GoalDate(rawValue: "2026-08-20"))
    let accumulateGoal = try insertGoal(in: store, name: "Read", target: 6, unit: "books", deadline: due)
    let increasing = try insertGoal(in: store, name: "Lift", kind: .measure, target: 200, unit: "lb", baseline: 100, deadline: due)
    let decreasing = try insertGoal(in: store, name: "Lower", kind: .measure, target: 120, unit: "mmHg", baseline: 180, deadline: due)
    let model = makeModel { goal, _ in
      let progress: GoalProgressSnapshot
      if goal === accumulateGoal {
        progress = accumulate(total: 7, target: 6, unit: "books")
      } else if goal === increasing {
        progress = measure(baseline: 100, target: 200, current: 160, unit: "lb")
      } else {
        progress = measure(baseline: 180, target: 120, current: 145, unit: "mmHg")
      }
      return .open(facts(standing: .behind, deadline: due, progress: progress))
    }

    model.refresh(
      habits: [], goals: [accumulateGoal, increasing, decreasing],
      context: refreshContext(on: try #require(GoalDate(rawValue: "2026-08-18")), locale: "en_US")
    )

    let rows = Dictionary(uniqueKeysWithValues: model.goalRows.map { ($0.name, $0) })
    #expect(rows["Read"]?.progressText == "7 of 6 books")
    #expect(rows["Read"]?.normalizedProgress == 7.0 / 6.0)
    #expect(rows["Lift"]?.progressText == "160 lb now · 60 of 100 lb")
    #expect(rows["Lift"]?.progress == .measure(baseline: 100, target: 200, current: 160, completedDistance: 60, totalDistance: 100, direction: .increasing, unit: "lb", normalizedProgress: 0.6))
    #expect(rows["Lower"]?.progressText == "145 mmHg now · 35 of 60 mmHg")
    #expect(rows["Lower"]?.progress == .measure(baseline: 180, target: 120, current: 145, completedDistance: 35, totalDistance: 60, direction: .decreasing, unit: "mmHg", normalizedProgress: 35.0 / 60.0))
    #expect(rows.values.allSatisfy { $0.accessibilityValue.contains($0.progressText) })
    #expect(rows.values.allSatisfy { $0.deadlineText.contains("Due") })
    #expect(rows.values.allSatisfy { $0.standingText == "Behind" })
  }

  @Test("malformed facts and relationship failures are isolated as unavailable rows")
  func failuresAreIsolatedAndTruthful() throws {
    let store = try makeStore()
    let due = try #require(GoalDate(rawValue: "2026-08-20"))
    let good = try insertGoal(in: store, name: "Good", deadline: due)
    let malformedClosure = try insertGoal(in: store, name: "Closure", deadline: due)
    malformedClosure.closureRawValue = "unknown"
    let malformedDate = try insertGoal(in: store, name: "Date", deadline: due)
    malformedDate.deadlineKey = "2026-99-99"
    let malformedProgress = try insertGoal(in: store, name: "Progress", deadline: due)
    let malformedStanding = try insertGoal(in: store, name: "Standing", deadline: due)
    let relationship = try insertGoal(in: store, name: "Relationship", deadline: due)
    let distant = try #require(GoalDate(rawValue: "2026-09-01"))
    let malformedOutsideWindow = try insertGoal(
      in: store,
      name: "Outside-window standing",
      deadline: distant
    )
    try store.save()
    let live = TodayOperations.live(context: store)
    let model = TodayModel(
      operations: TodayOperations(
        snapshot: live.snapshot,
        goalFacts: { goal, context in
          if goal === malformedClosure || goal === malformedDate {
            return try live.goalFacts(goal, context)
          }
          if goal === malformedProgress {
            return .open(
              facts(
                standing: .behind,
                deadline: due,
                progress: .accumulate(
                  AccumulateGoalProgress(total: 1, target: 999, unit: "wrong", normalizedProgress: .nan)
                )
              ))
          }
          if goal === malformedStanding {
            return .open(
              TodayGoalFacts(
                progress: accumulate(total: 1, target: 4),
                standing: GoalStandingSnapshot(
                  standing: .onPace,
                  actualNormalizedProgress: 0.9,
                  expectedNormalizedProgress: 0.5,
                  deadlineBoundary: try due.next().start(in: context.timeZone),
                  nextTimeRefresh: nil
                ),
                deadline: due
              ))
          }
          if goal === malformedOutsideWindow {
            return .open(
              TodayGoalFacts(
                progress: accumulate(total: 1, target: 4),
                standing: GoalStandingSnapshot(
                  standing: .onPace,
                  actualNormalizedProgress: 0.9,
                  expectedNormalizedProgress: 0.5,
                  deadlineBoundary: try distant.next().start(in: context.timeZone),
                  nextTimeRefresh: nil
                ),
                deadline: distant
              ))
          }
          if goal === relationship { throw FixtureError.relationship }
          return .open(facts(standing: .behind, deadline: due))
        }
      ))

    model.refresh(
      habits: [],
      goals: [
        good,
        malformedClosure,
        malformedDate,
        malformedProgress,
        malformedStanding,
        relationship,
        malformedOutsideWindow,
      ],
      context: refreshContext(on: try #require(GoalDate(rawValue: "2026-08-18")))
    )

    #expect(model.goalRows.count == 7)
    #expect(model.goalRows.first { $0.goal === good }?.facts != nil)
    for failed in [
      malformedClosure,
      malformedDate,
      malformedProgress,
      malformedStanding,
      relationship,
      malformedOutsideWindow,
    ] {
      let row = try #require(model.goalRows.first { $0.goal === failed })
      #expect(row.facts == nil)
      #expect(row.failure != nil)
      #expect(row.progressText == "Progress unavailable")
      #expect(row.accessibilityValue.contains("Try again"))
    }
  }

  @Test("Goal rows leave habit grouping and fraction alone but suppress All tended")
  func habitPresentationRemainsIndependent() throws {
    let store = try makeStore()
    let habit = try insertHabit(in: store, name: "Done")
    let goal = try insertGoal(in: store, name: "Needs attention")
    let model = TodayModel(
      operations: TodayOperations(
        snapshot: { _, _ in
          HabitTodaySnapshot(
            periodKey: "day:2026-08-18", progress: 1, target: 1, unit: "times",
            cadence: .daily, currentStreak: 1, isAtRisk: false, isMet: true
          )
        },
        goalFacts: { _, _ in .open(facts(standing: .behind, deadline: nil)) }
      ))

    model.refresh(
      habits: [habit], goals: [goal],
      context: refreshContext(on: try #require(GoalDate(rawValue: "2026-08-18")))
    )

    guard case .dashboard(let dashboard)? = model.presentation else {
      Issue.record("Expected dashboard")
      return
    }
    #expect(dashboard.metCount == 1)
    #expect(dashboard.activeCount == 1)
    #expect(dashboard.fractionText == "1 of 1")
    #expect(dashboard.toTendRows.isEmpty)
    #expect(dashboard.tendedRows.map(\.habit) == [habit])
    #expect(dashboard.goalRows.map(\.goal) == [goal])
    #expect(!dashboard.showsAllTended)
  }

  private func makeModel(
    goalFacts: @escaping TodayOperations.GoalFacts
  ) -> TodayModel {
    TodayModel(
      operations: TodayOperations(
        snapshot: { habit, _ in
          HabitTodaySnapshot(
            periodKey: "day:2026-08-18", progress: 0, target: habit.target,
            unit: habit.unit, cadence: .daily, currentStreak: 0,
            isAtRisk: false, isMet: false
          )
        },
        goalFacts: goalFacts
      ))
  }

  private func facts(
    standing: GoalStanding,
    deadline: GoalDate?,
    normalizedProgress: Double = 0.25,
    progress: GoalProgressSnapshot? = nil,
    nextTransition: Date? = nil
  ) -> TodayGoalFacts {
    let progress = progress ?? accumulate(total: Int(normalizedProgress * 4), target: 4)
    return TodayGoalFacts(
      progress: progress,
      standing: GoalStandingSnapshot(
        standing: standing,
        actualNormalizedProgress: normalized(progress),
        expectedNormalizedProgress: deadline == nil ? nil : (standing == .pastDue ? 1 : 0.5),
        deadlineBoundary: deadline.flatMap { try? $0.next().start(in: TimeZone(secondsFromGMT: 0)!) },
        nextTimeRefresh: nextTransition
      ),
      deadline: deadline
    )
  }

  private func normalized(_ progress: GoalProgressSnapshot) -> Double {
    switch progress {
    case .accumulate(let value): value.normalizedProgress
    case .measure(let value): value.normalizedProgress
    }
  }

  private func accumulate(total: Int, target: Int, unit: String = "times") -> GoalProgressSnapshot {
    .accumulate(
      AccumulateGoalProgress(
        total: total,
        target: target,
        unit: unit,
        normalizedProgress: Double(total) / Double(target)
      ))
  }

  private func measure(
    baseline: Int,
    target: Int,
    current: Int,
    unit: String
  ) -> GoalProgressSnapshot {
    let total = abs(target - baseline)
    let completed = min(max(target > baseline ? current - baseline : baseline - current, 0), total)
    return .measure(
      MeasureGoalProgress(
        baseline: baseline,
        target: target,
        currentValue: current,
        effectiveReadingID: nil,
        completedDistance: completed,
        totalDistance: total,
        unit: unit,
        normalizedProgress: Double(completed) / Double(total)
      ))
  }

  private func makeStore() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func insertGoal(
    in context: ModelContext,
    id: UUID = UUID(),
    name: String,
    kind: GoalKind = .accumulate,
    target: Int = 4,
    unit: String = "times",
    baseline: Int? = nil,
    deadline: GoalDate? = nil,
    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
  ) throws -> Goal {
    let goal = Goal(
      id: id, name: name, kind: kind, target: target, unit: unit,
      baseline: baseline, deadline: deadline, createdAt: createdAt
    )
    context.insert(goal)
    try context.save()
    return goal
  }

  private func insertHabit(in context: ModelContext, name: String) throws -> Habit {
    let habit = Habit(name: name, cadence: .daily, target: 1, unit: "times")
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
    locale identifierLocale: String = "en_US"
  ) -> TodayRefreshContext {
    let timeZone = TimeZone(identifier: identifier)!
    return refreshContext(
      instant: try! day.start(in: timeZone).addingTimeInterval(12 * 60 * 60),
      timeZone: identifier,
      locale: identifierLocale
    )
  }

  private func refreshContext(
    instant: Date,
    timeZone identifier: String,
    locale identifierLocale: String = "en_US"
  ) -> TodayRefreshContext {
    let timeZone = TimeZone(identifier: identifier)!
    let locale = Locale(identifier: identifierLocale)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.locale = locale
    return TodayRefreshContext(
      instant: instant,
      timeZone: timeZone,
      calendar: calendar,
      locale: locale
    )
  }

  private enum FixtureError: Error, LocalizedError {
    case unavailable
    case relationship

    var errorDescription: String? {
      switch self {
      case .unavailable: "Fixture unavailable."
      case .relationship: "Relationship unavailable."
      }
    }
  }
}
