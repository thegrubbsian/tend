import SwiftData

public enum TendSchemaV1: VersionedSchema {
  public static let versionIdentifier = Schema.Version(1, 0, 0)

  public static var models: [any PersistentModel.Type] {
    [Habit.self, HabitActivityPeriod.self, HabitBucket.self, LogEntry.self]
  }
}

public enum TendMigrationPlan: SchemaMigrationPlan {
  public static var schemas: [any VersionedSchema.Type] {
    [TendSchemaV1.self]
  }

  public static var stages: [MigrationStage] {
    []
  }
}
