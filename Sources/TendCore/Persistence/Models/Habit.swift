import Foundation
import SwiftData

@Model
public final class Habit {
  public var id: UUID = UUID()
  public var name: String = ""
  public var cadenceRawValue: String = "daily"
  public var target: Int = 1
  public var unit: String = "times"
  public var pinnedWeekdaysRawValue: Int = 0
  public var reminderMinuteOfDay: Int?
  public var isActive: Bool = true
  public var createdAt: Date = Date()
  public var bestStreak: Int = 0

  @Relationship(deleteRule: .cascade, inverse: \HabitActivityPeriod.habit)
  public var activityPeriods: [HabitActivityPeriod]? = []

  @Relationship(deleteRule: .cascade, inverse: \HabitBucket.habit)
  public var buckets: [HabitBucket]? = []

  @Relationship(deleteRule: .cascade, inverse: \LogEntry.habit)
  public var entries: [LogEntry]? = []

  public init(
    id: UUID = UUID(),
    name: String,
    cadence: HabitCadence,
    target: Int,
    unit: String = "times",
    pinnedWeekdays: PinnedWeekdays = .none,
    reminderTime: ReminderTime? = nil,
    isActive: Bool = true,
    createdAt: Date = Date(),
    bestStreak: Int = 0
  ) {
    self.id = id
    self.name = name
    cadenceRawValue = cadence.rawValue
    self.target = target
    self.unit = unit
    pinnedWeekdaysRawValue = pinnedWeekdays.rawValue
    reminderMinuteOfDay = reminderTime?.rawValue
    self.isActive = isActive
    self.createdAt = createdAt
    self.bestStreak = bestStreak
  }
}
