import SwiftData
import Testing

@testable import TendCore

@Suite("CloudKit schema compatibility")
struct CloudKitSchemaCompatibilityTests {
  @Test("version one has no CloudKit-incompatible schema metadata")
  func versionOneHasNoCloudKitIncompatibleMetadata() {
    let schema = Schema(versionedSchema: TendSchemaV1.self)
    var violations: [String] = []

    for entity in schema.entities {
      if !entity.uniquenessConstraints.isEmpty {
        violations.append("\(entity.name) has uniqueness constraints")
      }

      for attribute in entity.attributes {
        if attribute.isUnique {
          violations.append("\(entity.name).\(attribute.name) is unique")
        }
        if !attribute.isOptional, attribute.defaultValue == nil {
          violations.append("\(entity.name).\(attribute.name) has no default")
        }
      }

      for relationship in entity.relationships {
        if !relationship.isOptional {
          violations.append("\(entity.name).\(relationship.name) is nonoptional")
        }
        if relationship.inverseName?.isEmpty != false {
          violations.append("\(entity.name).\(relationship.name) has no inverse")
        }
        if relationship.deleteRule == .deny {
          violations.append("\(entity.name).\(relationship.name) uses deny")
        }
      }
    }

    #expect(
      violations.isEmpty,
      "CloudKit-incompatible schema metadata: \(violations.joined(separator: ", "))"
    )
  }
}
