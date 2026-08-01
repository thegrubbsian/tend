import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Habit persistence")
struct HabitModelTests {
  @Test("daily habit defaults round-trip")
  func dailyHabitDefaultsRoundTrip() throws {
    let container = try makeContainer()
    let id = try #require(UUID(uuidString: "38CB4430-3FC0-4D68-A2CB-5F37DC22669E"))
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let habit = Habit(
      id: id,
      name: "Meditation",
      cadence: .daily,
      target: 10,
      createdAt: createdAt
    )

    container.mainContext.insert(habit)
    try container.mainContext.save()

    let context = ModelContext(container)
    let fetched = try #require(context.fetch(FetchDescriptor<Habit>()).first)
    #expect(fetched.id == id)
    #expect(fetched.name == "Meditation")
    #expect(fetched.cadenceRawValue == "daily")
    #expect(fetched.target == 10)
    #expect(fetched.unit == "times")
    #expect(fetched.pinnedWeekdaysRawValue == 0)
    #expect(fetched.reminderMinuteOfDay == nil)
    #expect(fetched.isActive)
    #expect(fetched.createdAt == createdAt)
    #expect(fetched.bestStreak == 0)
    #expect(fetched.activityPeriods?.isEmpty == true)
  }

  @Test("weekly habit explicit values replace schema defaults")
  func weeklyHabitExplicitValuesReplaceSchemaDefaults() throws {
    let container = try makeContainer()
    let pinnedDays = try #require(PinnedWeekdays(rawValue: 5))
    let reminder = try #require(ReminderTime(hour: 9, minute: 0))
    let habit = Habit(
      name: "LinkedIn",
      cadence: .weekly,
      target: 2,
      unit: "posts",
      pinnedWeekdays: pinnedDays,
      reminderTime: reminder,
      isActive: false,
      bestStreak: 9
    )

    container.mainContext.insert(habit)
    try container.mainContext.save()

    let context = ModelContext(container)
    let fetched = try #require(context.fetch(FetchDescriptor<Habit>()).first)
    #expect(fetched.cadenceRawValue == "weekly")
    #expect(fetched.target == 2)
    #expect(fetched.unit == "posts")
    #expect(fetched.pinnedWeekdaysRawValue == 5)
    #expect(fetched.reminderMinuteOfDay == 540)
    #expect(!fetched.isActive)
    #expect(fetched.bestStreak == 9)
  }

  @Test("open and closed activity periods preserve both relationship directions")
  func activityPeriodsPreserveBothRelationshipDirections() throws {
    let container = try makeContainer()
    let habit = Habit(name: "Garden", cadence: .daily, target: 1)
    let openStart = Date(timeIntervalSince1970: 1_750_000_000)
    let closedStart = Date(timeIntervalSince1970: 1_700_000_000)
    let closedEnd = Date(timeIntervalSince1970: 1_710_000_000)
    let openPeriod = HabitActivityPeriod(startedAt: openStart)
    let closedPeriod = HabitActivityPeriod(startedAt: closedStart, endedAt: closedEnd)
    habit.activityPeriods = [openPeriod, closedPeriod]

    #expect(openPeriod.habit === habit)
    #expect(closedPeriod.habit === habit)

    container.mainContext.insert(habit)
    try container.mainContext.save()

    let context = ModelContext(container)
    let fetchedHabit = try #require(context.fetch(FetchDescriptor<Habit>()).first)
    let periods = try #require(fetchedHabit.activityPeriods)
      .sorted { $0.startedAt < $1.startedAt }
    #expect(periods.count == 2)
    #expect(periods[0].startedAt == closedStart)
    #expect(periods[0].endedAt == closedEnd)
    #expect(periods[0].habit?.id == fetchedHabit.id)
    #expect(periods[1].startedAt == openStart)
    #expect(periods[1].endedAt == nil)
    #expect(periods[1].habit?.id == fetchedHabit.id)
  }

  @Test("deleting a habit cascades to its activity periods")
  func deletingHabitCascadesToActivityPeriods() throws {
    let container = try makeContainer()
    let habit = Habit(name: "Garden", cadence: .daily, target: 1)
    habit.activityPeriods = [HabitActivityPeriod(startedAt: .now)]
    container.mainContext.insert(habit)
    try container.mainContext.save()

    container.mainContext.delete(habit)
    try container.mainContext.save()

    let context = ModelContext(container)
    #expect(try context.fetch(FetchDescriptor<Habit>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<HabitActivityPeriod>()).isEmpty)
  }

  @Test("storage preserves imported values for later domain validation")
  func storagePreservesImportedValuesForLaterDomainValidation() throws {
    let container = try makeContainer()
    let habit = Habit(name: "Imported", cadence: .daily, target: 1)
    habit.name = ""
    habit.cadenceRawValue = "monthly"
    habit.target = 0
    habit.pinnedWeekdaysRawValue = 128
    habit.reminderMinuteOfDay = 1_440
    container.mainContext.insert(habit)
    try container.mainContext.save()

    let context = ModelContext(container)
    let fetched = try #require(context.fetch(FetchDescriptor<Habit>()).first)
    #expect(fetched.name == "")
    #expect(fetched.cadenceRawValue == "monthly")
    #expect(fetched.target == 0)
    #expect(fetched.pinnedWeekdaysRawValue == 128)
    #expect(fetched.reminderMinuteOfDay == 1_440)
  }

  private func makeContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(
      for: Habit.self,
      HabitActivityPeriod.self,
      configurations: configuration
    )
  }
}
