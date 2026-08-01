import Foundation
import SwiftData

@Model
public final class LogEntry {
  public var id: UUID = UUID()
  public var timestamp: Date = Date()
  public var amount: Int = 1
  public var habit: Habit?
  public var bucket: HabitBucket?

  public init(
    id: UUID = UUID(),
    timestamp: Date,
    amount: Int,
    habit: Habit? = nil,
    bucket: HabitBucket? = nil
  ) {
    self.id = id
    self.timestamp = timestamp
    self.amount = amount
    self.habit = habit
    self.bucket = bucket
  }
}
