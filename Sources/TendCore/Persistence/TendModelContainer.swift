import Foundation
import SwiftData

public enum TendModelContainer {
  static let schema = Schema(versionedSchema: TendSchemaV3.self)

  static let productionConfiguration = ModelConfiguration(
    "Tend",
    schema: schema,
    isStoredInMemoryOnly: false,
    groupContainer: .none,
    cloudKitDatabase: .none
  )

  public static func production() throws -> ModelContainer {
    try make(configuration: productionConfiguration)
  }

  public static func inMemory() throws -> ModelContainer {
    let configuration = ModelConfiguration(
      "TendInMemory",
      schema: schema,
      isStoredInMemoryOnly: true,
      groupContainer: .none,
      cloudKitDatabase: .none
    )
    return try make(configuration: configuration)
  }

  public static func fileBacked(at storeURL: URL) throws -> ModelContainer {
    guard storeURL.isFileURL else {
      throw CocoaError(.fileWriteUnsupportedScheme)
    }

    var isDirectory: ObjCBool = false
    let storeDirectory = storeURL.deletingLastPathComponent()
    guard
      FileManager.default.fileExists(
        atPath: storeDirectory.path,
        isDirectory: &isDirectory
      ),
      isDirectory.boolValue
    else {
      throw CocoaError(.fileWriteInvalidFileName)
    }

    let configuration = ModelConfiguration(
      "Tend",
      schema: schema,
      url: storeURL,
      cloudKitDatabase: .none
    )
    return try make(configuration: configuration)
  }

  private static func make(configuration: ModelConfiguration) throws -> ModelContainer {
    try ModelContainer(
      for: schema,
      migrationPlan: TendMigrationPlan.self,
      configurations: [configuration]
    )
  }
}
