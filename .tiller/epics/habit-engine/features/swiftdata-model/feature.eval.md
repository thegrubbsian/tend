---
node: F-n7oy52
criteria:
  - id: C1
    statement: TendCore compiles for a generic iOS device with the iOS 26 and Swift 6 package configuration
    polarity: introduce
    binding:
      type: command
      run: "xcodebuild -scheme TendCore -destination 'generic/platform=iOS' build"
    required: true
  - id: C2
    statement: The complete persistence suite passes without an iPhone or simulator UI
    polarity: introduce
    binding: { type: command, run: "swift test" }
    required: true
  - id: C3
    statement: Habits and activity periods round-trip every required durable property and relationship
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Persistence/HabitModelTests.swift" }
    required: true
  - id: C4
    statement: Buckets and log entries round-trip canonical cadence-qualified identity, half-open period boundaries, snapshots, exemptions, verdicts, amounts, and aggregate ownership
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Persistence/BucketEntryModelTests.swift" }
    required: true
  - id: C5
    statement: A saved file-backed store reopens with the same history while production configuration keeps CloudKit disabled
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Persistence/PersistenceContainerTests.swift" }
    required: true
  - id: C6
    statement: The schema uses no unique constraints or deny rules and every relationship is optional with an explicit inverse compatible with future CloudKit adoption
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Persistence/CloudKitSchemaCompatibilityTests.swift" }
    required: true
  - id: C7
    statement: TendCore has no external package dependency
    polarity: introduce
    binding:
      type: command
      run: "swift package show-dependencies --format json | jq -e '.dependencies | length == 0'"
    required: true
---

# Acceptance

The contract covers only the persistence capability this feature can make green:
platform compilation, device-free model checks, durable local storage, a
CloudKit-compatible shape with synchronization disabled, and dependency
independence. Calendar evaluation, mutation policy, activity transitions, and
streak correctness remain acceptance concerns of their dependent features.
