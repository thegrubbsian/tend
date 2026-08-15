import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Persistence container")
struct PersistenceContainerTests {
  @Test("production configuration is local and version two")
  func productionConfigurationIsLocalAndVersionTwo() {
    let configuration = TendModelContainer.productionConfiguration

    #expect(configuration.name == "Tend")
    #expect(cloudKitIsDisabled(configuration.cloudKitDatabase))
    #expect(!configuration.isStoredInMemoryOnly)
    #expect(configuration.schema?.version == Schema.Version(2, 0, 0))
  }

  @Test("in-memory containers do not share state")
  func inMemoryContainersDoNotShareState() throws {
    let first = try TendModelContainer.inMemory()
    let second = try TendModelContainer.inMemory()
    first.mainContext.insert(
      Habit(name: "Meditation", cadence: .daily, target: 10, unit: "min")
    )
    try first.mainContext.save()

    #expect(try first.mainContext.fetch(FetchDescriptor<Habit>()).count == 1)
    #expect(try second.mainContext.fetch(FetchDescriptor<Habit>()).isEmpty)
  }

  @Test("a saved aggregate survives reopening the same file store")
  func savedAggregateSurvivesReopeningFileStore() throws {
    let location = try makeTemporaryStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    try saveCompleteAggregate(to: location.store)
    try verifyCompleteAggregate(in: location.store)
  }

  @Test("an invalid store location throws without an in-memory fallback")
  func invalidStoreLocationThrowsWithoutFallback() throws {
    let location = try makeTemporaryStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    try Data("not a directory".utf8).write(to: location.store)
    let invalidStore = location.store.appendingPathComponent("Tend.store")

    var reportedError = false
    do {
      _ = try TendModelContainer.fileBacked(at: invalidStore)
    } catch {
      reportedError = true
    }

    #expect(reportedError)
    #expect(!FileManager.default.fileExists(atPath: invalidStore.path))
  }

  private func makeTemporaryStoreLocation() throws -> (directory: URL, store: URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TendPersistenceTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false
    )
    return (directory, directory.appendingPathComponent("Tend.store"))
  }

  private func saveCompleteAggregate(to storeURL: URL) throws {
    let container = try TendModelContainer.fileBacked(at: storeURL)
    let context = ModelContext(container)
    let reminderTime = ReminderTime(hour: 8, minute: 30)!
    let habit = Habit(
      id: try #require(UUID(uuidString: "57CE3BA8-F330-4344-8110-02BFE626BB24")),
      name: "Water",
      cadence: .daily,
      target: 64,
      unit: "oz",
      reminderTime: reminderTime,
      isActive: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      bestStreak: 12
    )
    let period = HabitActivityPeriod(
      id: try #require(UUID(uuidString: "7D2908AA-213D-4F1A-B518-4251B39C3335")),
      startedAt: Date(timeIntervalSince1970: 1_700_000_100),
      endedAt: Date(timeIntervalSince1970: 1_700_086_500)
    )
    let bucket = HabitBucket(
      id: try #require(UUID(uuidString: "CA77E79C-866A-4C8A-A6A5-7C1C66D66BFC")),
      periodKey: "day:2023-11-14",
      startAt: Date(timeIntervalSince1970: 1_699_992_000),
      endAt: Date(timeIntervalSince1970: 1_700_078_400),
      cadence: .daily,
      finalizedAt: Date(timeIntervalSince1970: 1_700_164_800),
      verdict: .met,
      targetSnapshot: 64,
      unitSnapshot: "oz"
    )
    let entry = LogEntry(
      id: try #require(UUID(uuidString: "7B1590BF-5A29-4124-93B2-4DB44CF1D3B6")),
      timestamp: Date(timeIntervalSince1970: 1_700_040_000),
      amount: 64
    )
    habit.activityPeriods = [period]
    habit.buckets = [bucket]
    habit.entries = [entry]
    bucket.entries = [entry]

    context.insert(habit)
    try context.save()
  }

  private func verifyCompleteAggregate(in storeURL: URL) throws {
    let container = try TendModelContainer.fileBacked(at: storeURL)
    let context = ModelContext(container)
    let habit = try #require(context.fetch(FetchDescriptor<Habit>()).first)

    #expect(habit.id == UUID(uuidString: "57CE3BA8-F330-4344-8110-02BFE626BB24"))
    #expect(habit.name == "Water")
    #expect(habit.cadenceRawValue == "daily")
    #expect(habit.target == 64)
    #expect(habit.unit == "oz")
    #expect(habit.reminderMinuteOfDay == 510)
    #expect(!habit.isActive)
    #expect(habit.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(habit.bestStreak == 12)

    let period = try #require(habit.activityPeriods?.first)
    #expect(period.id == UUID(uuidString: "7D2908AA-213D-4F1A-B518-4251B39C3335"))
    #expect(period.startedAt == Date(timeIntervalSince1970: 1_700_000_100))
    #expect(period.endedAt == Date(timeIntervalSince1970: 1_700_086_500))
    #expect(period.habit?.id == habit.id)

    let bucket = try #require(habit.buckets?.first)
    #expect(bucket.id == UUID(uuidString: "CA77E79C-866A-4C8A-A6A5-7C1C66D66BFC"))
    #expect(bucket.periodKey == "day:2023-11-14")
    #expect(bucket.startAt == Date(timeIntervalSince1970: 1_699_992_000))
    #expect(bucket.endAt == Date(timeIntervalSince1970: 1_700_078_400))
    #expect(bucket.cadenceRawValue == "daily")
    #expect(!bucket.isExempt)
    #expect(bucket.finalizedAt == Date(timeIntervalSince1970: 1_700_164_800))
    #expect(bucket.verdictRawValue == "met")
    #expect(bucket.targetSnapshot == 64)
    #expect(bucket.unitSnapshot == "oz")
    #expect(bucket.habit?.id == habit.id)

    let entry = try #require(habit.entries?.first)
    #expect(entry.id == UUID(uuidString: "7B1590BF-5A29-4124-93B2-4DB44CF1D3B6"))
    #expect(entry.timestamp == Date(timeIntervalSince1970: 1_700_040_000))
    #expect(entry.amount == 64)
    #expect(entry.habit?.id == habit.id)
    #expect(entry.bucket?.id == bucket.id)
    #expect(bucket.entries?.first?.id == entry.id)
  }
  private func cloudKitIsDisabled(
    _ database: ModelConfiguration.CloudKitDatabase
  ) -> Bool {
    Mirror(reflecting: database).children.contains {
      $0.label == "_none" && $0.value as? Bool == true
    }
  }

}
