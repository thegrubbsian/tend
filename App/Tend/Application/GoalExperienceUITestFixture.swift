#if DEBUG
  import Foundation
  import SwiftData
  import TendCore

  enum GoalExperienceUITestFixtureError: Error, Equatable {
    case invalidStableIdentifier(String)
    case unexpectedState(String)
  }

  @MainActor
  enum GoalExperienceUITestFixture {
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
        throw GoalExperienceUITestFixtureError.unexpectedState("launch-instant")
      }
      let createdAt = try instant("2026-01-01T17:00:00Z")
      let upcomingDeadline = try goalDate("2026-01-31")
      let elapsedDeadline = try goalDate("2026-01-14")

      let piano = try create(
        id: "11000000-0000-0000-0000-000000000001",
        fields: GoalCreationFields(
          name: "Practice piano hours",
          kind: .accumulate,
          target: 100,
          unit: "hours"
        ),
        creation: creation,
        at: createdAt,
        timeZone: timeZone
      )
      let historicalPianoEntry = try progress.append(
        amount: 95,
        to: piano,
        destination: .today,
        at: createdAt,
        timeZone: timeZone
      )
      historicalPianoEntry.id = try identifier("21000000-0000-0000-0000-000000000001")
      let currentPianoEntry = try progress.append(
        amount: 10,
        to: piano,
        destination: .today,
        at: launchInstant,
        timeZone: timeZone
      )
      currentPianoEntry.id = try identifier("21000000-0000-0000-0000-000000000002")

      let increasing = try create(
        id: "11000000-0000-0000-0000-000000000002",
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
      let firstIncreasingReading = try progress.append(
        value: 140,
        to: increasing,
        destination: .today,
        at: launchInstant,
        timeZone: timeZone
      )
      firstIncreasingReading.id = try identifier("31000000-0000-0000-0000-000000000001")
      let secondIncreasingReading = try progress.append(
        value: 150,
        to: increasing,
        destination: .today,
        at: launchInstant,
        timeZone: timeZone
      )
      secondIncreasingReading.id = try identifier("31000000-0000-0000-0000-000000000002")

      let decreasing = try create(
        id: "11000000-0000-0000-0000-000000000003",
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
      decreasingReading.id = try identifier("31000000-0000-0000-0000-000000000003")

      let pastDue = try create(
        id: "11000000-0000-0000-0000-000000000004",
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
      pastDueEntry.id = try identifier("21000000-0000-0000-0000-000000000003")

      let harvested = try create(
        id: "11000000-0000-0000-0000-000000000005",
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
      harvestedEntry.id = try identifier("21000000-0000-0000-0000-000000000004")
      try lifecycle.close(harvested, as: .harvested)

      let letGo = try create(
        id: "11000000-0000-0000-0000-000000000006",
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
      letGoReading.id = try identifier("31000000-0000-0000-0000-000000000004")
      try lifecycle.close(letGo, as: .letGo)

      let goals = [piano, increasing, decreasing, pastDue, harvested, letGo]
      let entries = [historicalPianoEntry, currentPianoEntry, pastDueEntry, harvestedEntry]
      let readings = [
        firstIncreasingReading, secondIncreasingReading, decreasingReading, letGoReading,
      ]
      try context.save()
      try verify(
        goals: goals,
        entries: entries,
        readings: readings,
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
      entries: [GoalEntry],
      readings: [GoalReading],
      context: ModelContext,
      launchInstant: Date,
      timeZone: TimeZone
    ) throws {
      let expectedGoalIDs = [
        "11000000-0000-0000-0000-000000000001",
        "11000000-0000-0000-0000-000000000002",
        "11000000-0000-0000-0000-000000000003",
        "11000000-0000-0000-0000-000000000004",
        "11000000-0000-0000-0000-000000000005",
        "11000000-0000-0000-0000-000000000006",
      ]
      let expectedEntryIDs = [
        "21000000-0000-0000-0000-000000000001",
        "21000000-0000-0000-0000-000000000002",
        "21000000-0000-0000-0000-000000000003",
        "21000000-0000-0000-0000-000000000004",
      ]
      let expectedReadingIDs = [
        "31000000-0000-0000-0000-000000000001",
        "31000000-0000-0000-0000-000000000002",
        "31000000-0000-0000-0000-000000000003",
        "31000000-0000-0000-0000-000000000004",
      ]
      guard goals.count == 6,
        entries.count == 4,
        readings.count == 4,
        try context.fetchCount(FetchDescriptor<Goal>()) == 6,
        try context.fetchCount(FetchDescriptor<GoalEntry>()) == 4,
        try context.fetchCount(FetchDescriptor<GoalReading>()) == 4,
        goals.map(\.id.uuidString) == expectedGoalIDs,
        entries.map(\.id.uuidString) == expectedEntryIDs,
        readings.map(\.id.uuidString) == expectedReadingIDs,
        goals.map(\.name) == [
          "Practice piano hours",
          "Grow oak seedlings",
          "Lower resting heart rate",
          "Submit winter grant application",
          "Read the field guide",
          "Walk the coastal trail",
        ],
        entries.map(\.amount) == [95, 10, 7, 12],
        entries.map(\.assignedDateKey) == [
          "2026-01-01", "2026-01-15", "2026-01-15", "2026-01-15",
        ],
        entries.map(\.appendSequence) == [0, 1, 0, 0],
        entries.compactMap({ $0.goal?.id.uuidString }) == [
          expectedGoalIDs[0], expectedGoalIDs[0], expectedGoalIDs[3], expectedGoalIDs[4],
        ],
        readings.map(\.value) == [140, 150, 70, 20],
        readings.allSatisfy({ $0.assignedDateKey == "2026-01-15" }),
        readings.map(\.appendSequence) == [0, 1, 0, 0],
        readings.compactMap({ $0.goal?.id.uuidString }) == [
          expectedGoalIDs[1], expectedGoalIDs[1], expectedGoalIDs[2], expectedGoalIDs[5],
        ]
      else {
        throw GoalExperienceUITestFixtureError.unexpectedState("graph")
      }

      let expectedProgress: [GoalProgressSnapshot] = [
        .accumulate(
          AccumulateGoalProgress(
            total: 105,
            target: 100,
            unit: "hours",
            normalizedProgress: 1.05
          )
        ),
        .measure(
          MeasureGoalProgress(
            baseline: 120,
            target: 200,
            currentValue: 150,
            effectiveReadingID: readings[1].id,
            completedDistance: 30,
            totalDistance: 80,
            unit: "centimeters",
            normalizedProgress: 0.375
          )
        ),
        .measure(
          MeasureGoalProgress(
            baseline: 80,
            target: 60,
            currentValue: 70,
            effectiveReadingID: readings[2].id,
            completedDistance: 10,
            totalDistance: 20,
            unit: "beats per minute",
            normalizedProgress: 0.5
          )
        ),
        .accumulate(
          AccumulateGoalProgress(
            total: 7,
            target: 10,
            unit: "sections",
            normalizedProgress: 0.7
          )
        ),
        .accumulate(
          AccumulateGoalProgress(
            total: 12,
            target: 12,
            unit: "chapters",
            normalizedProgress: 1
          )
        ),
        .measure(
          MeasureGoalProgress(
            baseline: 0,
            target: 100,
            currentValue: 20,
            effectiveReadingID: readings[3].id,
            completedDistance: 20,
            totalDistance: 100,
            unit: "miles",
            normalizedProgress: 0.2
          )
        ),
      ]
      let expectedStandings: [GoalStanding?] = [
        .onPace, .behind, .onPace, .pastDue, nil, nil,
      ]
      let expectedClosures: [GoalClosure?] = [nil, nil, nil, nil, .harvested, .letGo]
      let progress = GoalProgressComputation(context: context)
      let standing = GoalStandingComputation()
      var calendar = Calendar(identifier: .gregorian)
      calendar.locale = Locale(identifier: "en_US_POSIX")
      calendar.timeZone = timeZone

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
        guard snapshot == expectedProgress[index],
          actualStanding == expectedStandings[index],
          try goal.checkedClosure == expectedClosures[index]
        else {
          throw GoalExperienceUITestFixtureError.unexpectedState(goal.name)
        }
      }
    }

    private static func identifier(_ value: String) throws -> UUID {
      guard let id = UUID(uuidString: value) else {
        throw GoalExperienceUITestFixtureError.invalidStableIdentifier(value)
      }
      return id
    }

    private static func instant(_ value: String) throws -> Date {
      guard let date = ISO8601DateFormatter().date(from: value) else {
        throw GoalExperienceUITestFixtureError.unexpectedState(value)
      }
      return date
    }

    private static func goalDate(_ value: String) throws -> LocalDate {
      guard let date = LocalDate(rawValue: value) else {
        throw GoalExperienceUITestFixtureError.unexpectedState(value)
      }
      return date
    }
  }
#endif
