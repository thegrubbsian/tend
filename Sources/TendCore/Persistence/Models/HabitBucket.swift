import Foundation
import SwiftData

@Model
public final class HabitBucket {
  public var id: UUID = UUID()
  public var periodKey: String = ""
  public var startAt: Date = Date()
  public var endAt: Date = Date()
  public var cadenceRawValue: String = "daily"
  public var isExempt: Bool = false
  public var finalizedAt: Date?
  public var verdictRawValue: String?
  public var targetSnapshot: Int?
  public var unitSnapshot: String?
  public var habit: Habit?

  @Relationship(deleteRule: .nullify, inverse: \LogEntry.bucket)
  public var entries: [LogEntry]? = []

  public init(
    id: UUID = UUID(),
    periodKey: String,
    startAt: Date,
    endAt: Date,
    cadence: HabitCadence,
    isExempt: Bool = false,
    finalizedAt: Date? = nil,
    verdict: BucketVerdict? = nil,
    targetSnapshot: Int? = nil,
    unitSnapshot: String? = nil,
    habit: Habit? = nil
  ) {
    self.id = id
    self.periodKey = periodKey
    self.startAt = startAt
    self.endAt = endAt
    cadenceRawValue = cadence.rawValue
    self.isExempt = isExempt
    self.finalizedAt = finalizedAt
    verdictRawValue = verdict?.rawValue
    self.targetSnapshot = targetSnapshot
    self.unitSnapshot = unitSnapshot
    self.habit = habit
  }
}
