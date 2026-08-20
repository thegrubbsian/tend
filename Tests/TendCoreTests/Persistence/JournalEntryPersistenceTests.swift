import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Journal entry persistence")
struct JournalEntryPersistenceTests {
  @Test("journal values and permissive body shapes survive reopen exactly")
  func journalValuesAndBodyShapesSurviveReopen() throws {
    let location = try makeTemporaryStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let baseCreatedAt = Date(timeIntervalSince1970: 1_775_000_001)
    let bodies = [
      "",
      "   \n\t",
      "First line\nSecond line\n第三行 🌱",
      String(repeating: "field journal 🌿\n", count: 16_384),
    ]
    let ids = (1...4).map {
      uuid("a1000000-0000-0000-0000-00000000000\($0)")
    }
    let dayKeys = (1...4).map { "2026-03-0\($0)" }
    let createdAt = (0..<4).map {
      baseCreatedAt.addingTimeInterval(TimeInterval($0))
    }
    let editedAt = (0..<4).map {
      baseCreatedAt.addingTimeInterval(TimeInterval($0 + 10))
    }

    do {
      let container = try TendModelContainer.fileBacked(at: location.store)
      for index in bodies.indices {
        container.mainContext.insert(
          JournalEntry(
            id: ids[index],
            day: try LocalDate(validating: dayKeys[index]),
            body: bodies[index],
            createdAt: createdAt[index],
            editedAt: editedAt[index]
          ))
      }
      try container.mainContext.save()
    }

    let reopened = try TendModelContainer.fileBacked(at: location.store)
    let fetched = try ModelContext(reopened).fetch(FetchDescriptor<JournalEntry>()).sorted {
      $0.dayKey < $1.dayKey
    }
    #expect(fetched.map(\.id) == ids)
    #expect(fetched.map(\.dayKey) == dayKeys)
    #expect(fetched.map(\.body) == bodies)
    #expect(fetched.map(\.createdAt) == createdAt)
    #expect(fetched.map(\.editedAt) == editedAt)
  }

  @Test("duplicate and malformed days remain loadable across reopen")
  func duplicateAndMalformedDaysRemainLoadableAcrossReopen() throws {
    let location = try makeTemporaryStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let day = try #require(LocalDate(rawValue: "2026-03-07"))

    do {
      let container = try TendModelContainer.fileBacked(at: location.store)
      let first = JournalEntry(
        id: uuid("a2000000-0000-0000-0000-000000000001"),
        day: day,
        body: "First",
        createdAt: Date(timeIntervalSince1970: 1_775_100_001),
        editedAt: Date(timeIntervalSince1970: 1_775_100_001)
      )
      let duplicate = JournalEntry(
        id: uuid("a2000000-0000-0000-0000-000000000002"),
        day: day,
        body: "Duplicate",
        createdAt: Date(timeIntervalSince1970: 1_775_100_002),
        editedAt: Date(timeIntervalSince1970: 1_775_100_002)
      )
      let malformed = JournalEntry(
        id: uuid("a2000000-0000-0000-0000-000000000003"),
        day: day,
        body: "Imported",
        createdAt: Date(timeIntervalSince1970: 1_775_100_003),
        editedAt: Date(timeIntervalSince1970: 1_775_100_003)
      )
      malformed.dayKey = "today"
      container.mainContext.insert(first)
      container.mainContext.insert(duplicate)
      container.mainContext.insert(malformed)
      try container.mainContext.save()
    }

    let reopened = try TendModelContainer.fileBacked(at: location.store)
    let fetched = try ModelContext(reopened).fetch(FetchDescriptor<JournalEntry>())
    #expect(fetched.count == 3)
    #expect(fetched.filter { $0.dayKey == "2026-03-07" }.count == 2)
    #expect(
      fetched.first { $0.id == uuid("a2000000-0000-0000-0000-000000000003") }?.dayKey == "today")
  }

  @Test("version three graphs migrate unchanged before Journal persistence")
  func versionThreeGraphsMigrateBeforeJournalPersistence() throws {
    let location = try makeTemporaryStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let expected = try createVersionThreeFixture(at: location.store)

    do {
      let migrated = try TendModelContainer.fileBacked(at: location.store)
      try verifyVersionThreeFixture(in: migrated, expected: expected)
      #expect(try ModelContext(migrated).fetch(FetchDescriptor<JournalEntry>()).isEmpty)

      let journal = JournalEntry(
        id: uuid("a3000000-0000-0000-0000-000000000001"),
        day: try #require(LocalDate(rawValue: "2026-03-08")),
        body: "Migration kept everything.",
        createdAt: Date(timeIntervalSince1970: 1_775_200_001),
        editedAt: Date(timeIntervalSince1970: 1_775_200_001)
      )
      migrated.mainContext.insert(journal)
      try migrated.mainContext.save()
    }

    let reopened = try TendModelContainer.fileBacked(at: location.store)
    try verifyVersionThreeFixture(in: reopened, expected: expected)
    let journals = try ModelContext(reopened).fetch(FetchDescriptor<JournalEntry>())
    let journal = try #require(journals.first)
    #expect(journals.count == 1)
    #expect(journal.id == uuid("a3000000-0000-0000-0000-000000000001"))
    #expect(journal.dayKey == "2026-03-08")
    #expect(journal.body == "Migration kept everything.")
  }

  @Test("version four appends one flat permissive Journal entity")
  func versionFourAppendsFlatPermissiveJournalEntity() throws {
    let versionThree = Schema(versionedSchema: TendSchemaV3.self)
    let versionFour = Schema(versionedSchema: TendSchemaV4.self)

    #expect(versionThree.version == Schema.Version(3, 0, 0))
    #expect(versionFour.version == Schema.Version(4, 0, 0))
    #expect(!versionThree.entities.map(\.name).contains("JournalEntry"))
    #expect(
      versionFour.entities.map(\.name).sorted() == [
        "Goal", "GoalEntry", "GoalReading", "Habit", "HabitActivityPeriod", "HabitBucket",
        "JournalEntry", "LogEntry",
      ])
    #expect(
      TendSchemaV4.models.map(ObjectIdentifier.init)
        == [
          Habit.self,
          HabitActivityPeriod.self,
          HabitBucket.self,
          LogEntry.self,
          Goal.self,
          GoalEntry.self,
          GoalReading.self,
          JournalEntry.self,
        ].map(ObjectIdentifier.init))

    let entity = try #require(versionFour.entities.first { $0.name == "JournalEntry" })
    #expect(
      entity.attributes.map(\.name).sorted() == ["body", "createdAt", "dayKey", "editedAt", "id"])
    #expect(entity.relationships.isEmpty)
    #expect(entity.uniquenessConstraints.isEmpty)
    #expect(entity.attributes.allSatisfy { !$0.isUnique })
    #expect(entity.attributes.allSatisfy { $0.isOptional || $0.defaultValue != nil })
  }

  private struct VersionThreeFixture {
    let habitID: UUID
    let activityID: UUID
    let bucketID: UUID
    let logID: UUID
    let goalID: UUID
    let goalEntryID: UUID
  }

  private func createVersionThreeFixture(at storeURL: URL) throws -> VersionThreeFixture {
    let schema = Schema(versionedSchema: TendSchemaV3.self)
    let configuration = ModelConfiguration(
      "Tend",
      schema: schema,
      url: storeURL,
      cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    let startedAt = Date(timeIntervalSince1970: 1_775_000_000)
    let endedAt = startedAt.addingTimeInterval(86_400)

    let habit = Habit(
      id: uuid("b1000000-0000-0000-0000-000000000001"),
      name: "Existing habit",
      cadence: .daily,
      target: 2,
      unit: "pages",
      createdAt: startedAt,
      bestStreak: 4
    )
    let activity = HabitActivityPeriod(
      id: uuid("b2000000-0000-0000-0000-000000000001"),
      startedAt: startedAt,
      habit: habit
    )
    let bucket = HabitBucket(
      id: uuid("b3000000-0000-0000-0000-000000000001"),
      periodKey: "daily:2026-04-01",
      startAt: startedAt,
      endAt: endedAt,
      cadence: .daily,
      targetSnapshot: 2,
      unitSnapshot: "pages",
      habit: habit
    )
    let log = LogEntry(
      id: uuid("b4000000-0000-0000-0000-000000000001"),
      timestamp: startedAt.addingTimeInterval(60),
      amount: 1,
      habit: habit,
      bucket: bucket
    )
    habit.activityPeriods = [activity]
    habit.buckets = [bucket]
    habit.entries = [log]
    bucket.entries = [log]

    let goal = Goal(
      id: uuid("c1000000-0000-0000-0000-000000000001"),
      name: "Existing goal",
      kind: .accumulate,
      target: 12,
      unit: "chapters",
      deadline: try LocalDate(validating: "2026-12-31"),
      createdAt: startedAt
    )
    goal.closureRawValue = GoalClosure.harvested.rawValue
    let goalEntry = GoalEntry(
      id: uuid("c2000000-0000-0000-0000-000000000001"),
      amount: 7,
      assignedDate: try #require(LocalDate(rawValue: "2026-04-01")),
      appendedAt: startedAt.addingTimeInterval(120),
      appendSequence: 3,
      goal: goal
    )
    goal.entries = [goalEntry]

    context.insert(habit)
    context.insert(goal)
    try context.save()

    return VersionThreeFixture(
      habitID: habit.id,
      activityID: activity.id,
      bucketID: bucket.id,
      logID: log.id,
      goalID: goal.id,
      goalEntryID: goalEntry.id
    )
  }

  private func verifyVersionThreeFixture(
    in container: ModelContainer,
    expected: VersionThreeFixture
  ) throws {
    let context = ModelContext(container)
    let startedAt = Date(timeIntervalSince1970: 1_775_000_000)
    let endedAt = startedAt.addingTimeInterval(86_400)
    let habits = try context.fetch(FetchDescriptor<Habit>())
    let activities = try context.fetch(FetchDescriptor<HabitActivityPeriod>())
    let buckets = try context.fetch(FetchDescriptor<HabitBucket>())
    let logs = try context.fetch(FetchDescriptor<LogEntry>())
    let goals = try context.fetch(FetchDescriptor<Goal>())
    let goalEntries = try context.fetch(FetchDescriptor<GoalEntry>())
    let readings = try context.fetch(FetchDescriptor<GoalReading>())

    let habit = try #require(habits.first { $0.id == expected.habitID })
    #expect(habits.count == 1)
    #expect(habit.name == "Existing habit")
    #expect(habit.cadenceRawValue == HabitCadence.daily.rawValue)
    #expect(habit.target == 2)
    #expect(habit.unit == "pages")
    #expect(habit.pinnedWeekdaysRawValue == 0)
    #expect(habit.reminderMinuteOfDay == nil)
    #expect(habit.isActive)
    #expect(habit.createdAt == startedAt)
    #expect(habit.bestStreak == 4)

    let activity = try #require(activities.first { $0.id == expected.activityID })
    #expect(activities.count == 1)
    #expect(activity.startedAt == startedAt)
    #expect(activity.endedAt == nil)
    #expect(activity.habit === habit)
    #expect(try #require(habit.activityPeriods).map(\.id) == [activity.id])

    let bucket = try #require(buckets.first { $0.id == expected.bucketID })
    #expect(buckets.count == 1)
    #expect(bucket.periodKey == "daily:2026-04-01")
    #expect(bucket.startAt == startedAt)
    #expect(bucket.endAt == endedAt)
    #expect(bucket.cadenceRawValue == HabitCadence.daily.rawValue)
    #expect(!bucket.isExempt)
    #expect(bucket.finalizedAt == nil)
    #expect(bucket.verdictRawValue == nil)
    #expect(bucket.targetSnapshot == 2)
    #expect(bucket.unitSnapshot == "pages")
    #expect(bucket.habit === habit)
    #expect(try #require(habit.buckets).map(\.id) == [bucket.id])

    let log = try #require(logs.first { $0.id == expected.logID })
    #expect(logs.count == 1)
    #expect(log.timestamp == startedAt.addingTimeInterval(60))
    #expect(log.amount == 1)
    #expect(log.habit === habit)
    #expect(log.bucket === bucket)
    #expect(try #require(habit.entries).map(\.id) == [log.id])
    #expect(try #require(bucket.entries).map(\.id) == [log.id])

    let goal = try #require(goals.first { $0.id == expected.goalID })
    #expect(goals.count == 1)
    #expect(goal.name == "Existing goal")
    #expect(goal.kindRawValue == GoalKind.accumulate.rawValue)
    #expect(goal.target == 12)
    #expect(goal.unit == "chapters")
    #expect(goal.baseline == nil)
    #expect(goal.deadlineKey == "2026-12-31")
    #expect(goal.createdAt == startedAt)
    #expect(goal.closureRawValue == GoalClosure.harvested.rawValue)
    #expect(try #require(goal.readings).isEmpty)
    #expect(readings.isEmpty)

    let goalEntry = try #require(goalEntries.first { $0.id == expected.goalEntryID })
    #expect(goalEntries.count == 1)
    #expect(goalEntry.amount == 7)
    #expect(goalEntry.assignedDateKey == "2026-04-01")
    #expect(goalEntry.appendedAt == startedAt.addingTimeInterval(120))
    #expect(goalEntry.appendSequence == 3)
    #expect(goalEntry.goal === goal)
    #expect(try #require(goal.entries).map(\.id) == [goalEntry.id])
  }

  private func makeTemporaryStoreLocation() throws -> (directory: URL, store: URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "JournalEntryPersistenceTests-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false
    )
    return (directory, directory.appendingPathComponent("Tend.store"))
  }

  private func uuid(_ rawValue: String) -> UUID {
    UUID(uuidString: rawValue)!
  }
}
