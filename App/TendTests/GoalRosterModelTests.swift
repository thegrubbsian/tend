import Foundation
import SwiftData
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Goal roster model")
struct GoalRosterModelTests {
  @Test("empty, open, past-due, harvested, and let-go goals partition exactly once")
  func partitionsEveryGoalExactlyOnce() throws {
    let fixture = try GoalRosterFixture()
    var fetchedGoals: [Goal] = []
    var factsByID: [UUID: GoalRosterDomainFacts] = [:]
    let model = fixture.model(goals: { fetchedGoals }, facts: { goal in
      try #require(factsByID[goal.id])
    })

    model.refresh(
      at: fixture.instant,
      calendar: fixture.calendar,
      timeZone: fixture.timeZone,
      locale: fixture.locale
    )
    #expect(model.openRows.isEmpty)
    #expect(model.pastDueRows.isEmpty)
    #expect(model.closedRows.isEmpty)

    let open = try fixture.insertGoal(name: "Open")
    let behind = try fixture.insertGoal(name: "Behind", deadline: fixture.futureDeadline)
    let pastDue = try fixture.insertGoal(name: "Past", deadline: fixture.pastDeadline)
    let harvested = try fixture.insertGoal(name: "Harvested", closure: .harvested)
    let letGo = try fixture.insertGoal(name: "Let go", closure: .letGo)
    fetchedGoals = [open, behind, pastDue, harvested, letGo]
    factsByID = [
      open.id: fixture.accumulateFacts(standing: fixture.standing(.onPace)),
      behind.id: fixture.accumulateFacts(standing: fixture.standing(.behind)),
      pastDue.id: fixture.accumulateFacts(standing: fixture.standing(.pastDue)),
      harvested.id: fixture.accumulateFacts(closure: .harvested),
      letGo.id: fixture.accumulateFacts(closure: .letGo),
    ]

    model.refresh(
      at: fixture.instant,
      calendar: fixture.calendar,
      timeZone: fixture.timeZone,
      locale: fixture.locale
    )

    #expect(model.openRows.map(\.stateText) == ["Behind", "On pace"])
    #expect(model.pastDueRows.map(\.stateText) == ["Past due"])
    #expect(Set(model.closedRows.map(\.stateText)) == ["Harvested", "Let go"])
    let rows = model.openRows + model.pastDueRows + model.closedRows
    let fetchedIDs = Set(fetchedGoals.map(\.persistentModelID))
    #expect(rows.count == fetchedGoals.count)
    #expect(Set(rows.map(\.id)) == fetchedIDs)
    #expect(Set(rows.map(\.id)).count == rows.count)
    #expect(model.loadFailure == nil)
  }

  @Test("accumulate rows retain exact target and over-target progress")
  func projectsAccumulateProgressWithoutClampingFacts() throws {
    let fixture = try GoalRosterFixture()
    let exact = try fixture.insertGoal(name: "Exact", target: 1_000, unit: "miles")
    let over = try fixture.insertGoal(name: "Over", target: 1_000, unit: "miles")
    let model = fixture.model(
      goals: { [exact, over] },
      facts: { goal in
        fixture.accumulateFacts(
          total: goal.id == exact.id ? 1_000 : 1_250,
          target: 1_000,
          unit: "miles",
          standing: fixture.standing(.onPace)
        )
      }
    )

    fixture.refresh(model)
    let rows = Dictionary(uniqueKeysWithValues: model.openRows.map { ($0.goal.id, $0) })
    let exactRow = try #require(rows[exact.id])
    let overRow = try #require(rows[over.id])

    #expect(
      exactRow.progress
        == .accumulate(total: 1_000, target: 1_000, unit: "miles", normalizedProgress: 1)
    )
    #expect(exactRow.progressText == "1,000 of 1,000 miles")
    #expect(
      overRow.progress
        == .accumulate(total: 1_250, target: 1_000, unit: "miles", normalizedProgress: 1.25)
    )
    #expect(overRow.progressText == "1,250 of 1,000 miles")
    #expect(overRow.accessibilityLabel == "Over")
    #expect(overRow.accessibilityValue == "On pace, 1,250 of 1,000 miles, No deadline")
  }

  @Test("increasing and decreasing measure rows retain current value and direction")
  func projectsBothMeasureDirections() throws {
    let fixture = try GoalRosterFixture()
    let increasing = try fixture.insertGoal(
      name: "Increase",
      kind: .measure,
      target: 2_000,
      unit: "kg",
      baseline: 1_000,
      readingValues: [1_400]
    )
    let decreasing = try fixture.insertGoal(
      name: "Decrease",
      kind: .measure,
      target: 1_000,
      unit: "kg",
      baseline: 2_000,
      readingValues: [1_350]
    )
    let model = fixture.model(
      goals: { [increasing, decreasing] },
      facts: { goal in
        if goal.id == increasing.id {
          return fixture.measureFacts(
            baseline: 1_000,
            target: 2_000,
            current: 1_400,
            completed: 400,
            total: 1_000,
            normalized: 0.4
          )
        }
        return fixture.measureFacts(
          baseline: 2_000,
          target: 1_000,
          current: 1_350,
          completed: 650,
          total: 1_000,
          normalized: 0.65
        )
      }
    )

    fixture.refresh(model)
    let rows = Dictionary(uniqueKeysWithValues: model.openRows.map { ($0.goal.id, $0) })

    #expect(
      rows[increasing.id]?.progress
        == .measure(
          baseline: 1_000,
          target: 2_000,
          current: 1_400,
          completedDistance: 400,
          totalDistance: 1_000,
          direction: .increasing,
          unit: "kg",
          normalizedProgress: 0.4
        )
    )
    #expect(rows[increasing.id]?.progressText == "1,400 kg now · 400 of 1,000 kg")
    #expect(
      rows[decreasing.id]?.progress
        == .measure(
          baseline: 2_000,
          target: 1_000,
          current: 1_350,
          completedDistance: 650,
          totalDistance: 1_000,
          direction: .decreasing,
          unit: "kg",
          normalizedProgress: 0.65
        )
    )
    #expect(rows[decreasing.id]?.progressText == "1,350 kg now · 650 of 1,000 kg")
  }

  @Test("no-deadline goals are on pace and expose no transition")
  func projectsNoDeadlineGoal() throws {
    let fixture = try GoalRosterFixture()
    let goal = try fixture.insertGoal(name: "Read")
    let model = fixture.model(
      goals: { [goal] },
      facts: { _ in fixture.accumulateFacts(standing: fixture.standing(.onPace)) }
    )

    fixture.refresh(model)
    let row = try #require(model.openRows.first)

    #expect(row.deadlineText == "No deadline")
    #expect(row.standing == .onPace)
    #expect(row.expectedNormalizedProgress == nil)
    #expect(row.stateText == "On pace")
    #expect(model.nextRefreshInstant == nil)
  }

  @Test("open goals order behind before on-pace, then deadline, name, creation, and id")
  func ordersOpenGoals() throws {
    let fixture = try GoalRosterFixture()
    let early = fixture.date("2026-01-02T00:00:00Z")
    let late = fixture.date("2026-01-03T00:00:00Z")
    let lowestID = fixture.uuid("10000000-0000-0000-0000-000000000001")
    let highestID = fixture.uuid("20000000-0000-0000-0000-000000000001")
    let behindEarly = try fixture.insertGoal(
      name: "Zulu", deadline: fixture.earlierFutureDeadline, createdAt: late)
    let behindLater = try fixture.insertGoal(
      name: "Alpha", deadline: fixture.futureDeadline, createdAt: early)
    let onPaceDeadline = try fixture.insertGoal(
      name: "Zulu", deadline: fixture.futureDeadline, createdAt: early)
    let onPaceAlpha = try fixture.insertGoal(
      name: "alpha", deadline: fixture.laterFutureDeadline, createdAt: late)
    let onPaceBravoOldLow = try fixture.insertGoal(
      id: lowestID,
      name: "Bravo",
      deadline: fixture.laterFutureDeadline,
      createdAt: early
    )
    let onPaceBravoOldHigh = try fixture.insertGoal(
      id: highestID,
      name: "bravo",
      deadline: fixture.laterFutureDeadline,
      createdAt: early
    )
    let onPaceBravoNew = try fixture.insertGoal(
      name: "Bravo", deadline: fixture.laterFutureDeadline, createdAt: late)
    let onPaceNoDeadline = try fixture.insertGoal(name: "Aardvark", createdAt: early)
    let goals = [
      onPaceNoDeadline, onPaceBravoNew, onPaceBravoOldHigh, onPaceAlpha, behindLater,
      onPaceDeadline, behindEarly, onPaceBravoOldLow,
    ]
    let model = fixture.model(
      goals: { goals },
      facts: { goal in
        fixture.accumulateFacts(
          standing: fixture.standing(
            goal.id == behindEarly.id || goal.id == behindLater.id ? .behind : .onPace
          )
        )
      }
    )

    fixture.refresh(model)

    #expect(
      model.openRows.map(\.goal.id)
        == [
          behindEarly.id,
          behindLater.id,
          onPaceDeadline.id,
          onPaceAlpha.id,
          onPaceBravoOldLow.id,
          onPaceBravoOldHigh.id,
          onPaceBravoNew.id,
          onPaceNoDeadline.id,
        ]
    )
    #expect(model.openRows[0].deadlineText == "Jan 18, 2026")
    #expect(model.openRows.last?.deadlineText == "No deadline")
  }

  @Test("past-due goals order by deadline then deterministic tie-breakers")
  func ordersPastDueGoals() throws {
    let fixture = try GoalRosterFixture()
    let old = fixture.date("2026-01-01T00:00:00Z")
    let recent = fixture.date("2026-01-02T00:00:00Z")
    let lowID = fixture.uuid("30000000-0000-0000-0000-000000000001")
    let highID = fixture.uuid("40000000-0000-0000-0000-000000000001")
    let earlierDeadline = try fixture.insertGoal(name: "Zulu", deadline: fixture.earlierPastDeadline)
    let alpha = try fixture.insertGoal(name: "alpha", deadline: fixture.pastDeadline, createdAt: recent)
    let bravoOldLow = try fixture.insertGoal(
      id: lowID,
      name: "Bravo",
      deadline: fixture.pastDeadline,
      createdAt: old
    )
    let bravoOldHigh = try fixture.insertGoal(
      id: highID,
      name: "bravo",
      deadline: fixture.pastDeadline,
      createdAt: old
    )
    let bravoNew = try fixture.insertGoal(
      name: "Bravo", deadline: fixture.pastDeadline, createdAt: recent)
    let goals = [bravoNew, bravoOldHigh, alpha, earlierDeadline, bravoOldLow]
    let model = fixture.model(
      goals: { goals },
      facts: { _ in fixture.accumulateFacts(standing: fixture.standing(.pastDue)) }
    )

    fixture.refresh(model)

    #expect(
      model.pastDueRows.map(\.goal.id)
        == [earlierDeadline.id, alpha.id, bravoOldLow.id, bravoOldHigh.id, bravoNew.id]
    )
  }

  @Test("closed goals use one deterministic combined order")
  func ordersCombinedClosedGoals() throws {
    let fixture = try GoalRosterFixture()
    let old = fixture.date("2026-01-01T00:00:00Z")
    let recent = fixture.date("2026-01-02T00:00:00Z")
    let lowID = fixture.uuid("50000000-0000-0000-0000-000000000001")
    let highID = fixture.uuid("60000000-0000-0000-0000-000000000001")
    let alphaLetGo = try fixture.insertGoal(name: "Alpha", closure: .letGo, createdAt: recent)
    let bravoHarvestedOldLow = try fixture.insertGoal(
      id: lowID, name: "Bravo", closure: .harvested, createdAt: old)
    let bravoLetGoOldHigh = try fixture.insertGoal(
      id: highID, name: "bravo", closure: .letGo, createdAt: old)
    let bravoHarvestedNew = try fixture.insertGoal(
      name: "Bravo", closure: .harvested, createdAt: recent)
    let goals = [bravoHarvestedNew, bravoLetGoOldHigh, alphaLetGo, bravoHarvestedOldLow]
    let model = fixture.model(
      goals: { goals },
      facts: { goal in
        let closure = try goal.checkedClosure
        return fixture.accumulateFacts(closure: try #require(closure))
      }
    )

    fixture.refresh(model)

    #expect(
      model.closedRows.map(\.goal.id)
        == [
          alphaLetGo.id,
          bravoHarvestedOldLow.id,
          bravoLetGoOldHigh.id,
          bravoHarvestedNew.id,
        ]
    )
    #expect(model.closedRows.map(\.stateText) == ["Let go", "Harvested", "Let go", "Harvested"])
  }

  @Test("the earliest domain transition drives the next refresh instant")
  func exposesEarliestNextTransition() throws {
    let fixture = try GoalRosterFixture()
    let past = fixture.instant.addingTimeInterval(-1)
    let early = fixture.instant.addingTimeInterval(60)
    let late = fixture.instant.addingTimeInterval(600)
    let ignored = try fixture.insertGoal(name: "Elapsed")
    let first = try fixture.insertGoal(name: "First")
    let second = try fixture.insertGoal(name: "Second")
    let none = try fixture.insertGoal(name: "None")
    let model = fixture.model(
      goals: { [second, ignored, none, first] },
      facts: { goal in
        let transition: Date?
        if goal.id == ignored.id {
          transition = past
        } else if goal.id == first.id {
          transition = early
        } else if goal.id == second.id {
          transition = late
        } else {
          transition = nil
        }
        return fixture.accumulateFacts(
          standing: fixture.standing(.onPace, nextTimeRefresh: transition)
        )
      }
    )

    fixture.refresh(model)

    #expect(model.nextRefreshInstant == early)
  }

  @Test("closed disclosure survives successful and failed reloads in one model lifetime")
  func preservesClosedDisclosureState() throws {
    let fixture = try GoalRosterFixture()
    let first = try fixture.insertGoal(name: "First", closure: .harvested)
    let second = try fixture.insertGoal(name: "Second", closure: .letGo)
    var fetchedGoals = [first]
    var shouldFail = false
    let model = GoalRosterModel(
      operations: GoalRosterOperations(
        fetchGoals: {
          if shouldFail { throw TestGoalRosterFailure.fetch }
          return fetchedGoals
        },
        facts: { goal, _, _, _ in
          let closure = try goal.checkedClosure
          return fixture.accumulateFacts(closure: try #require(closure))
        }
      )
    )

    fixture.refresh(model)
    model.toggleClosedDisclosure()
    #expect(model.isClosedExpanded)

    fetchedGoals = [second, first]
    fixture.refresh(model)
    #expect(model.isClosedExpanded)
    #expect(Set(model.closedRows.map(\.goal.id)) == [first.id, second.id])

    shouldFail = true
    fixture.refresh(model)
    #expect(model.isClosedExpanded)
    #expect(Set(model.closedRows.map(\.goal.id)) == [first.id, second.id])
    #expect(model.loadFailure != nil)
  }

  @Test("time and persisted mutation refreshes replace the complete roster")
  func refreshesAtNewInstantAndAfterMutation() throws {
    let fixture = try GoalRosterFixture()
    let goal = try fixture.insertGoal(
      name: "Finish",
      target: 10,
      deadline: try #require(GoalDate(year: 2026, month: 1, day: 15)),
      entryAmounts: [2]
    )
    let model = GoalRosterModel(context: fixture.context)

    fixture.refresh(model)
    #expect(model.openRows.map(\.goal.id) == [goal.id])
    #expect(model.openRows.first?.progressText == "2 of 10 times")

    model.refresh(
      at: fixture.date("2026-01-16T00:01:00Z"),
      calendar: fixture.calendar,
      timeZone: fixture.timeZone,
      locale: fixture.locale
    )
    #expect(model.openRows.isEmpty)
    #expect(model.pastDueRows.map(\.goal.id) == [goal.id])

    goal.closureRawValue = GoalClosure.harvested.rawValue
    let replacement = try fixture.insertGoal(name: "Replacement", target: 3, entryAmounts: [3])
    try fixture.context.save()
    model.refresh(
      at: fixture.date("2026-01-16T00:01:00Z"),
      calendar: fixture.calendar,
      timeZone: fixture.timeZone,
      locale: fixture.locale
    )

    #expect(model.pastDueRows.isEmpty)
    #expect(model.openRows.map(\.goal.id) == [replacement.id])
    #expect(model.openRows.first?.progressText == "3 of 3 times")
    #expect(model.closedRows.map(\.goal.id) == [goal.id])
    #expect(model.closedRows.first?.stateText == "Harvested")
  }

  @Test("fetch failure preserves the last complete roster and offers retry")
  func preservesRowsOnFetchFailure() throws {
    let fixture = try GoalRosterFixture()
    let goal = try fixture.insertGoal(name: "Saved")
    let transition = fixture.instant.addingTimeInterval(300)
    var fetchAttempts = 0
    let model = GoalRosterModel(
      operations: GoalRosterOperations(
        fetchGoals: {
          fetchAttempts += 1
          if fetchAttempts == 2 { throw TestGoalRosterFailure.fetch }
          return [goal]
        },
        facts: { _, _, _, _ in
          fixture.accumulateFacts(
            total: fetchAttempts == 1 ? 4 : 7,
            standing: fixture.standing(.onPace, nextTimeRefresh: transition)
          )
        }
      )
    )

    fixture.refresh(model)
    model.toggleClosedDisclosure()
    let savedProgress = model.openRows.map(\.progress)
    let savedTransition = model.nextRefreshInstant

    fixture.refresh(model)

    #expect(model.openRows.map(\.progress) == savedProgress)
    #expect(model.nextRefreshInstant == savedTransition)
    #expect(model.isClosedExpanded)
    #expect(
      model.loadFailure
        == GoalRosterLoadFailure(message: "Goals are unavailable right now.", retryTitle: "Try again")
    )

    model.retryRefresh()
    #expect(fetchAttempts == 3)
    #expect(model.openRows.first?.progressText == "7 of 10 times")
    #expect(model.loadFailure == nil)
  }

  @Test("one corrupt goal fails the complete refresh without publishing partial rows")
  func preservesRowsOnFactFailure() throws {
    let fixture = try GoalRosterFixture()
    let savedOpen = try fixture.insertGoal(name: "Saved open")
    let savedPastDue = try fixture.insertGoal(name: "Saved past", deadline: fixture.pastDeadline)
    let savedClosed = try fixture.insertGoal(name: "Saved closed", closure: .harvested)
    let projectedBeforeFailure = try fixture.insertGoal(name: "Would publish")
    let corrupt = try fixture.insertGoal(name: "Corrupt")
    let savedTransition = fixture.instant.addingTimeInterval(300)
    let unpublishedTransition = fixture.instant.addingTimeInterval(60)
    var fetchedGoals = [savedOpen, savedPastDue, savedClosed]
    var corruptID: UUID?
    var factInvocations: [UUID] = []
    let model = fixture.model(
      goals: { fetchedGoals },
      facts: { goal in
        factInvocations.append(goal.id)
        if goal.id == corruptID { throw TestGoalRosterFailure.facts }
        if goal.id == savedPastDue.id {
          return fixture.accumulateFacts(standing: fixture.standing(.pastDue))
        }
        if goal.id == savedClosed.id {
          return fixture.accumulateFacts(closure: .harvested)
        }
        return fixture.accumulateFacts(
          total: goal.id == savedOpen.id ? 3 : 9,
          standing: fixture.standing(
            .onPace,
            nextTimeRefresh: goal.id == savedOpen.id ? savedTransition : unpublishedTransition
          )
        )
      }
    )

    fixture.refresh(model)
    model.toggleClosedDisclosure()
    let savedOpenRows = model.openRows.map { ($0.id, $0.progress) }
    let savedPastDueIDs = model.pastDueRows.map(\.id)
    let savedClosedIDs = model.closedRows.map(\.id)

    fetchedGoals = [projectedBeforeFailure, corrupt]
    corruptID = corrupt.id
    factInvocations.removeAll()
    fixture.refresh(model)

    #expect(factInvocations == [projectedBeforeFailure.id, corrupt.id])
    #expect(model.openRows.count == savedOpenRows.count)
    #expect(model.openRows.first?.id == savedOpenRows.first?.0)
    #expect(model.openRows.first?.progress == savedOpenRows.first?.1)
    #expect(model.pastDueRows.map(\.id) == savedPastDueIDs)
    #expect(model.closedRows.map(\.id) == savedClosedIDs)
    #expect(model.nextRefreshInstant == savedTransition)
    #expect(model.isClosedExpanded)
    #expect(model.loadFailure?.retryTitle == "Try again")
  }
}

@MainActor
private final class GoalRosterFixture {
  let context: ModelContext
  let instant: Date
  let timeZone: TimeZone
  let calendar: Calendar
  let locale: Locale
  let earlierFutureDeadline: GoalDate
  let futureDeadline: GoalDate
  let laterFutureDeadline: GoalDate
  let earlierPastDeadline: GoalDate
  let pastDeadline: GoalDate

  init() throws {
    let container = try TendModelContainer.inMemory()
    context = ModelContext(container)
    timeZone = try #require(TimeZone(identifier: "UTC"))
    locale = Locale(identifier: "en_US")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.locale = locale
    self.calendar = calendar
    instant = try Self.parseDate("2026-01-15T12:00:00Z")
    earlierFutureDeadline = try #require(GoalDate(year: 2026, month: 1, day: 18))
    futureDeadline = try #require(GoalDate(year: 2026, month: 1, day: 20))
    laterFutureDeadline = try #require(GoalDate(year: 2026, month: 1, day: 21))
    earlierPastDeadline = try #require(GoalDate(year: 2026, month: 1, day: 10))
    pastDeadline = try #require(GoalDate(year: 2026, month: 1, day: 14))
  }

  func insertGoal(
    id: UUID = UUID(),
    name: String,
    kind: GoalKind = .accumulate,
    target: Int = 10,
    unit: String = "times",
    baseline: Int? = nil,
    deadline: GoalDate? = nil,
    closure: GoalClosure? = nil,
    createdAt: Date? = nil,
    entryAmounts: [Int] = [],
    readingValues: [Int] = []
  ) throws -> Goal {
    let goal = Goal(
      id: id,
      name: name,
      kind: kind,
      target: target,
      unit: unit,
      baseline: baseline,
      deadline: deadline,
      createdAt: createdAt ?? date("2026-01-01T00:00:00Z")
    )
    goal.closureRawValue = closure?.rawValue
    let assignedDate = try #require(GoalDate(year: 2026, month: 1, day: 15))
    goal.entries = entryAmounts.enumerated().map { index, amount in
      GoalEntry(
        amount: amount,
        assignedDate: assignedDate,
        appendedAt: instant.addingTimeInterval(TimeInterval(index)),
        appendSequence: index
      )
    }
    goal.readings = readingValues.enumerated().map { index, value in
      GoalReading(
        value: value,
        assignedDate: assignedDate,
        appendedAt: instant.addingTimeInterval(TimeInterval(index)),
        appendSequence: index
      )
    }
    context.insert(goal)
    try context.save()
    return goal
  }

  func model(
    goals: @escaping () throws -> [Goal],
    facts: @escaping (Goal) throws -> GoalRosterDomainFacts
  ) -> GoalRosterModel {
    GoalRosterModel(
      operations: GoalRosterOperations(
        fetchGoals: goals,
        facts: { goal, _, _, _ in try facts(goal) }
      )
    )
  }

  func refresh(_ model: GoalRosterModel) {
    model.refresh(at: instant, calendar: calendar, timeZone: timeZone, locale: locale)
  }

  func accumulateFacts(
    total: Int = 0,
    target: Int = 10,
    unit: String = "times",
    standing: GoalStandingSnapshot? = nil,
    closure: GoalClosure? = nil
  ) -> GoalRosterDomainFacts {
    GoalRosterDomainFacts(
      progress: .accumulate(
        AccumulateGoalProgress(
          total: total,
          target: target,
          unit: unit,
          normalizedProgress: Double(total) / Double(target)
        )
      ),
      standing: standing,
      closure: closure
    )
  }

  func measureFacts(
    baseline: Int,
    target: Int,
    current: Int,
    completed: Int,
    total: Int,
    normalized: Double
  ) -> GoalRosterDomainFacts {
    GoalRosterDomainFacts(
      progress: .measure(
        MeasureGoalProgress(
          baseline: baseline,
          target: target,
          currentValue: current,
          effectiveReadingID: nil,
          completedDistance: completed,
          totalDistance: total,
          unit: "kg",
          normalizedProgress: normalized
        )
      ),
      standing: standing(.onPace),
      closure: nil
    )
  }

  func standing(
    _ value: GoalStanding,
    nextTimeRefresh: Date? = nil
  ) -> GoalStandingSnapshot {
    GoalStandingSnapshot(
      standing: value,
      actualNormalizedProgress: 0,
      expectedNormalizedProgress: value == .onPace ? nil : 0.5,
      deadlineBoundary: value == .onPace ? nil : instant.addingTimeInterval(86_400),
      nextTimeRefresh: nextTimeRefresh
    )
  }

  func date(_ value: String) -> Date {
    try! Self.parseDate(value)
  }

  func uuid(_ value: String) -> UUID {
    UUID(uuidString: value)!
  }

  private static func parseDate(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    return try #require(formatter.date(from: value))
  }
}

private enum TestGoalRosterFailure: LocalizedError {
  case fetch
  case facts

  var errorDescription: String? {
    switch self {
    case .fetch: "Test fetch failure"
    case .facts: "Test fact failure"
    }
  }
}
