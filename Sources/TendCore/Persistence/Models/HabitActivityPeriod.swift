import Foundation
import SwiftData

@Model
public final class HabitActivityPeriod {
  public var id: UUID = UUID()
  public var startedAt: Date = Date()
  public var endedAt: Date?
  public var habit: Habit?

  public init(
    id: UUID = UUID(),
    startedAt: Date,
    endedAt: Date? = nil,
    habit: Habit? = nil
  ) {
    self.id = id
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.habit = habit
  }
}
