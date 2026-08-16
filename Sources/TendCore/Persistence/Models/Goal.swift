import Foundation
import SwiftData

@Model
public final class Goal {
  public var id: UUID = UUID()
  public var name: String = ""
  public var kindRawValue: String = "accumulate"
  public var target: Int = 1
  public var unit: String = "times"
  public var baseline: Int?
  public var deadlineKey: String?
  public var createdAt: Date = Date()

  @Relationship(deleteRule: .cascade, inverse: \GoalEntry.goal)
  public var entries: [GoalEntry]? = []

  @Relationship(deleteRule: .cascade, inverse: \GoalReading.goal)
  public var readings: [GoalReading]? = []

  public init(
    id: UUID = UUID(),
    name: String,
    kind: GoalKind,
    target: Int,
    unit: String = "times",
    baseline: Int? = nil,
    deadline: GoalDate? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    kindRawValue = kind.rawValue
    self.target = target
    self.unit = unit
    self.baseline = baseline
    deadlineKey = deadline?.rawValue
    self.createdAt = createdAt
  }
}
