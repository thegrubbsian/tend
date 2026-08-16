# Add goal persistence and date values

## Approach

Extend TendCore's local versioned SwiftData store with a separate Goal
aggregate. Start with `GoalPersistenceTests` against the current habit-only
schema, then add one additive schema version and migration. Reuse existing
scalar raw-value, optional inverse, cascade, local-only configuration, and
file-backed test conventions.

Define a public, `Equatable`, `Comparable`, `Codable`, and `Sendable`
`GoalDate`. It validates Gregorian year/month/day, round-trips one fixed
`YYYY-MM-DD` key, resolves the containing local day from an explicit TimeZone,
and returns adjacent dates through calendar arithmetic. It never stores a time
zone or normalizes an impossible date.

Define stable raw-value `GoalKind` cases `accumulate` and `measure`. Add three
SwiftData models:

- Goal: UUID, name, kind raw value, target, unit, optional baseline, optional
  deadline key, created-at timestamp, entries, and readings.
- GoalEntry: UUID, positive amount storage, assigned date key, append timestamp,
  append sequence, and Goal inverse.
- GoalReading: UUID, integer value, assigned date key, append timestamp, append
  sequence, and Goal inverse.

Keep storage models migration-permissive: checked domain operations and
computations enforce nonempty text, positive amounts, kind-specific
relationships, valid sequences, and valid date keys. Give every nonoptional
stored attribute a schema-visible default. Use optional relationships with
explicit inverses, Goal-to-child cascade deletion, no unique constraints, and
no deny rules.

Add the new models to the next `VersionedSchema`, migrate the current complete
habit store unchanged, and make that schema current in production, in-memory,
and injected file-backed containers. Keep CloudKit disabled and preserve honest
container errors. Add no sample goals and no closure field owned by
goals/goal-lifecycle (F-5aficd).

## Surfaces

- Create `Sources/TendCore/Goals/GoalDate.swift`.
- Create `Sources/TendCore/Goals/GoalKind.swift`.
- Create `Sources/TendCore/Persistence/Models/Goal.swift`.
- Create `Sources/TendCore/Persistence/Models/GoalEntry.swift`.
- Create `Sources/TendCore/Persistence/Models/GoalReading.swift`.
- Modify `Sources/TendCore/Persistence/TendSchema.swift`.
- Modify `Sources/TendCore/Persistence/TendModelContainer.swift` for the latest
  schema and migration plan.
- Create `Tests/TendCoreTests/Persistence/GoalPersistenceTests.swift`.
- Modify focused model-value, container, and CloudKit-compatibility tests for
  the additive schema.
- Do not modify habit model shapes, logging operations, app UI, or Pencil comps.

## Tests

Write `GoalPersistenceTests` first. Cover GoalDate round-trip, comparison,
impossible and malformed keys, previous/next date across month, year, leap day,
spring-forward, and fall-back boundaries, and resolution under multiple time
zones.

Round-trip Accumulate and Measure aggregates with zero, one, and many
kind-specific children through in-memory and reopened file-backed containers.
Assert every scalar, UUID, date key, append timestamp, sequence, inverse, and
cascade relationship. Prove deleting Goal cascades both child collections while
deleting one child leaves Goal intact.

Create a file-backed fixture under the exact prior schema containing complete
habit, activity, bucket, and log history. Migrate and reopen it through the
production plan. Assert all preexisting identities, attributes, relationships,
and counts are unchanged and no Goal appears.

Run:

- `Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/GoalPersistenceTests.swift`
- `Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/ModelValueTests.swift`
- `Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/PersistenceContainerTests.swift`
- `Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/CloudKitSchemaCompatibilityTests.swift`
- `swift build`

## Edge cases

- GoalDate year, month, and day remain owner date components across time-zone
  changes; only resolution to Date moves.
- Lexicographic GoalDate keys must preserve chronological order for every
  supported four-digit year.
- Empty optional relationship arrays and nil inverses remain legal storage
  states so checked domain code can report corruption rather than the store
  failing unpredictably.
- Unknown kind and malformed date raw values persist only as corrupt imported
  state and fail checked access; they never default to Accumulate or Today.
- Stable UUIDs are ordinary attributes and may collide; SwiftData persistent
  identity remains aggregate ownership.
- This schema version contains no standing, closure, progress cache, direction,
  bucket, verdict, or streak field for goals.
