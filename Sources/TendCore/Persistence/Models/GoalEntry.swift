import Foundation
import SwiftData

@Model
public final class GoalEntry {
  public var id: UUID = UUID()
  public var amount: Int = 1
  public var assignedDateKey: String = ""
  public var appendedAt: Date = Date()
  public var appendSequence: Int = 0
  public var goal: Goal?

  public init(
    id: UUID = UUID(),
    amount: Int,
    assignedDate: LocalDate,
    appendedAt: Date,
    appendSequence: Int,
    goal: Goal? = nil
  ) {
    self.id = id
    self.amount = amount
    assignedDateKey = assignedDate.rawValue
    self.appendedAt = appendedAt
    self.appendSequence = appendSequence
    self.goal = goal
  }
}
