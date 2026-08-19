import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Goal persistence")
struct GoalPersistenceTests {

  @Test("goal kind raw values are stable and unknown values fail checked decoding")
  func goalKindRawValuesAreStable() throws {
    #expect(GoalKind.accumulate.rawValue == "accumulate")
    #expect(GoalKind.measure.rawValue == "measure")
    #expect(GoalKind(rawValue: "count") == nil)

    let encoded = try JSONEncoder().encode(GoalKind.measure)
    #expect(String(decoding: encoded, as: UTF8.self) == "\"measure\"")
    #expect(try JSONDecoder().decode(GoalKind.self, from: encoded) == .measure)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(GoalKind.self, from: Data("\"count\"".utf8))
    }
  }

  @Test("all goal aggregate shapes round-trip in memory")
  func allGoalAggregateShapesRoundTripInMemory() throws {
    let container = try TendModelContainer.inMemory()
    try insertEveryAggregateShape(into: container)
    try verifyEveryAggregateShape(in: container)
  }

  @Test("all goal aggregate shapes survive reopening a file store")
  func allGoalAggregateShapesSurviveReopeningFileStore() throws {
    let location = try makeTemporaryStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    do {
      let container = try TendModelContainer.fileBacked(at: location.store)
      try insertEveryAggregateShape(into: container)
    }

    let reopened = try TendModelContainer.fileBacked(at: location.store)
    try verifyEveryAggregateShape(in: reopened)
  }

  @Test("storage preserves corrupt imported raw values without defaulting")
  func storagePreservesCorruptImportedRawValues() throws {
    let container = try TendModelContainer.inMemory()
    let goal = Goal(name: "Imported", kind: .accumulate, target: 1)
    goal.kindRawValue = "count"
    goal.deadlineKey = "today"
    let entry = GoalEntry(
      amount: 1,
      assignedDate: try #require(LocalDate(rawValue: "2024-01-01")),
      appendedAt: Date(timeIntervalSince1970: 1),
      appendSequence: 0
    )
    entry.assignedDateKey = "yesterday"
    goal.entries = [entry]
    container.mainContext.insert(goal)
    try container.mainContext.save()

    let context = ModelContext(container)
    let fetched = try #require(context.fetch(FetchDescriptor<Goal>()).first)
    let fetchedEntry = try #require(fetched.entries?.first)
    #expect(fetched.kindRawValue == "count")
    #expect(GoalKind(rawValue: fetched.kindRawValue) == nil)
    #expect(fetched.deadlineKey == "today")
    #expect(LocalDate(rawValue: try #require(fetched.deadlineKey)) == nil)
    #expect(fetchedEntry.assignedDateKey == "yesterday")
    #expect(LocalDate(rawValue: fetchedEntry.assignedDateKey) == nil)
  }

  @Test("optional collections and inverses remain legal storage states")
  func optionalRelationshipsRemainLegal() throws {
    let container = try TendModelContainer.inMemory()
    let goal = Goal(name: "Detached relationships", kind: .accumulate, target: 1)
    goal.entries = nil
    goal.readings = nil
    let entry = GoalEntry(
      amount: 1,
      assignedDate: try #require(LocalDate(rawValue: "2024-01-01")),
      appendedAt: Date(timeIntervalSince1970: 1),
      appendSequence: 0,
      goal: nil
    )
    container.mainContext.insert(goal)
    container.mainContext.insert(entry)
    try container.mainContext.save()

    let context = ModelContext(container)
    let fetchedGoal = try #require(context.fetch(FetchDescriptor<Goal>()).first)
    let fetchedEntry = try #require(context.fetch(FetchDescriptor<GoalEntry>()).first)
    #expect(fetchedGoal.entries?.isEmpty == true)
    #expect(fetchedGoal.readings?.isEmpty == true)
    #expect(fetchedEntry.goal == nil)
  }

  @Test("deleting a goal cascades entries and readings")
  func deletingGoalCascadesChildren() throws {
    let container = try TendModelContainer.inMemory()
    let goal = Goal(name: "Owned history", kind: .accumulate, target: 10)
    goal.entries = [makeEntry(index: 0)]
    goal.readings = [makeReading(index: 0)]
    container.mainContext.insert(goal)
    try container.mainContext.save()

    container.mainContext.delete(goal)
    try container.mainContext.save()

    let context = ModelContext(container)
    #expect(try context.fetch(FetchDescriptor<Goal>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<GoalEntry>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<GoalReading>()).isEmpty)
  }

  @Test("deleting a child leaves its goal and sibling history intact")
  func deletingChildLeavesGoalIntact() throws {
    let container = try TendModelContainer.inMemory()
    let entryGoal = Goal(name: "Entry history", kind: .accumulate, target: 10)
    entryGoal.entries = [makeEntry(index: 0), makeEntry(index: 1)]
    let readingGoal = Goal(name: "Reading history", kind: .measure, target: 10, baseline: 0)
    readingGoal.readings = [makeReading(index: 0), makeReading(index: 1)]
    container.mainContext.insert(entryGoal)
    container.mainContext.insert(readingGoal)
    try container.mainContext.save()

    let deletedEntryID = try #require(entryGoal.entries?.first?.id)
    let deletedReadingID = try #require(readingGoal.readings?.first?.id)
    container.mainContext.delete(try #require(entryGoal.entries?.first))
    container.mainContext.delete(try #require(readingGoal.readings?.first))
    try container.mainContext.save()

    let context = ModelContext(container)
    let goals = try context.fetch(FetchDescriptor<Goal>())
    let fetchedEntryGoal = try #require(goals.first { $0.id == entryGoal.id })
    let fetchedReadingGoal = try #require(goals.first { $0.id == readingGoal.id })
    let remainingEntry = try #require(context.fetch(FetchDescriptor<GoalEntry>()).first)
    let remainingReading = try #require(context.fetch(FetchDescriptor<GoalReading>()).first)
    #expect(goals.count == 2)
    #expect(remainingEntry.id != deletedEntryID)
    #expect(remainingEntry.goal?.id == fetchedEntryGoal.id)
    #expect(remainingReading.id != deletedReadingID)
    #expect(remainingReading.goal?.id == fetchedReadingGoal.id)
  }

  @Test("the complete version-one habit store migrates without changes")
  func completeVersionOneHabitStoreMigratesWithoutChanges() throws {
    let location = try makeTemporaryStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    try createVersionOneFixture(at: location.store)
    do {
      let migrating = try TendModelContainer.fileBacked(at: location.store)
      let migratingContext = ModelContext(migrating)
      #expect(try migratingContext.fetchCount(FetchDescriptor<Habit>()) == 1)
    }

    let reopened = try TendModelContainer.fileBacked(at: location.store)
    let context = ModelContext(reopened)

    let habits = try context.fetch(FetchDescriptor<Habit>())
    let periods = try context.fetch(FetchDescriptor<HabitActivityPeriod>())
    let buckets = try context.fetch(FetchDescriptor<HabitBucket>())
    let entries = try context.fetch(FetchDescriptor<LogEntry>())
    #expect(habits.count == 1)
    #expect(periods.count == 2)
    #expect(buckets.count == 2)
    #expect(entries.count == 2)
    #expect(try context.fetch(FetchDescriptor<Goal>()).isEmpty)

    let habit = try #require(habits.first)
    #expect(habit.id == UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
    #expect(habit.name == "Complete habit")
    #expect(habit.cadenceRawValue == "weekly")
    #expect(habit.target == 3)
    #expect(habit.unit == "sessions")
    #expect(habit.pinnedWeekdaysRawValue == 5)
    #expect(habit.reminderMinuteOfDay == 510)
    #expect(!habit.isActive)
    #expect(habit.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(habit.bestStreak == 11)

    let sortedPeriods = periods.sorted { $0.startedAt < $1.startedAt }
    #expect(
      sortedPeriods.map(\.id) == [
        UUID(uuidString: "20000000-0000-0000-0000-000000000001"),
        UUID(uuidString: "20000000-0000-0000-0000-000000000002"),
      ])
    #expect(sortedPeriods[0].startedAt == Date(timeIntervalSince1970: 1_700_000_100))
    #expect(sortedPeriods[0].endedAt == Date(timeIntervalSince1970: 1_700_086_400))
    #expect(sortedPeriods[1].endedAt == nil)
    #expect(sortedPeriods[1].startedAt == Date(timeIntervalSince1970: 1_700_172_800))
    #expect(sortedPeriods.allSatisfy { $0.habit?.id == habit.id })

    let sortedBuckets = buckets.sorted { $0.periodKey < $1.periodKey }
    #expect(
      sortedBuckets.map(\.id) == [
        UUID(uuidString: "30000000-0000-0000-0000-000000000001"),
        UUID(uuidString: "30000000-0000-0000-0000-000000000002"),
      ])
    #expect(sortedBuckets[0].periodKey == "week:2023-11-13")
    #expect(sortedBuckets[0].startAt == Date(timeIntervalSince1970: 1_699_833_600))
    #expect(sortedBuckets[0].endAt == Date(timeIntervalSince1970: 1_700_438_400))
    #expect(sortedBuckets[0].cadenceRawValue == "weekly")
    #expect(sortedBuckets[0].isExempt)
    #expect(sortedBuckets[0].finalizedAt == Date(timeIntervalSince1970: 1_700_524_800))
    #expect(sortedBuckets[0].verdictRawValue == "missed")
    #expect(sortedBuckets[0].targetSnapshot == 3)
    #expect(sortedBuckets[0].unitSnapshot == "sessions")
    #expect(sortedBuckets[1].periodKey == "week:2023-11-20")
    #expect(sortedBuckets[1].finalizedAt == nil)
    #expect(sortedBuckets[1].verdictRawValue == nil)
    #expect(sortedBuckets[1].startAt == Date(timeIntervalSince1970: 1_700_438_400))
    #expect(sortedBuckets[1].endAt == Date(timeIntervalSince1970: 1_701_043_200))
    #expect(sortedBuckets[1].cadenceRawValue == "weekly")
    #expect(!sortedBuckets[1].isExempt)
    #expect(sortedBuckets[1].targetSnapshot == nil)
    #expect(sortedBuckets[1].unitSnapshot == nil)
    #expect(sortedBuckets.allSatisfy { $0.habit?.id == habit.id })

    let sortedEntries = entries.sorted { $0.timestamp < $1.timestamp }
    #expect(
      sortedEntries.map(\.id) == [
        UUID(uuidString: "40000000-0000-0000-0000-000000000001"),
        UUID(uuidString: "40000000-0000-0000-0000-000000000002"),
      ])
    #expect(
      sortedEntries.map(\.timestamp) == [
        Date(timeIntervalSince1970: 1_700_000_200),
        Date(timeIntervalSince1970: 1_700_500_000),
      ])
    #expect(sortedEntries.map(\.amount) == [1, 2])
    #expect(sortedEntries.allSatisfy { $0.habit?.id == habit.id })
    #expect(sortedEntries[0].bucket?.id == sortedBuckets[0].id)
    #expect(sortedEntries[1].bucket?.id == sortedBuckets[1].id)
    #expect(sortedBuckets[0].entries?.map(\.id) == [sortedEntries[0].id])
    #expect(sortedBuckets[1].entries?.map(\.id) == [sortedEntries[1].id])
    #expect(habit.activityPeriods?.count == 2)
    #expect(habit.buckets?.count == 2)
    #expect(habit.entries?.count == 2)
  }

  private func insertEveryAggregateShape(into container: ModelContainer) throws {
    let createdAt = Date(timeIntervalSince1970: 1_720_000_000)
    for kind in [GoalKind.accumulate, .measure] {
      for childCount in 0...2 {
        let goal = Goal(
          id: aggregateID(kind: kind, childCount: childCount),
          name: "\(kind.rawValue)-\(childCount)",
          kind: kind,
          target: kind == .accumulate ? 100 : -25,
          unit: kind == .accumulate ? "pages" : "kg",
          baseline: kind == .measure ? 75 : nil,
          deadline: LocalDate(rawValue: "2025-12-31")!,
          createdAt: createdAt.addingTimeInterval(TimeInterval(childCount))
        )
        if kind == .accumulate {
          goal.entries = (0..<childCount).map(makeEntry(index:))
        } else {
          goal.readings = (0..<childCount).map(makeReading(index:))
        }
        container.mainContext.insert(goal)
      }
    }
    try container.mainContext.save()
  }

  private func verifyEveryAggregateShape(in container: ModelContainer) throws {
    let context = ModelContext(container)
    let goals = try context.fetch(FetchDescriptor<Goal>())
    #expect(goals.count == 6)

    for kind in [GoalKind.accumulate, .measure] {
      for childCount in 0...2 {
        let id = aggregateID(kind: kind, childCount: childCount)
        let goal = try #require(goals.first { $0.id == id })
        #expect(goal.name == "\(kind.rawValue)-\(childCount)")
        #expect(goal.kindRawValue == kind.rawValue)
        #expect(goal.target == (kind == .accumulate ? 100 : -25))
        #expect(goal.unit == (kind == .accumulate ? "pages" : "kg"))
        #expect(goal.baseline == (kind == .measure ? 75 : nil))
        #expect(goal.deadlineKey == "2025-12-31")
        #expect(goal.createdAt == Date(timeIntervalSince1970: 1_720_000_000 + Double(childCount)))

        let entries = try #require(goal.entries).sorted { $0.appendSequence < $1.appendSequence }
        let readings = try #require(goal.readings).sorted { $0.appendSequence < $1.appendSequence }
        #expect(entries.count == (kind == .accumulate ? childCount : 0))
        #expect(readings.count == (kind == .measure ? childCount : 0))
        for (index, entry) in entries.enumerated() {
          #expect(entry.id == progressID(prefix: 5, index: index))
          #expect(entry.amount == index + 1)
          #expect(entry.assignedDateKey == "2024-01-0\(index + 1)")
          #expect(entry.appendedAt == Date(timeIntervalSince1970: 1_730_000_000 + Double(index)))
          #expect(entry.appendSequence == index)
          #expect(entry.goal?.id == goal.id)
        }
        for (index, reading) in readings.enumerated() {
          #expect(reading.id == progressID(prefix: 6, index: index))
          #expect(reading.value == 70 - index)
          #expect(reading.assignedDateKey == "2024-02-0\(index + 1)")
          #expect(reading.appendedAt == Date(timeIntervalSince1970: 1_740_000_000 + Double(index)))
          #expect(reading.appendSequence == index)
          #expect(reading.goal?.id == goal.id)
        }
      }
    }
  }

  private func makeEntry(index: Int) -> GoalEntry {
    GoalEntry(
      id: progressID(prefix: 5, index: index),
      amount: index + 1,
      assignedDate: LocalDate(rawValue: "2024-01-0\(index + 1)")!,
      appendedAt: Date(timeIntervalSince1970: 1_730_000_000 + Double(index)),
      appendSequence: index
    )
  }

  private func makeReading(index: Int) -> GoalReading {
    GoalReading(
      id: progressID(prefix: 6, index: index),
      value: 70 - index,
      assignedDate: LocalDate(rawValue: "2024-02-0\(index + 1)")!,
      appendedAt: Date(timeIntervalSince1970: 1_740_000_000 + Double(index)),
      appendSequence: index
    )
  }

  private func aggregateID(kind: GoalKind, childCount: Int) -> UUID {
    let prefix = kind == .accumulate ? 7 : 8
    return UUID(uuidString: "\(prefix)0000000-0000-0000-0000-00000000000\(childCount)")!
  }

  private func progressID(prefix: Int, index: Int) -> UUID {
    UUID(uuidString: "\(prefix)0000000-0000-0000-0000-00000000000\(index)")!
  }

  private func makeTemporaryStoreLocation() throws -> (directory: URL, store: URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("GoalPersistenceTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false
    )
    return (directory, directory.appendingPathComponent("Tend.store"))
  }

  private func createVersionOneFixture(at storeURL: URL) throws {
    let schema = Schema(versionedSchema: TendSchemaV1.self)
    let configuration = ModelConfiguration(
      "Tend",
      schema: schema,
      url: storeURL,
      cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    let habit = Habit(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
      name: "Complete habit",
      cadence: .weekly,
      target: 3,
      unit: "sessions",
      pinnedWeekdays: PinnedWeekdays(rawValue: 5)!,
      reminderTime: ReminderTime(hour: 8, minute: 30),
      isActive: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      bestStreak: 11
    )
    let periods = [
      HabitActivityPeriod(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
        startedAt: Date(timeIntervalSince1970: 1_700_000_100),
        endedAt: Date(timeIntervalSince1970: 1_700_086_400)
      ),
      HabitActivityPeriod(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
        startedAt: Date(timeIntervalSince1970: 1_700_172_800)
      ),
    ]
    let buckets = [
      HabitBucket(
        id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
        periodKey: "week:2023-11-13",
        startAt: Date(timeIntervalSince1970: 1_699_833_600),
        endAt: Date(timeIntervalSince1970: 1_700_438_400),
        cadence: .weekly,
        isExempt: true,
        finalizedAt: Date(timeIntervalSince1970: 1_700_524_800),
        verdict: .missed,
        targetSnapshot: 3,
        unitSnapshot: "sessions"
      ),
      HabitBucket(
        id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
        periodKey: "week:2023-11-20",
        startAt: Date(timeIntervalSince1970: 1_700_438_400),
        endAt: Date(timeIntervalSince1970: 1_701_043_200),
        cadence: .weekly
      ),
    ]
    let entries = [
      LogEntry(
        id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
        timestamp: Date(timeIntervalSince1970: 1_700_000_200),
        amount: 1
      ),
      LogEntry(
        id: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!,
        timestamp: Date(timeIntervalSince1970: 1_700_500_000),
        amount: 2
      ),
    ]
    habit.activityPeriods = periods
    habit.buckets = buckets
    habit.entries = entries
    buckets[0].entries = [entries[0]]
    buckets[1].entries = [entries[1]]
    context.insert(habit)
    try context.save()
  }
}
