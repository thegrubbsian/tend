import Foundation
import SwiftData

public enum TendSchemaV1: VersionedSchema {
  public static let versionIdentifier = Schema.Version(1, 0, 0)

  public static var models: [any PersistentModel.Type] {
    [Habit.self, HabitActivityPeriod.self, HabitBucket.self, LogEntry.self]
  }
}

public enum TendSchemaV2: VersionedSchema {
  public static let versionIdentifier = Schema.Version(2, 0, 0)

  public static var models: [any PersistentModel.Type] {
    [
      Habit.self,
      HabitActivityPeriod.self,
      HabitBucket.self,
      LogEntry.self,
      Goal.self,
      GoalEntry.self,
      GoalReading.self,
    ]
  }

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
      deadline: LocalDate? = nil,
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
      assignedDate: LocalDate,
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
}

public enum TendSchemaV3: VersionedSchema {
  public static let versionIdentifier = Schema.Version(3, 0, 0)

  public static var models: [any PersistentModel.Type] {
    [
      Habit.self,
      HabitActivityPeriod.self,
      HabitBucket.self,
      LogEntry.self,
      Goal.self,
      GoalEntry.self,
      GoalReading.self,
    ]
  }
}

public enum TendMigrationPlan: SchemaMigrationPlan {
  public static var schemas: [any VersionedSchema.Type] {
    [TendSchemaV1.self, TendSchemaV2.self, TendSchemaV3.self]
  }

  public static var stages: [MigrationStage] {
    [
      .lightweight(fromVersion: TendSchemaV1.self, toVersion: TendSchemaV2.self),
      .lightweight(fromVersion: TendSchemaV2.self, toVersion: TendSchemaV3.self),
    ]
  }
}
