import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Goal lifecycle persistence")
struct GoalLifecyclePersistenceTests {
  @Test("closure raw values are stable and checked access distinguishes open from corrupt")
  func closureRawValuesAndCheckedAccessAreStable() throws {
    #expect(GoalClosure.harvested.rawValue == "harvested")
    #expect(GoalClosure.letGo.rawValue == "letGo")
    #expect(GoalClosure(rawValue: "harvested") == .harvested)
    #expect(GoalClosure(rawValue: "letGo") == .letGo)
    #expect(GoalClosure(rawValue: "") == nil)
    #expect(GoalClosure(rawValue: "retired") == nil)

    let goal = Goal(name: "Open", kind: .accumulate, target: 1)
    #expect(try goal.checkedClosure == nil)

    goal.closureRawValue = ""
    #expect(throws: GoalClosureError.unsupportedRawValue("")) {
      _ = try goal.checkedClosure
    }

    goal.closureRawValue = "retired"
    #expect(throws: GoalClosureError.unsupportedRawValue("retired")) {
      _ = try goal.checkedClosure
    }
  }

  @Test("open, harvested, and let-go goals and both progress relationships round-trip")
  func closureStatesAndRelationshipsRoundTrip() throws {
    let location = try makeTemporaryStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    do {
      let container = try TendModelContainer.fileBacked(at: location.store)
      let openGoal = Goal(
        id: uuid("91000000-0000-0000-0000-000000000001"),
        name: "Open goal",
        kind: .accumulate,
        target: 12,
        unit: "chapters",
        createdAt: Date(timeIntervalSince1970: 1_760_000_001)
      )
      let harvestedGoal = Goal(
        id: uuid("91000000-0000-0000-0000-000000000002"),
        name: "Harvested goal",
        kind: .accumulate,
        target: 20,
        unit: "pages",
        deadline: LocalDate(rawValue: "2026-03-01"),
        createdAt: Date(timeIntervalSince1970: 1_760_000_002)
      )
      harvestedGoal.closureRawValue = GoalClosure.harvested.rawValue
      harvestedGoal.entries = [
        GoalEntry(
          id: uuid("92000000-0000-0000-0000-000000000001"),
          amount: 7,
          assignedDate: try #require(LocalDate(rawValue: "2026-02-01")),
          appendedAt: Date(timeIntervalSince1970: 1_760_000_101),
          appendSequence: 4
        )
      ]

      let letGoGoal = Goal(
        id: uuid("91000000-0000-0000-0000-000000000003"),
        name: "Let-go goal",
        kind: .measure,
        target: 165,
        unit: "lb",
        baseline: 195,
        deadline: LocalDate(rawValue: "2026-04-01"),
        createdAt: Date(timeIntervalSince1970: 1_760_000_003)
      )
      letGoGoal.closureRawValue = GoalClosure.letGo.rawValue
      letGoGoal.readings = [
        GoalReading(
          id: uuid("93000000-0000-0000-0000-000000000001"),
          value: 183,
          assignedDate: try #require(LocalDate(rawValue: "2026-02-02")),
          appendedAt: Date(timeIntervalSince1970: 1_760_000_102),
          appendSequence: 5
        )
      ]

      container.mainContext.insert(openGoal)
      container.mainContext.insert(harvestedGoal)
      container.mainContext.insert(letGoGoal)
      try container.mainContext.save()
    }

    let reopened = try TendModelContainer.fileBacked(at: location.store)
    let context = ModelContext(reopened)
    let goals = try context.fetch(FetchDescriptor<Goal>())
    let openGoal = try requireGoal(uuid("91000000-0000-0000-0000-000000000001"), in: goals)
    let harvestedGoal = try requireGoal(
      uuid("91000000-0000-0000-0000-000000000002"),
      in: goals
    )
    let letGoGoal = try requireGoal(uuid("91000000-0000-0000-0000-000000000003"), in: goals)

    #expect(openGoal.closureRawValue == nil)
    #expect(try openGoal.checkedClosure == nil)
    #expect(harvestedGoal.closureRawValue == "harvested")
    #expect(try harvestedGoal.checkedClosure == .harvested)
    #expect(letGoGoal.closureRawValue == "letGo")
    #expect(try letGoGoal.checkedClosure == .letGo)

    let entry = try #require(harvestedGoal.entries?.first)
    #expect(entry.id == uuid("92000000-0000-0000-0000-000000000001"))
    #expect(entry.goal === harvestedGoal)
    #expect(entry.appendSequence == 4)
    let reading = try #require(letGoGoal.readings?.first)
    #expect(reading.id == uuid("93000000-0000-0000-0000-000000000001"))
    #expect(reading.goal === letGoGoal)
    #expect(reading.appendSequence == 5)
  }

  @Test("current stores preserve corrupt closure raw values and reject checked access")
  func corruptCurrentRawValuesSurviveReopening() throws {
    let location = try makeTemporaryStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    do {
      let container = try TendModelContainer.fileBacked(at: location.store)
      let empty = Goal(
        id: uuid("94000000-0000-0000-0000-000000000001"),
        name: "Empty raw",
        kind: .accumulate,
        target: 1
      )
      empty.closureRawValue = ""
      let future = Goal(
        id: uuid("94000000-0000-0000-0000-000000000002"),
        name: "Future raw",
        kind: .measure,
        target: 1,
        baseline: 0
      )
      future.closureRawValue = "paused"
      container.mainContext.insert(empty)
      container.mainContext.insert(future)
      try container.mainContext.save()
    }

    let reopened = try TendModelContainer.fileBacked(at: location.store)
    let goals = try ModelContext(reopened).fetch(FetchDescriptor<Goal>())
    let empty = try requireGoal(uuid("94000000-0000-0000-0000-000000000001"), in: goals)
    let future = try requireGoal(uuid("94000000-0000-0000-0000-000000000002"), in: goals)

    #expect(empty.closureRawValue == "")
    #expect(throws: GoalClosureError.unsupportedRawValue("")) {
      _ = try empty.checkedClosure
    }
    #expect(future.closureRawValue == "paused")
    #expect(throws: GoalClosureError.unsupportedRawValue("paused")) {
      _ = try future.checkedClosure
    }
  }

  @Test("the exact version-two goal store migrates every fact and persistent identity")
  func versionTwoGoalStoreMigratesWithoutChanges() throws {
    let location = try makeTemporaryStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let expectedIDs = try createVersionTwoFixture(at: location.store)

    do {
      let migrated = try TendModelContainer.fileBacked(at: location.store)
      try verifyMigratedVersionTwoFixture(in: migrated, expectedIDs: expectedIDs)
    }

    let reopened = try TendModelContainer.fileBacked(at: location.store)
    try verifyMigratedVersionTwoFixture(in: reopened, expectedIDs: expectedIDs)
  }

  @Test("an empty version-two store migrates and reopens")
  func emptyVersionTwoStoreMigratesAndReopens() throws {
    let location = try makeTemporaryStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    try createEmptyVersionTwoFixture(at: location.store)

    do {
      let migrated = try TendModelContainer.fileBacked(at: location.store)
      #expect(try ModelContext(migrated).fetch(FetchDescriptor<Goal>()).isEmpty)
    }

    let reopened = try TendModelContainer.fileBacked(at: location.store)
    #expect(try ModelContext(reopened).fetch(FetchDescriptor<Goal>()).isEmpty)
  }

  @Test("versioned schemas freeze version two and register every version-three model")
  func versionedSchemaShapeIsStable() throws {
    let versionTwo = Schema(versionedSchema: TendSchemaV2.self)
    let versionThree = Schema(versionedSchema: TendSchemaV3.self)

    #expect(versionTwo.version == Schema.Version(2, 0, 0))
    #expect(versionThree.version == Schema.Version(3, 0, 0))
    let expectedEntityNames = [
      "Goal", "GoalEntry", "GoalReading", "Habit", "HabitActivityPeriod", "HabitBucket",
      "LogEntry",
    ]
    #expect(versionTwo.entities.map(\.name) == expectedEntityNames)
    #expect(versionThree.entities.map(\.name) == expectedEntityNames)
    #expect(
      TendSchemaV2.models.map(ObjectIdentifier.init)
        == [
          Habit.self,
          HabitActivityPeriod.self,
          HabitBucket.self,
          LogEntry.self,
          TendSchemaV2.Goal.self,
          TendSchemaV2.GoalEntry.self,
          TendSchemaV2.GoalReading.self,
        ].map(ObjectIdentifier.init))
    #expect(
      TendSchemaV3.models.map(ObjectIdentifier.init)
        == [
          Habit.self,
          HabitActivityPeriod.self,
          HabitBucket.self,
          LogEntry.self,
          Goal.self,
          GoalEntry.self,
          GoalReading.self,
        ].map(ObjectIdentifier.init))

    let versionTwoGoal = try #require(versionTwo.entities.first { $0.name == "Goal" })
    let versionThreeGoal = try #require(versionThree.entities.first { $0.name == "Goal" })
    #expect(!versionTwoGoal.attributes.map(\.name).contains("closureRawValue"))
    #expect(versionThreeGoal.attributes.map(\.name).contains("closureRawValue"))

    for schema in [versionTwo, versionThree] {
      let goal = try #require(schema.entities.first { $0.name == "Goal" })
      let entries = try #require(goal.relationships.first { $0.name == "entries" })
      let readings = try #require(goal.relationships.first { $0.name == "readings" })
      #expect(entries.deleteRule == .cascade)
      #expect(entries.inverseName == "goal")
      #expect(readings.deleteRule == .cascade)
      #expect(readings.inverseName == "goal")
    }
  }

  private struct HistoricalPersistentIDs {
    let goals: [UUID: PersistentIdentity]
    let entries: [UUID: PersistentIdentity]
    let readings: [UUID: PersistentIdentity]
  }

  private struct PersistentIdentity: Equatable {
    let entityName: String
    let primaryKey: String
  }

  private struct EncodedPersistentIdentifier: Decodable {
    struct Implementation: Decodable {
      let entityName: String
      let primaryKey: String
    }

    let implementation: Implementation
  }

  private func createVersionTwoFixture(at storeURL: URL) throws -> HistoricalPersistentIDs {
    let schema = Schema(versionedSchema: TendSchemaV2.self)
    let configuration = ModelConfiguration(
      "Tend",
      schema: schema,
      url: storeURL,
      cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)

    let firstAccumulate = TendSchemaV2.Goal(
      id: uuid("a1000000-0000-0000-0000-000000000001"),
      name: "  Read owner text exactly  ",
      kind: .accumulate,
      target: 40,
      unit: "chapters read",
      deadline: LocalDate(rawValue: "2026-06-30"),
      createdAt: Date(timeIntervalSince1970: 1_750_000_001)
    )
    let accumulateEntries = [
      TendSchemaV2.GoalEntry(
        id: uuid("a2000000-0000-0000-0000-000000000001"),
        amount: 3,
        assignedDate: try #require(LocalDate(rawValue: "2026-01-03")),
        appendedAt: Date(timeIntervalSince1970: 1_750_000_101),
        appendSequence: 8
      ),
      TendSchemaV2.GoalEntry(
        id: uuid("a2000000-0000-0000-0000-000000000002"),
        amount: 5,
        assignedDate: try #require(LocalDate(rawValue: "2026-01-04")),
        appendedAt: Date(timeIntervalSince1970: 1_750_000_102),
        appendSequence: 13
      ),
    ]
    firstAccumulate.entries = accumulateEntries

    let secondAccumulate = TendSchemaV2.Goal(
      id: uuid("a1000000-0000-0000-0000-000000000002"),
      name: "Empty accumulate",
      kind: .accumulate,
      target: 1,
      unit: "time",
      createdAt: Date(timeIntervalSince1970: 1_750_000_002)
    )

    let firstMeasure = TendSchemaV2.Goal(
      id: uuid("b1000000-0000-0000-0000-000000000001"),
      name: "Weight arc",
      kind: .measure,
      target: 165,
      unit: "lb",
      baseline: 195,
      deadline: LocalDate(rawValue: "2027-01-01"),
      createdAt: Date(timeIntervalSince1970: 1_750_000_003)
    )
    let measureReadings = [
      TendSchemaV2.GoalReading(
        id: uuid("b3000000-0000-0000-0000-000000000001"),
        value: 190,
        assignedDate: try #require(LocalDate(rawValue: "2026-01-05")),
        appendedAt: Date(timeIntervalSince1970: 1_750_000_103),
        appendSequence: 21
      ),
      TendSchemaV2.GoalReading(
        id: uuid("b3000000-0000-0000-0000-000000000002"),
        value: 183,
        assignedDate: try #require(LocalDate(rawValue: "2026-01-06")),
        appendedAt: Date(timeIntervalSince1970: 1_750_000_104),
        appendSequence: 34
      ),
    ]
    firstMeasure.readings = measureReadings

    let secondMeasure = TendSchemaV2.Goal(
      id: uuid("b1000000-0000-0000-0000-000000000002"),
      name: "No-deadline measure",
      kind: .measure,
      target: -10,
      unit: "degrees",
      baseline: 7,
      createdAt: Date(timeIntervalSince1970: 1_750_000_004)
    )

    for goal in [firstAccumulate, secondAccumulate, firstMeasure, secondMeasure] {
      context.insert(goal)
    }
    try context.save()

    return HistoricalPersistentIDs(
      goals: Dictionary(
        uniqueKeysWithValues: try [
          firstAccumulate, secondAccumulate, firstMeasure, secondMeasure,
        ].map {
          ($0.id, try persistentIdentity(of: $0.persistentModelID))
        }),
      entries: Dictionary(
        uniqueKeysWithValues: try accumulateEntries.map {
          ($0.id, try persistentIdentity(of: $0.persistentModelID))
        }),
      readings: Dictionary(
        uniqueKeysWithValues: try measureReadings.map {
          ($0.id, try persistentIdentity(of: $0.persistentModelID))
        })
    )
  }

  private func createEmptyVersionTwoFixture(at storeURL: URL) throws {
    let schema = Schema(versionedSchema: TendSchemaV2.self)
    let configuration = ModelConfiguration(
      "Tend",
      schema: schema,
      url: storeURL,
      cloudKitDatabase: .none
    )
    _ = try ModelContainer(for: schema, configurations: [configuration])
  }

  private func verifyMigratedVersionTwoFixture(
    in container: ModelContainer,
    expectedIDs: HistoricalPersistentIDs
  ) throws {
    let context = ModelContext(container)
    let goals = try context.fetch(FetchDescriptor<Goal>())
    let entries = try context.fetch(FetchDescriptor<GoalEntry>())
    let readings = try context.fetch(FetchDescriptor<GoalReading>())
    #expect(goals.count == 4)
    #expect(entries.count == 2)
    #expect(readings.count == 2)
    #expect(goals.allSatisfy { $0.closureRawValue == nil })
    for goal in goals {
      #expect(try goal.checkedClosure == nil)
      let expectedID = try #require(expectedIDs.goals[goal.id])
      #expect(try persistentIdentity(of: goal.persistentModelID) == expectedID)
    }
    for entry in entries {
      let expectedID = try #require(expectedIDs.entries[entry.id])
      #expect(try persistentIdentity(of: entry.persistentModelID) == expectedID)
    }
    for reading in readings {
      let expectedID = try #require(expectedIDs.readings[reading.id])
      #expect(try persistentIdentity(of: reading.persistentModelID) == expectedID)
    }

    let firstAccumulate = try requireGoal(
      uuid("a1000000-0000-0000-0000-000000000001"),
      in: goals
    )
    #expect(firstAccumulate.name == "  Read owner text exactly  ")
    #expect(firstAccumulate.kindRawValue == "accumulate")
    #expect(firstAccumulate.target == 40)
    #expect(firstAccumulate.unit == "chapters read")
    #expect(firstAccumulate.baseline == nil)
    #expect(firstAccumulate.deadlineKey == "2026-06-30")
    #expect(firstAccumulate.createdAt == Date(timeIntervalSince1970: 1_750_000_001))
    let migratedEntries = try #require(firstAccumulate.entries).sorted {
      $0.appendSequence < $1.appendSequence
    }
    #expect(
      migratedEntries.map(\.id) == [
        uuid("a2000000-0000-0000-0000-000000000001"),
        uuid("a2000000-0000-0000-0000-000000000002"),
      ])
    #expect(migratedEntries.map(\.amount) == [3, 5])
    #expect(migratedEntries.map(\.assignedDateKey) == ["2026-01-03", "2026-01-04"])
    #expect(
      migratedEntries.map(\.appendedAt) == [
        Date(timeIntervalSince1970: 1_750_000_101),
        Date(timeIntervalSince1970: 1_750_000_102),
      ])
    #expect(migratedEntries.map(\.appendSequence) == [8, 13])
    #expect(migratedEntries.allSatisfy { $0.goal === firstAccumulate })

    let secondAccumulate = try requireGoal(
      uuid("a1000000-0000-0000-0000-000000000002"),
      in: goals
    )
    #expect(secondAccumulate.name == "Empty accumulate")
    #expect(secondAccumulate.kindRawValue == "accumulate")
    #expect(secondAccumulate.target == 1)
    #expect(secondAccumulate.unit == "time")
    #expect(secondAccumulate.baseline == nil)
    #expect(secondAccumulate.deadlineKey == nil)
    #expect(secondAccumulate.createdAt == Date(timeIntervalSince1970: 1_750_000_002))
    #expect(try #require(secondAccumulate.entries).isEmpty)
    #expect(try #require(secondAccumulate.readings).isEmpty)

    let firstMeasure = try requireGoal(
      uuid("b1000000-0000-0000-0000-000000000001"),
      in: goals
    )
    #expect(firstMeasure.name == "Weight arc")
    #expect(firstMeasure.kindRawValue == "measure")
    #expect(firstMeasure.target == 165)
    #expect(firstMeasure.unit == "lb")
    #expect(firstMeasure.baseline == 195)
    #expect(firstMeasure.deadlineKey == "2027-01-01")
    #expect(firstMeasure.createdAt == Date(timeIntervalSince1970: 1_750_000_003))
    let migratedReadings = try #require(firstMeasure.readings).sorted {
      $0.appendSequence < $1.appendSequence
    }
    #expect(
      migratedReadings.map(\.id) == [
        uuid("b3000000-0000-0000-0000-000000000001"),
        uuid("b3000000-0000-0000-0000-000000000002"),
      ])
    #expect(migratedReadings.map(\.value) == [190, 183])
    #expect(migratedReadings.map(\.assignedDateKey) == ["2026-01-05", "2026-01-06"])
    #expect(
      migratedReadings.map(\.appendedAt) == [
        Date(timeIntervalSince1970: 1_750_000_103),
        Date(timeIntervalSince1970: 1_750_000_104),
      ])
    #expect(migratedReadings.map(\.appendSequence) == [21, 34])
    #expect(migratedReadings.allSatisfy { $0.goal === firstMeasure })

    let secondMeasure = try requireGoal(
      uuid("b1000000-0000-0000-0000-000000000002"),
      in: goals
    )
    #expect(secondMeasure.name == "No-deadline measure")
    #expect(secondMeasure.kindRawValue == "measure")
    #expect(secondMeasure.target == -10)
    #expect(secondMeasure.unit == "degrees")
    #expect(secondMeasure.baseline == 7)
    #expect(secondMeasure.deadlineKey == nil)
    #expect(secondMeasure.createdAt == Date(timeIntervalSince1970: 1_750_000_004))
    #expect(try #require(secondMeasure.entries).isEmpty)
    #expect(try #require(secondMeasure.readings).isEmpty)
  }

  private func persistentIdentity(of identifier: PersistentIdentifier) throws
    -> PersistentIdentity
  {
    let data = try JSONEncoder().encode(identifier)
    let decoded = try JSONDecoder().decode(EncodedPersistentIdentifier.self, from: data)
    return PersistentIdentity(
      entityName: decoded.implementation.entityName,
      primaryKey: decoded.implementation.primaryKey
    )
  }

  private func requireGoal(_ id: UUID, in goals: [Goal]) throws -> Goal {
    try #require(goals.first { $0.id == id })
  }

  private func makeTemporaryStoreLocation() throws -> (directory: URL, store: URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "GoalLifecyclePersistenceTests-\(UUID().uuidString)",
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
