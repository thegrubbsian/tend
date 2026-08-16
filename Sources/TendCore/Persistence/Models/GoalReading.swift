import Foundation
import SwiftData

@Model
public final class GoalReading {
  public var id: UUID = UUID()
  public var value: Int = 0
  public var assignedDateKey: String = ""
  public var appendedAt: Date = Date()
  public var appendSequence: Int = 0
  public var goal: Goal?

  public init(
    id: UUID = UUID(),
    value: Int,
    assignedDate: GoalDate,
    appendedAt: Date,
    appendSequence: Int,
    goal: Goal? = nil
  ) {
    self.id = id
    self.value = value
    assignedDateKey = assignedDate.rawValue
    self.appendedAt = appendedAt
    self.appendSequence = appendSequence
    self.goal = goal
  }
}
