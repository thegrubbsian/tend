#if DEBUG
  import Foundation
  import SwiftData
  import TendCore

  enum GoalRosterUITestFixtureError: Error, Equatable {
    case invalidStableIdentifier(String)
    case unexpectedState(String)
  }

  @MainActor
  enum GoalRosterUITestFixture {
    static func seed(
      context: ModelContext,
      at launchInstant: Date,
      timeZone: TimeZone
    ) throws {
      let creation = GoalCreationOperations(context: context)
      let progress = GoalProgressOperations(context: context)
      let lifecycle = GoalLifecycleOperations(context: context)
      let expectedLaunchInstant = try instant("2026-01-15T17:00:00Z")
      guard launchInstant == expectedLaunchInstant else {
        throw GoalRosterUITestFixtureError.unexpectedState("launch-instant")
      }
      let createdAt = try instant("2026-01-01T17:00:00Z")
      let upcomingDeadline = try goalDate("2026-01-31")
      let elapsedDeadline = try goalDate("2026-01-14")

      let accumulate = try create(
        id: "10000000-0000-0000-0000-000000000001",
        fields: GoalCreationFields(
          name: "Fund neighborhood science kits for every after-school classroom",
          kind: .accumulate,
          target: 2_000_000,
          unit: "dollars pledged across neighborhoods"
        ),
        creation: creation,
        at: createdAt,
        timeZone: timeZone
      )
      let accumulateEntry = try progress.append(
        amount: 1_250_000,
        to: accumulate,
        destination: .today,
        at: launchInstant,
        timeZone: timeZone
      )
      accumulateEntry.id = try identifier("20000000-0000-0000-0000-000000000001")

      let increasing = try create(
        id: "10000000-0000-0000-0000-000000000002",
        fields: GoalCreationFields(
          name: "Grow oak seedlings",
          kind: .measure,
          target: 200,
          unit: "centimeters",
          baseline: 120,
          deadline: upcomingDeadline
        ),
        creation: creation,
        at: createdAt,
        timeZone: timeZone
      )
      let increasingReading = try progress.append(
        value: 150,
        to: increasing,
        destination: .today,
        at: launchInstant,
        timeZone: timeZone
      )
      increasingReading.id = try identifier("30000000-0000-0000-0000-000000000001")

      let decreasing = try create(
        id: "10000000-0000-0000-0000-000000000003",
        fields: GoalCreationFields(
          name: "Lower resting heart rate",
          kind: .measure,
          target: 60,
          unit: "beats per minute",
          baseline: 80,
          deadline: upcomingDeadline
        ),
        creation: creation,
        at: createdAt,
        timeZone: timeZone
      )
      let decreasingReading = try progress.append(
        value: 70,
        to: decreasing,
        destination: .today,
        at: launchInstant,
        timeZone: timeZone
      )
      decreasingReading.id = try identifier("30000000-0000-0000-0000-000000000002")

      let pastDue = try create(
        id: "10000000-0000-0000-0000-000000000004",
        fields: GoalCreationFields(
          name: "Submit winter grant application",
          kind: .accumulate,
          target: 10,
          unit: "sections",
          deadline: elapsedDeadline
        ),
        creation: creation,
        at: createdAt,
        timeZone: timeZone
      )
      let pastDueEntry = try progress.append(
        amount: 7,
        to: pastDue,
        destination: .today,
        at: launchInstant,
        timeZone: timeZone
      )
      pastDueEntry.id = try identifier("20000000-0000-0000-0000-000000000002")

      let harvested = try create(
        id: "10000000-0000-0000-0000-000000000005",
        fields: GoalCreationFields(
          name: "Read the field guide",
          kind: .accumulate,
          target: 12,
          unit: "chapters"
        ),
        creation: creation,
        at: createdAt,
        timeZone: timeZone
      )
      let harvestedEntry = try progress.append(
        amount: 12,
        to: harvested,
        destination: .today,
        at: launchInstant,
        timeZone: timeZone
      )
      harvestedEntry.id = try identifier("20000000-0000-0000-0000-000000000003")
      try lifecycle.close(harvested, as: .harvested)

      let letGo = try create(
        id: "10000000-0000-0000-0000-000000000006",
        fields: GoalCreationFields(
          name: "Walk the coastal trail",
          kind: .measure,
          target: 100,
          unit: "miles",
          baseline: 0
        ),
        creation: creation,
        at: createdAt,
        timeZone: timeZone
      )
      let letGoReading = try progress.append(
        value: 20,
        to: letGo,
        destination: .today,
        at: launchInstant,
        timeZone: timeZone
      )
      letGoReading.id = try identifier("30000000-0000-0000-0000-000000000003")
      try lifecycle.close(letGo, as: .letGo)

      try context.save()
      try verify(
        goals: [accumulate, increasing, decreasing, pastDue, harvested, letGo],
        context: context,
        launchInstant: launchInstant,
        timeZone: timeZone
      )
    }

    private static func create(
      id: String,
      fields: GoalCreationFields,
      creation: GoalCreationOperations,
      at instant: Date,
      timeZone: TimeZone
    ) throws -> Goal {
      let goal = try creation.create(fields: fields, at: instant, timeZone: timeZone)
      goal.id = try identifier(id)
      return goal
    }

    private static func verify(
      goals: [Goal],
      context: ModelContext,
      launchInstant: Date,
      timeZone: TimeZone
    ) throws {
      guard goals.count == 6,
        try context.fetchCount(FetchDescriptor<Goal>()) == 6,
        try context.fetchCount(FetchDescriptor<GoalEntry>()) == 3,
        try context.fetchCount(FetchDescriptor<GoalReading>()) == 3
      else {
        throw GoalRosterUITestFixtureError.unexpectedState("graph-counts")
      }

      let progress = GoalProgressComputation(context: context)
      let standing = GoalStandingComputation()
      var calendar = Calendar(identifier: .gregorian)
      calendar.locale = Locale(identifier: "en_US_POSIX")
      calendar.timeZone = timeZone
      let expectedStandings: [GoalStanding?] = [
        .onPace, .behind, .onPace, .pastDue, nil, nil,
      ]
      let expectedClosures: [GoalClosure?] = [nil, nil, nil, nil, .harvested, .letGo]

      for index in goals.indices {
        let goal = goals[index]
        let snapshot = try progress.snapshot(for: goal)
        let actualStanding = try standing.snapshot(
          for: goal,
          progress: snapshot,
          at: launchInstant,
          calendar: calendar,
          timeZone: timeZone
        )?.standing
        guard actualStanding == expectedStandings[index],
          try goal.checkedClosure == expectedClosures[index]
        else {
          throw GoalRosterUITestFixtureError.unexpectedState(goal.name)
        }
      }
    }

    private static func identifier(_ value: String) throws -> UUID {
      guard let id = UUID(uuidString: value) else {
        throw GoalRosterUITestFixtureError.invalidStableIdentifier(value)
      }
      return id
    }

    private static func instant(_ value: String) throws -> Date {
      guard let date = ISO8601DateFormatter().date(from: value) else {
        throw GoalRosterUITestFixtureError.unexpectedState(value)
      }
      return date
    }

    private static func goalDate(_ value: String) throws -> GoalDate {
      guard let date = GoalDate(rawValue: value) else {
        throw GoalRosterUITestFixtureError.unexpectedState(value)
      }
      return date
    }
  }
#endif
