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
}

public enum TendMigrationPlan: SchemaMigrationPlan {
  public static var schemas: [any VersionedSchema.Type] {
    [TendSchemaV1.self, TendSchemaV2.self]
  }

  public static var stages: [MigrationStage] {
    [
      .lightweight(fromVersion: TendSchemaV1.self, toVersion: TendSchemaV2.self)
    ]
  }
}
