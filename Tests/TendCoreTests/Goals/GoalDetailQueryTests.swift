import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Goal detail query")
struct GoalDetailQueryTests {
  @Test("accumulate detail preserves over-achievement and orders entry history by civil date then sequence")
  func accumulateDetailIsCompleteAndOrdered() throws {
    let context = try makeContext()
    let goalID = UUID()
    let newestID = UUID()
    let sameDayEarlierID = UUID()
    let oldID = UUID()
    let goal = Goal(
      id: goalID,
      name: "Read",
      kind: .accumulate,
      target: 10,
      unit: "pages",
      createdAt: try instant("2024-01-01T12:00:00Z")
    )
    goal.entries = [
      GoalEntry(
        id: oldID,
        amount: 2,
        assignedDate: try goalDate("2024-01-01"),
        appendedAt: try instant("2024-01-09T00:00:00Z"),
        appendSequence: 0
      ),
      GoalEntry(
        id: sameDayEarlierID,
        amount: 5,
        assignedDate: try goalDate("2024-01-04"),
        appendedAt: try instant("2024-01-10T00:00:00Z"),
        appendSequence: 1
      ),
      GoalEntry(
        id: newestID,
        amount: 8,
        assignedDate: try goalDate("2024-01-04"),
        appendedAt: try instant("2024-01-02T00:00:00Z"),
        appendSequence: 2
      ),
    ]
    context.insert(goal)
    try context.save()

    let snapshot = try GoalDetailQuery(context: context).snapshot(
      for: goal,
      at: try instant("2024-01-04T20:00:00Z"),
      calendar: Calendar(identifier: .gregorian),
      timeZone: try timeZone("UTC")
    )

    #expect(
      snapshot.metadata
        == GoalDetailMetadata(
          id: goalID,
          name: "Read",
          kind: .accumulate,
          target: 10,
          unit: "pages",
          baseline: nil,
          deadline: nil,
          createdAt: try instant("2024-01-01T12:00:00Z"),
          closure: nil
        ))
    #expect(
      snapshot.progress
        == .accumulate(
          AccumulateGoalProgress(
            total: 15,
            target: 10,
            unit: "pages",
            normalizedProgress: 1.5
          )))
    #expect(snapshot.standing?.standing == .onPace)
    #expect(snapshot.standing?.expectedNormalizedProgress == nil)
    #expect(snapshot.availableAppendDestinations == [.today, .yesterday])
    #expect(
      snapshot.history
        == [
          .entry(
            GoalDetailEntry(
              id: GoalEntryIdentity(rawValue: newestID),
              assignedDate: try goalDate("2024-01-04"),
              amount: 8,
              appendedAt: try instant("2024-01-02T00:00:00Z"),
              appendSequence: 2,
              isDeleteEligible: true
            )),
          .entry(
            GoalDetailEntry(
              id: GoalEntryIdentity(rawValue: sameDayEarlierID),
              assignedDate: try goalDate("2024-01-04"),
              amount: 5,
              appendedAt: try instant("2024-01-10T00:00:00Z"),
              appendSequence: 1,
              isDeleteEligible: true
            )),
          .entry(
            GoalDetailEntry(
              id: GoalEntryIdentity(rawValue: oldID),
              assignedDate: try goalDate("2024-01-01"),
              amount: 2,
              appendedAt: try instant("2024-01-09T00:00:00Z"),
              appendSequence: 0,
              isDeleteEligible: false
            )),
        ])
  }

  @Test("increasing measure marks the latest date and sequence effective, not relationship or timestamp order")
  func increasingMeasureMarksEffectiveReading() throws {
    let context = try makeContext()
    let firstID = UUID()
    let effectiveID = UUID()
    let olderID = UUID()
    let goal = Goal(
      name: "Run",
      kind: .measure,
      target: 10,
      unit: "km",
      baseline: 0,
      createdAt: try instant("2024-02-01T00:00:00Z")
    )
    goal.readings = [
      GoalReading(
        id: olderID,
        value: 3,
        assignedDate: try goalDate("2024-02-02"),
        appendedAt: try instant("2024-02-09T00:00:00Z"),
        appendSequence: 2
      ),
      GoalReading(
        id: effectiveID,
        value: 14,
        assignedDate: try goalDate("2024-02-03"),
        appendedAt: try instant("2024-02-01T00:00:00Z"),
        appendSequence: 5
      ),
      GoalReading(
        id: firstID,
        value: 8,
        assignedDate: try goalDate("2024-02-03"),
        appendedAt: try instant("2024-02-10T00:00:00Z"),
        appendSequence: 4
      ),
    ]
    context.insert(goal)
    try context.save()

    let snapshot = try query(context, goal, at: "2024-02-03T12:00:00Z")

    #expect(
      snapshot.progress
        == .measure(
          MeasureGoalProgress(
            baseline: 0,
            target: 10,
            currentValue: 14,
            effectiveReadingID: effectiveID,
            completedDistance: 10,
            totalDistance: 10,
            unit: "km",
            normalizedProgress: 1
          )))
    #expect(
      snapshot.history
        == [
          .reading(
            GoalDetailReading(
              id: GoalReadingIdentity(rawValue: effectiveID),
              assignedDate: try goalDate("2024-02-03"),
              value: 14,
              appendedAt: try instant("2024-02-01T00:00:00Z"),
              appendSequence: 5,
              isDeleteEligible: true,
              isEffective: true
            )),
          .reading(
            GoalDetailReading(
              id: GoalReadingIdentity(rawValue: firstID),
              assignedDate: try goalDate("2024-02-03"),
              value: 8,
              appendedAt: try instant("2024-02-10T00:00:00Z"),
              appendSequence: 4,
              isDeleteEligible: true,
              isEffective: false
            )),
          .reading(
            GoalDetailReading(
              id: GoalReadingIdentity(rawValue: olderID),
              assignedDate: try goalDate("2024-02-02"),
              value: 3,
              appendedAt: try instant("2024-02-09T00:00:00Z"),
              appendSequence: 2,
              isDeleteEligible: true,
              isEffective: false
            )),
        ])
  }

  @Test("decreasing measure delegates clamped progress and truthful current value")
  func decreasingMeasureProgressIsDelegated() throws {
    let context = try makeContext()
    let readingID = UUID()
    let goal = Goal(
      name: "Weight",
      kind: .measure,
      target: 80,
      unit: "kg",
      baseline: 100,
      createdAt: try instant("2024-03-01T00:00:00Z")
    )
    goal.readings = [
      GoalReading(
        id: readingID,
        value: 70,
        assignedDate: try goalDate("2024-03-02"),
        appendedAt: try instant("2024-03-02T10:00:00Z"),
        appendSequence: 0
      )
    ]
    context.insert(goal)
    try context.save()

    let snapshot = try query(context, goal, at: "2024-03-02T12:00:00Z")

    #expect(
      snapshot.progress
        == .measure(
          MeasureGoalProgress(
            baseline: 100,
            target: 80,
            currentValue: 70,
            effectiveReadingID: readingID,
            completedDistance: 20,
            totalDistance: 20,
            unit: "kg",
            normalizedProgress: 1
          )))
  }

  @Test("standing exposes no-deadline, behind, and past-due open states")
  func standingStatesAreDelegated() throws {
    do {
      let context = try makeContext()
      let goal = try persistedGoal(in: context, deadline: nil)
      let snapshot = try query(context, goal, at: "2024-01-02T00:00:00Z")
      #expect(snapshot.standing?.standing == .onPace)
      #expect(snapshot.standing?.expectedNormalizedProgress == nil)
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        deadline: try goalDate("2024-01-10")
      )
      let snapshot = try query(context, goal, at: "2024-01-06T00:00:00Z")
      #expect(snapshot.standing?.standing == .behind)
      #expect(snapshot.standing?.expectedNormalizedProgress != nil)
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        deadline: try goalDate("2024-01-02")
      )
      let snapshot = try query(context, goal, at: "2024-01-03T00:00:00Z")
      #expect(snapshot.standing?.standing == .pastDue)
      #expect(snapshot.standing?.expectedNormalizedProgress == 1)
    }
  }

  @Test("harvested and let-go goals retain facts but expose no standing or mutation eligibility")
  func closedGoalsRemainReadableWithoutMutations() throws {
    for closure in [GoalClosure.harvested, .letGo] {
      let context = try makeContext()
      let goal = try persistedGoalWithEntry(in: context, assignedDate: "2024-01-02")
      goal.closureRawValue = closure.rawValue
      try context.save()

      let snapshot = try query(context, goal, at: "2024-01-02T12:00:00Z")

      #expect(snapshot.metadata.closure == closure)
      #expect(snapshot.progress == .accumulate(.init(total: 1, target: 10, unit: "pages", normalizedProgress: 0.1)))
      #expect(snapshot.standing == nil)
      #expect(snapshot.availableAppendDestinations.isEmpty)
      guard case .entry(let entry) = try #require(snapshot.history.first) else {
        Issue.record("Expected entry history")
        continue
      }
      #expect(!entry.isDeleteEligible)
    }
  }

  @Test("Today and Yesterday append destinations respect the local creation day")
  func appendEligibilityRespectsCreationDay() throws {
    let context = try makeContext()
    let goal = try persistedGoal(
      in: context,
      createdAt: try instant("2024-07-04T12:00:00Z")
    )

    let creationDay = try query(context, goal, at: "2024-07-04T20:00:00Z")
    let nextDay = try query(context, goal, at: "2024-07-05T00:00:00Z")

    #expect(creationDay.availableAppendDestinations == [.today])
    #expect(nextDay.availableAppendDestinations == [.today, .yesterday])
  }

  @Test("local Gregorian days drive eligibility across midnight, DST, zones, and caller calendars")
  func eligibilityUsesExplicitLocalGregorianDays() throws {
    do {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        createdAt: try instant("2024-07-04T23:00:00Z")
      )
      var nonGregorian = Calendar(identifier: .hebrew)
      nonGregorian.timeZone = try timeZone("UTC")
      let query = GoalDetailQuery(context: context)
      let evaluation = try instant("2024-07-05T00:30:00Z")

      let utc = try query.snapshot(
        for: goal,
        at: evaluation,
        calendar: nonGregorian,
        timeZone: try timeZone("UTC")
      )
      let losAngeles = try query.snapshot(
        for: goal,
        at: evaluation,
        calendar: nonGregorian,
        timeZone: try timeZone("America/Los_Angeles")
      )

      #expect(utc.availableAppendDestinations == [.today, .yesterday])
      #expect(losAngeles.availableAppendDestinations == [.today])
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoalWithEntry(
        in: context,
        assignedDate: "2024-03-09",
        createdAt: try instant("2024-03-08T12:00:00Z")
      )
      let snapshot = try GoalDetailQuery(context: context).snapshot(
        for: goal,
        at: try instant("2024-03-10T10:30:00Z"),
        calendar: Calendar(identifier: .iso8601),
        timeZone: try timeZone("America/Los_Angeles")
      )
      guard case .entry(let entry) = try #require(snapshot.history.first) else {
        Issue.record("Expected entry history")
        return
      }
      #expect(entry.isDeleteEligible)
    }
  }

  @Test("history before creation and after the evaluation local day is rejected")
  func impossibleHistoryDatesAreRejected() throws {
    do {
      let context = try makeContext()
      let goal = try persistedGoalWithEntry(
        in: context,
        assignedDate: "2024-01-01",
        createdAt: try instant("2024-01-02T00:00:00Z")
      )
      try expectQueryError(.historyBeforeCreation(try goalDate("2024-01-01"))) {
        _ = try query(context, goal, at: "2024-01-03T00:00:00Z")
      }
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoalWithEntry(in: context, assignedDate: "2024-01-04")
      try expectQueryError(.historyAfterEvaluation(try goalDate("2024-01-04"))) {
        _ = try query(context, goal, at: "2024-01-03T12:00:00Z")
      }
    }
  }

  @Test("corrupt dates, graphs, and duplicate presentation identities are rejected")
  func corruptPersistenceIsRejected() throws {
    do {
      let context = try makeContext()
      let goal = try persistedGoalWithEntry(in: context, assignedDate: "2024-01-01")
      goal.entries?.first?.assignedDateKey = "2024-13-01"
      try context.save()
      try expectQueryError(.progress(.invalidAssignedDate("2024-13-01"))) {
        _ = try query(context, goal, at: "2024-01-02T00:00:00Z")
      }
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoal(in: context)
      goal.entries = [
        GoalEntry(
          amount: 1,
          assignedDate: try goalDate("2024-01-01"),
          appendedAt: try instant("2024-01-01T01:00:00Z"),
          appendSequence: 0
        )
      ]
      try expectQueryError(.progress(.invalidGoalGraph)) {
        _ = try query(context, goal, at: "2024-01-02T00:00:00Z")
      }
    }

    do {
      let context = try makeContext()
      let goal = Goal(
        name: "Read",
        kind: .accumulate,
        target: 10,
        unit: "pages",
        createdAt: try instant("2024-01-01T00:00:00Z")
      )
      let duplicateID = UUID()
      goal.entries = [
        GoalEntry(
          id: duplicateID,
          amount: 1,
          assignedDate: try goalDate("2024-01-01"),
          appendedAt: try instant("2024-01-01T01:00:00Z"),
          appendSequence: 0
        ),
        GoalEntry(
          id: duplicateID,
          amount: 2,
          assignedDate: try goalDate("2024-01-02"),
          appendedAt: try instant("2024-01-02T01:00:00Z"),
          appendSequence: 1
        ),
      ]
      context.insert(goal)
      try context.save()
      try expectQueryError(.duplicateEntryIdentity(GoalEntryIdentity(rawValue: duplicateID))) {
        _ = try query(context, goal, at: "2024-01-02T12:00:00Z")
      }
    }

    do {
      let context = try makeContext()
      let goal = Goal(
        name: "Weight",
        kind: .measure,
        target: 80,
        unit: "kg",
        baseline: 100,
        createdAt: try instant("2024-01-01T00:00:00Z")
      )
      let duplicateID = UUID()
      goal.readings = [
        GoalReading(
          id: duplicateID,
          value: 99,
          assignedDate: try goalDate("2024-01-01"),
          appendedAt: try instant("2024-01-01T01:00:00Z"),
          appendSequence: 0
        ),
        GoalReading(
          id: duplicateID,
          value: 98,
          assignedDate: try goalDate("2024-01-02"),
          appendedAt: try instant("2024-01-02T01:00:00Z"),
          appendSequence: 1
        ),
      ]
      context.insert(goal)
      try context.save()
      try expectQueryError(.duplicateReadingIdentity(GoalReadingIdentity(rawValue: duplicateID))) {
        _ = try query(context, goal, at: "2024-01-02T12:00:00Z")
      }
    }
  }

  @Test("the query requires a goal owned by its exact context")
  func ownershipIsEnforced() throws {
    let owningContext = try makeContext()
    let foreignContext = try makeContext()
    let goal = try persistedGoal(in: owningContext)

    try expectQueryError(.progress(.foreignGoal)) {
      _ = try GoalDetailQuery(context: foreignContext).snapshot(
        for: goal,
        at: try instant("2024-01-02T00:00:00Z"),
        calendar: Calendar(identifier: .gregorian),
        timeZone: try timeZone("UTC")
      )
    }
  }

  @Test("failed validation neither mutates nor saves query state")
  func rejectionDoesNotMutate() throws {
    let context = try makeContext()
    let goal = try persistedGoalWithEntry(in: context, assignedDate: "2024-01-04")
    let originalIDs = goal.entries?.map(\.id)
    let originalDates = goal.entries?.map(\.assignedDateKey)
    let originalSequences = goal.entries?.map(\.appendSequence)
    #expect(!context.hasChanges)

    try expectQueryError(.historyAfterEvaluation(try goalDate("2024-01-04"))) {
      _ = try query(context, goal, at: "2024-01-03T00:00:00Z")
    }

    #expect(goal.entries?.map(\.id) == originalIDs)
    #expect(goal.entries?.map(\.assignedDateKey) == originalDates)
    #expect(goal.entries?.map(\.appendSequence) == originalSequences)
    #expect(!context.hasChanges)
  }

  @Test("successful queries preserve unrelated pending context work")
  func queryPreservesUnrelatedPendingWork() throws {
    let context = try makeContext()
    let goal = try persistedGoal(in: context)
    let unrelated = try persistedGoal(in: context, name: "Other")
    unrelated.name = "Changed but unsaved"
    #expect(context.hasChanges)

    _ = try query(context, goal, at: "2024-01-02T00:00:00Z")

    #expect(unrelated.name == "Changed but unsaved")
    #expect(context.hasChanges)
  }

  private func query(
    _ context: ModelContext,
    _ goal: Goal,
    at instantValue: String
  ) throws -> GoalDetailSnapshot {
    try GoalDetailQuery(context: context).snapshot(
      for: goal,
      at: instant(instantValue),
      calendar: Calendar(identifier: .gregorian),
      timeZone: timeZone("UTC")
    )
  }

  private func persistedGoal(
    in context: ModelContext,
    name: String = "Read",
    deadline: GoalDate? = nil,
    createdAt: Date = Date(timeIntervalSince1970: 1_704_067_200)
  ) throws -> Goal {
    let goal = Goal(
      name: name,
      kind: .accumulate,
      target: 10,
      unit: "pages",
      deadline: deadline,
      createdAt: createdAt
    )
    context.insert(goal)
    try context.save()
    return goal
  }

  private func persistedGoalWithEntry(
    in context: ModelContext,
    assignedDate: String,
    createdAt: Date = Date(timeIntervalSince1970: 1_704_067_200)
  ) throws -> Goal {
    let goal = Goal(
      name: "Read",
      kind: .accumulate,
      target: 10,
      unit: "pages",
      createdAt: createdAt
    )
    goal.entries = [
      GoalEntry(
        amount: 1,
        assignedDate: try goalDate(assignedDate),
        appendedAt: createdAt,
        appendSequence: 0
      )
    ]
    context.insert(goal)
    try context.save()
    return goal
  }

  private func expectQueryError(
    _ expected: GoalDetailQueryError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected GoalDetailQueryError: \(expected)")
    } catch let error as GoalDetailQueryError {
      #expect(error == expected)
    }
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private func timeZone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }

  private func goalDate(_ value: String) throws -> GoalDate {
    try #require(GoalDate(rawValue: value))
  }
}
