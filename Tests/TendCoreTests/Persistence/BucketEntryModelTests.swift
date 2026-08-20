import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Bucket and entry persistence")
struct BucketEntryModelTests {
  @Test("canonical daily and weekly periods round-trip half-open boundaries")
  func canonicalPeriodsRoundTripHalfOpenBoundaries() throws {
    let container = try makeContainer()
    let habit = Habit(name: "Exercise", cadence: .daily, target: 8_000, unit: "steps")
    let springStart = Date(timeIntervalSince1970: 1_000_000)
    let fallStart = Date(timeIntervalSince1970: 2_000_000)
    let weekStart = Date(timeIntervalSince1970: 3_000_000)
    habit.buckets = [
      HabitBucket(
        periodKey: "day:2026-03-08",
        startAt: springStart,
        endAt: springStart.addingTimeInterval(23 * 60 * 60),
        cadence: .daily
      ),
      HabitBucket(
        periodKey: "day:2026-11-01",
        startAt: fallStart,
        endAt: fallStart.addingTimeInterval(25 * 60 * 60),
        cadence: .daily
      ),
      HabitBucket(
        periodKey: "week:2026-03-02",
        startAt: weekStart,
        endAt: weekStart.addingTimeInterval(7 * 24 * 60 * 60),
        cadence: .weekly
      ),
    ]

    container.mainContext.insert(habit)
    try container.mainContext.save()

    let context = ModelContext(container)
    let buckets = try context.fetch(FetchDescriptor<HabitBucket>())
      .sorted { $0.periodKey < $1.periodKey }
    #expect(
      buckets.map(\.periodKey) == [
        "day:2026-03-08", "day:2026-11-01", "week:2026-03-02",
      ])
    #expect(buckets[0].endAt.timeIntervalSince(buckets[0].startAt) == 23 * 60 * 60)
    #expect(buckets[1].endAt.timeIntervalSince(buckets[1].startAt) == 25 * 60 * 60)
    #expect(buckets[2].endAt.timeIntervalSince(buckets[2].startAt) == 7 * 24 * 60 * 60)
    #expect(buckets[0].cadenceRawValue == "daily")
    #expect(buckets[2].cadenceRawValue == "weekly")
    #expect(buckets.allSatisfy { $0.habit?.id == habit.id })
  }

  @Test("a time-zone boundary change updates one non-final bucket in place")
  func timeZoneBoundaryChangeUpdatesOneBucketInPlace() throws {
    let container = try makeContainer()
    let id = try #require(UUID(uuidString: "BA0CE112-0A2D-42FC-A0C0-B46078E43835"))
    let originalStart = Date(timeIntervalSince1970: 4_000_000)
    let habit = Habit(name: "Piano", cadence: .daily, target: 30, unit: "min")
    habit.buckets = [
      HabitBucket(
        id: id,
        periodKey: "day:2026-08-01",
        startAt: originalStart,
        endAt: originalStart.addingTimeInterval(24 * 60 * 60),
        cadence: .daily
      )
    ]
    container.mainContext.insert(habit)
    try container.mainContext.save()

    let context = ModelContext(container)
    let bucket = try #require(context.fetch(FetchDescriptor<HabitBucket>()).first)
    let shiftedStart = originalStart.addingTimeInterval(3 * 60 * 60)
    bucket.startAt = shiftedStart
    bucket.endAt = shiftedStart.addingTimeInterval(24 * 60 * 60)
    try context.save()

    let reloaded = ModelContext(container)
    let buckets = try reloaded.fetch(FetchDescriptor<HabitBucket>())
    #expect(buckets.count == 1)
    #expect(buckets[0].id == id)
    #expect(buckets[0].periodKey == "day:2026-08-01")
    #expect(buckets[0].startAt == shiftedStart)
  }

  @Test("open final and exempt bucket facts remain distinct")
  func bucketFactsRemainDistinct() throws {
    let container = try makeContainer()
    let habit = Habit(name: "Piano", cadence: .daily, target: 30, unit: "min")
    let start = Date(timeIntervalSince1970: 5_000_000)
    let finalizedAt = Date(timeIntervalSince1970: 5_200_000)
    habit.buckets = [
      HabitBucket(
        periodKey: "day:2026-07-30",
        startAt: start,
        endAt: start.addingTimeInterval(86_400),
        cadence: .daily
      ),
      HabitBucket(
        periodKey: "day:2026-07-31",
        startAt: start.addingTimeInterval(86_400),
        endAt: start.addingTimeInterval(2 * 86_400),
        cadence: .daily,
        finalizedAt: finalizedAt,
        verdict: .met,
        targetSnapshot: 30,
        unitSnapshot: "min"
      ),
      HabitBucket(
        periodKey: "day:2026-08-01",
        startAt: start.addingTimeInterval(2 * 86_400),
        endAt: start.addingTimeInterval(3 * 86_400),
        cadence: .daily,
        isExempt: true
      ),
    ]
    container.mainContext.insert(habit)
    try container.mainContext.save()

    let context = ModelContext(container)
    let buckets = try context.fetch(FetchDescriptor<HabitBucket>())
    let open = try #require(buckets.first { $0.periodKey == "day:2026-07-30" })
    #expect(open.finalizedAt == nil)
    #expect(open.verdictRawValue == nil)
    #expect(open.targetSnapshot == nil)
    #expect(open.unitSnapshot == nil)
    #expect(!open.isExempt)

    let final = try #require(buckets.first { $0.periodKey == "day:2026-07-31" })
    #expect(final.finalizedAt == finalizedAt)
    #expect(final.verdictRawValue == "met")
    #expect(final.targetSnapshot == 30)
    #expect(final.unitSnapshot == "min")

    let exempt = try #require(buckets.first { $0.periodKey == "day:2026-08-01" })
    #expect(exempt.isExempt)
    #expect(exempt.finalizedAt == nil)
  }

  @Test("entries preserve aggregate ownership and explicit bucket membership")
  func entriesPreserveAggregateOwnershipAndBucketMembership() throws {
    let container = try makeContainer()
    let habit = Habit(name: "Water", cadence: .daily, target: 64, unit: "oz")
    let start = Date(timeIntervalSince1970: 6_000_000)
    let bucket = HabitBucket(
      periodKey: "day:2026-08-01",
      startAt: start,
      endAt: start.addingTimeInterval(86_400),
      cadence: .daily
    )
    let backfill = LogEntry(timestamp: start.addingTimeInterval(-3_600), amount: 8)
    let current = LogEntry(timestamp: start.addingTimeInterval(900), amount: 24)
    habit.buckets = [bucket]
    habit.entries = [backfill, current]
    bucket.entries = [backfill, current]

    #expect(backfill.habit === habit)
    #expect(backfill.bucket === bucket)
    #expect(current.habit === habit)
    #expect(current.bucket === bucket)

    container.mainContext.insert(habit)
    try container.mainContext.save()

    let context = ModelContext(container)
    let fetchedHabit = try #require(context.fetch(FetchDescriptor<Habit>()).first)
    let fetchedBucket = try #require(context.fetch(FetchDescriptor<HabitBucket>()).first)
    let entries = try #require(fetchedBucket.entries)
    #expect(entries.map(\.amount).reduce(0, +) == 32)
    #expect(entries.allSatisfy { $0.habit?.id == fetchedHabit.id })
    #expect(entries.allSatisfy { $0.bucket?.id == fetchedBucket.id })
    #expect(entries.contains { $0.timestamp < fetchedBucket.startAt })
  }

  @Test("deleting a bucket nullifies entry membership without deleting the entry")
  func deletingBucketNullifiesEntryMembership() throws {
    let container = try makeContainer()
    let habit = Habit(name: "Water", cadence: .daily, target: 64, unit: "oz")
    let start = Date(timeIntervalSince1970: 6_500_000)
    let bucket = HabitBucket(
      periodKey: "day:2026-08-01",
      startAt: start,
      endAt: start.addingTimeInterval(86_400),
      cadence: .daily
    )
    let entry = LogEntry(timestamp: start, amount: 8)
    habit.buckets = [bucket]
    habit.entries = [entry]
    bucket.entries = [entry]
    container.mainContext.insert(habit)
    try container.mainContext.save()

    container.mainContext.delete(bucket)
    try container.mainContext.save()

    let context = ModelContext(container)
    let fetchedEntry = try #require(context.fetch(FetchDescriptor<LogEntry>()).first)
    #expect(try context.fetch(FetchDescriptor<HabitBucket>()).isEmpty)
    #expect(fetchedEntry.bucket == nil)
    #expect(fetchedEntry.habit?.id == habit.id)
  }

  @Test("deleting a habit cascades through buckets and entries")
  func deletingHabitCascadesThroughBucketsAndEntries() throws {
    let container = try makeContainer()
    let habit = Habit(name: "Water", cadence: .daily, target: 64, unit: "oz")
    let start = Date(timeIntervalSince1970: 7_000_000)
    let bucket = HabitBucket(
      periodKey: "day:2026-08-01",
      startAt: start,
      endAt: start.addingTimeInterval(86_400),
      cadence: .daily
    )
    let entry = LogEntry(timestamp: start, amount: 8)
    habit.buckets = [bucket]
    habit.entries = [entry]
    bucket.entries = [entry]
    container.mainContext.insert(habit)
    try container.mainContext.save()

    container.mainContext.delete(habit)
    try container.mainContext.save()

    let context = ModelContext(container)
    #expect(try context.fetch(FetchDescriptor<Habit>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<HabitBucket>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<LogEntry>()).isEmpty)
  }

  @Test("versioned schemas preserve historical models and advance current models")
  func versionedSchemasPreserveHistoricalModelsAndAdvanceCurrentModels() {
    let versionOneModels = Set(TendSchemaV1.models.map(ObjectIdentifier.init))
    let expectedVersionOneModels = Set([
      ObjectIdentifier(Habit.self),
      ObjectIdentifier(HabitActivityPeriod.self),
      ObjectIdentifier(HabitBucket.self),
      ObjectIdentifier(LogEntry.self),
    ])
    let versionTwoModels = Set(TendSchemaV2.models.map(ObjectIdentifier.init))
    let expectedVersionTwoModels = expectedVersionOneModels.union([
      ObjectIdentifier(TendSchemaV2.Goal.self),
      ObjectIdentifier(TendSchemaV2.GoalEntry.self),
      ObjectIdentifier(TendSchemaV2.GoalReading.self),
    ])
    let versionThreeModels = Set(TendSchemaV3.models.map(ObjectIdentifier.init))
    let expectedVersionThreeModels = expectedVersionOneModels.union([
      ObjectIdentifier(Goal.self),
      ObjectIdentifier(GoalEntry.self),
      ObjectIdentifier(GoalReading.self),
    ])
    let versionFourModels = Set(TendSchemaV4.models.map(ObjectIdentifier.init))
    let expectedVersionFourModels = expectedVersionThreeModels.union([
      ObjectIdentifier(JournalEntry.self)
    ])

    #expect(TendSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    #expect(versionOneModels == expectedVersionOneModels)
    #expect(TendSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
    #expect(versionTwoModels == expectedVersionTwoModels)
    #expect(TendSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
    #expect(versionThreeModels == expectedVersionThreeModels)
    #expect(TendSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
    #expect(versionFourModels == expectedVersionFourModels)
    #expect(TendMigrationPlan.schemas.count == 4)
    #expect(TendMigrationPlan.stages.count == 3)
  }

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: TendSchemaV1.self)
    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(
      for: schema,
      migrationPlan: TendMigrationPlan.self,
      configurations: [configuration]
    )
  }
}
