#if DEBUG
  import Foundation
  import SwiftData
  import TendCore

  enum TodayGoalUITestFixtureError: Error, Equatable {
    case invalidStableIdentifier(String)
    case invalidStableDate(String)
    case unexpectedState(String)
  }

  @MainActor
  enum TodayGoalUITestFixture {
    enum Variant {
      case mixed
      case allTended
      case firstLaunch
      case inactive
      case failure
      case journey
      case empty
    }

    static func seed(
      _ variant: Variant,
      context: ModelContext,
      at launchInstant: Date,
      timeZone: TimeZone
    ) throws {
      let expectedLaunchInstant = try instant("2026-08-05T19:00:00Z")
      guard launchInstant == expectedLaunchInstant else {
        throw TodayGoalUITestFixtureError.unexpectedState("launch-instant")
      }

      switch variant {
      case .mixed:
        try TodayDashboardUITestFixture.seed(
          .mixed,
          context: context,
          at: launchInstant,
          timeZone: timeZone
        )
      case .allTended:
        try TodayDashboardUITestFixture.seed(
          .allTended,
          context: context,
          at: launchInstant,
          timeZone: timeZone
        )
      case .firstLaunch:
        break
      case .inactive:
        try TodayDashboardUITestFixture.seed(
          .inactive,
          context: context,
          at: launchInstant,
          timeZone: timeZone
        )
      case .failure:
        try TodayDashboardUITestFixture.seed(
          .mixed,
          context: context,
          at: launchInstant,
          timeZone: timeZone
        )
      case .journey:
        try TodayDashboardUITestFixture.seed(
          .allTended,
          context: context,
          at: launchInstant,
          timeZone: timeZone
        )
      case .empty:
        try TodayDashboardUITestFixture.seed(
          .mixed,
          context: context,
          at: launchInstant,
          timeZone: timeZone
        )
      }

      let seeder = Seeder(context: context, launchInstant: launchInstant, timeZone: timeZone)
      switch variant {
      case .mixed:
        try seeder.seedMixed()
      case .allTended:
        try seeder.seedAllTended()
      case .firstLaunch:
        try seeder.seedFirstLaunch()
      case .inactive:
        try seeder.seedInactive()
      case .failure:
        try seeder.seedFailure()
      case .journey:
        try seeder.seedJourney()
      case .empty:
        try seeder.seedEmpty()
      }
    }

    private struct Seeder {
      let context: ModelContext
      let launchInstant: Date
      let timeZone: TimeZone
      let creation: GoalCreationOperations
      let progress: GoalProgressOperations
      let lifecycle: GoalLifecycleOperations

      init(context: ModelContext, launchInstant: Date, timeZone: TimeZone) {
        self.context = context
        self.launchInstant = launchInstant
        self.timeZone = timeZone
        creation = GoalCreationOperations(context: context)
        progress = GoalProgressOperations(context: context)
        lifecycle = GoalLifecycleOperations(context: context)
      }

      func seedMixed() throws {
        let standardCreation = try instant("2026-07-01T19:00:00Z")
        let nearCreation = try instant("2026-07-30T19:00:00Z")

        _ = try accumulate(
          goalID: "71abcdef-0000-0000-0000-000000000001",
          entryID: "72000000-0000-0000-0000-000000000001",
          name: "Behind practice goal",
          target: 10,
          unit: "sessions",
          deadline: "2026-08-12",
          createdAt: standardCreation,
          amount: 2
        )
        _ = try measure(
          goalID: "71000000-0000-0000-0000-000000000002",
          readingID: "73000000-0000-0000-0000-000000000002",
          name: "Near on-pace measure",
          target: 200,
          unit: "pages",
          baseline: 100,
          deadline: "2026-08-09",
          createdAt: nearCreation,
          value: 160
        )
        _ = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000003",
          entryID: "72000000-0000-0000-0000-000000000003",
          name: "Past-due grant goal",
          target: 10,
          unit: "sections",
          deadline: "2026-08-04",
          createdAt: standardCreation,
          amount: 7
        )
        _ = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000004",
          entryID: "72000000-0000-0000-0000-000000000004",
          name: "Distant on-pace goal",
          target: 10,
          unit: "lessons",
          deadline: "2026-08-20",
          createdAt: nearCreation,
          amount: 8
        )
        _ = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000005",
          entryID: "72000000-0000-0000-0000-000000000005",
          name: "No-deadline goal",
          target: 12,
          unit: "letters",
          deadline: nil,
          createdAt: standardCreation,
          amount: 2
        )
        let harvested = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000006",
          entryID: "72000000-0000-0000-0000-000000000006",
          name: "Harvested goal",
          target: 4,
          unit: "milestones",
          deadline: "2026-08-09",
          createdAt: standardCreation,
          amount: 4
        )
        try lifecycle.close(harvested, as: .harvested)
        let letGo = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000007",
          entryID: "72000000-0000-0000-0000-000000000007",
          name: "Let-go goal",
          target: 5,
          unit: "routes",
          deadline: "2026-08-09",
          createdAt: standardCreation,
          amount: 1
        )
        try lifecycle.close(letGo, as: .letGo)

        try finish(
          goalIDs: [
            "71abcdef-0000-0000-0000-000000000001",
            "71000000-0000-0000-0000-000000000002",
            "71000000-0000-0000-0000-000000000003",
            "71000000-0000-0000-0000-000000000004",
            "71000000-0000-0000-0000-000000000005",
            "71000000-0000-0000-0000-000000000006",
            "71000000-0000-0000-0000-000000000007",
          ],
          entryCount: 6,
          readingCount: 1
        )
      }

      func seedAllTended() throws {
        _ = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000101",
          entryID: "72000000-0000-0000-0000-000000000101",
          name: "Finish research chapters",
          target: 8,
          unit: "chapters",
          deadline: "2026-08-12",
          createdAt: try instant("2026-07-01T19:00:00Z"),
          amount: 1
        )
        try finish(
          goalIDs: ["71000000-0000-0000-0000-000000000101"],
          entryCount: 1,
          readingCount: 0
        )
      }

      func seedFirstLaunch() throws {
        _ = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000201",
          entryID: "72000000-0000-0000-0000-000000000201",
          name: "Draft the field plan",
          target: 6,
          unit: "drafts",
          deadline: "2026-08-12",
          createdAt: try instant("2026-07-01T19:00:00Z"),
          amount: 1
        )
        try finish(
          goalIDs: ["71000000-0000-0000-0000-000000000201"],
          entryCount: 1,
          readingCount: 0
        )
      }

      func seedInactive() throws {
        _ = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000301",
          entryID: "72000000-0000-0000-0000-000000000301",
          name: "Visit every preserve",
          target: 9,
          unit: "visits",
          deadline: "2026-08-12",
          createdAt: try instant("2026-07-01T19:00:00Z"),
          amount: 2
        )
        try finish(
          goalIDs: ["71000000-0000-0000-0000-000000000301"],
          entryCount: 1,
          readingCount: 0
        )
      }

      func seedFailure() throws {
        let createdAt = try instant("2026-07-01T19:00:00Z")
        let malformed = try accumulate(
          goalID: "71abcdef-0000-0000-0000-000000000401",
          entryID: "72000000-0000-0000-0000-000000000401",
          name: "Unavailable planning goal",
          target: 4,
          unit: "plans",
          deadline: "2026-08-09",
          createdAt: createdAt,
          amount: 1
        )
        _ = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000402",
          entryID: "72000000-0000-0000-0000-000000000402",
          name: "Failure past-due goal",
          target: 5,
          unit: "reports",
          deadline: "2026-08-04",
          createdAt: createdAt,
          amount: 3
        )
        _ = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000403",
          entryID: "72000000-0000-0000-0000-000000000403",
          name: "Failure near goal",
          target: 10,
          unit: "reviews",
          deadline: "2026-08-09",
          createdAt: try instant("2026-07-30T19:00:00Z"),
          amount: 8
        )

        malformed.deadlineKey = "2026-99-99"
        try finish(
          goalIDs: [
            "71abcdef-0000-0000-0000-000000000401",
            "71000000-0000-0000-0000-000000000402",
            "71000000-0000-0000-0000-000000000403",
          ],
          entryCount: 3,
          readingCount: 0
        )
        guard malformed.deadlineKey == "2026-99-99" else {
          throw TodayGoalUITestFixtureError.unexpectedState("malformed-goal")
        }
      }

      func seedJourney() throws {
        _ = try accumulate(
          goalID: "71abcdef-0000-0000-0000-000000000501",
          entryID: "72000000-0000-0000-0000-000000000501",
          name: "Journey practice goal",
          target: 10,
          unit: "sessions",
          deadline: "2026-08-20",
          createdAt: try instant("2026-07-01T19:00:00Z"),
          amount: 1
        )
        try finish(
          goalIDs: ["71abcdef-0000-0000-0000-000000000501"],
          entryCount: 1,
          readingCount: 0
        )
      }

      func seedEmpty() throws {
        let standardCreation = try instant("2026-07-01T19:00:00Z")
        _ = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000601",
          entryID: "72000000-0000-0000-0000-000000000601",
          name: "Empty distant goal",
          target: 10,
          unit: "lessons",
          deadline: "2026-08-20",
          createdAt: try instant("2026-07-30T19:00:00Z"),
          amount: 8
        )
        _ = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000602",
          entryID: "72000000-0000-0000-0000-000000000602",
          name: "Empty no-deadline goal",
          target: 10,
          unit: "notes",
          deadline: nil,
          createdAt: standardCreation,
          amount: 2
        )
        let harvested = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000603",
          entryID: "72000000-0000-0000-0000-000000000603",
          name: "Empty harvested goal",
          target: 3,
          unit: "steps",
          deadline: "2026-08-09",
          createdAt: standardCreation,
          amount: 3
        )
        try lifecycle.close(harvested, as: .harvested)
        let letGo = try accumulate(
          goalID: "71000000-0000-0000-0000-000000000604",
          entryID: "72000000-0000-0000-0000-000000000604",
          name: "Empty let-go goal",
          target: 4,
          unit: "trips",
          deadline: "2026-08-09",
          createdAt: standardCreation,
          amount: 1
        )
        try lifecycle.close(letGo, as: .letGo)

        try finish(
          goalIDs: (601...604).map { "71000000-0000-0000-0000-000000000\($0)" },
          entryCount: 4,
          readingCount: 0
        )
      }

      private func accumulate(
        goalID: String,
        entryID: String,
        name: String,
        target: Int,
        unit: String,
        deadline: String?,
        createdAt: Date,
        amount: Int
      ) throws -> Goal {
        let goal = try create(
          id: goalID,
          fields: GoalCreationFields(
            name: name,
            kind: .accumulate,
            target: target,
            unit: unit,
            deadline: try deadline.map { try goalDate($0) }
          ),
          at: createdAt
        )
        let entry = try progress.append(
          amount: amount,
          to: goal,
          destination: .today,
          at: launchInstant,
          timeZone: timeZone
        )
        entry.id = try identifier(entryID)
        return goal
      }

      private func measure(
        goalID: String,
        readingID: String,
        name: String,
        target: Int,
        unit: String,
        baseline: Int,
        deadline: String,
        createdAt: Date,
        value: Int
      ) throws -> Goal {
        let goal = try create(
          id: goalID,
          fields: GoalCreationFields(
            name: name,
            kind: .measure,
            target: target,
            unit: unit,
            baseline: baseline,
            deadline: try goalDate(deadline)
          ),
          at: createdAt
        )
        let reading = try progress.append(
          value: value,
          to: goal,
          destination: .today,
          at: launchInstant,
          timeZone: timeZone
        )
        reading.id = try identifier(readingID)
        return goal
      }

      private func create(
        id: String,
        fields: GoalCreationFields,
        at instant: Date
      ) throws -> Goal {
        let goal = try creation.create(fields: fields, at: instant, timeZone: timeZone)
        goal.id = try identifier(id)
        return goal
      }

      private func finish(
        goalIDs: [String],
        entryCount: Int,
        readingCount: Int
      ) throws {
        try context.save()
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let entries = try context.fetch(FetchDescriptor<GoalEntry>())
        let readings = try context.fetch(FetchDescriptor<GoalReading>())
        let expectedIDs = try Set(goalIDs.map { try identifier($0) })
        guard goals.count == goalIDs.count,
          Set(goals.map(\.id)) == expectedIDs,
          entries.count == entryCount,
          readings.count == readingCount
        else {
          throw TodayGoalUITestFixtureError.unexpectedState("goal-graph")
        }
      }
    }

    private static func identifier(_ value: String) throws -> UUID {
      guard let id = UUID(uuidString: value) else {
        throw TodayGoalUITestFixtureError.invalidStableIdentifier(value)
      }
      return id
    }

    private static func instant(_ value: String) throws -> Date {
      guard let date = ISO8601DateFormatter().date(from: value) else {
        throw TodayGoalUITestFixtureError.unexpectedState(value)
      }
      return date
    }

    private static func goalDate(_ value: String) throws -> LocalDate {
      guard let date = LocalDate(rawValue: value) else {
        throw TodayGoalUITestFixtureError.invalidStableDate(value)
      }
      return date
    }
  }
#endif
