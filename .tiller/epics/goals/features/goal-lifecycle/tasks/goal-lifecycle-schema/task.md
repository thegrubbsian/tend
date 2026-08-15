# Add durable goal closure state

## Approach

Extend the versioned persistence model produced by goals/goal-records
(F-e149jw) with the minimum durable lifecycle fact: an optional closure
disposition. Inspect and reuse the prerequisite's Goal model, enum-storage, and
migration conventions rather than creating a parallel lifecycle record.

Define a public, `Equatable`, `Sendable`, stable raw-value `GoalClosure` with
exactly `harvested` and `letGo`. Persist its optional raw representation on
Goal, where nil means open. Expose checked model access that distinguishes nil
from an unknown stored value; never map an unknown raw value to open or a known
case.

Add the next schema version and a lightweight migration from the prerequisite
goal schema. Every existing Goal must acquire nil closure while retaining its
identity, kind, configuration, creation time, deadline, and all accumulate-entry
or measure-reading relationships. Update the production migration plan and
container to use the new latest schema without changing the in-memory test
factory's public behavior.

Do not persist standing, expected progress, completion, a failure verdict, a
closed timestamp, or a second open flag. Do not add close/reopen operations in
this task. The output is a migration-safe lifecycle value that later tasks can
read and mutate.

## Surfaces

- Modify the Goal model created by goals/goal-records (F-e149jw) under
  `Sources/TendCore/Persistence/Models/`.
- Add `GoalClosure` beside the prerequisite's goal value types; do not overload
  habit model values with goal-only semantics.
- Modify `Sources/TendCore/Persistence/TendSchema.swift`.
- Modify `Sources/TendCore/Persistence/TendModelContainer.swift` only where the
  latest schema or migration plan changes.
- Create
  `Tests/TendCoreTests/Persistence/GoalLifecyclePersistenceTests.swift`.
- Modify focused persistence test helpers only to construct predecessor-schema
  stores.
- Do not modify app UI, goal progress arithmetic, habit models, or Pencil
  comps.

## Tests

Write `GoalLifecyclePersistenceTests` first. Cover nil, harvested, and let-go
round trips; stable raw values; relationship round trips for both goal kinds;
and an on-disk migration fixture containing multiple goals plus progress
children under the exact prerequisite schema. Assert migrated goals are open,
all ordinary fields and persistent identities remain stable, every child
relationship survives, and the store reopens through the production migration
plan.

Seed an unknown closure raw value through the lowest supported persistence test
boundary and prove checked access or store opening fails honestly. Do not assert
private property names when owner-visible durable behavior can establish the
contract.

Run:

- `Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/GoalLifecyclePersistenceTests.swift`
- `Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/PersistenceContainerTests.swift`
- `Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/CloudKitSchemaCompatibilityTests.swift`
- `swift build`

## Edge cases

- A migrated store may contain no goals, one kind, both kinds, or goals with no
  progress children.
- Nil closure is the only open representation; an empty string is corrupt, not
  nil.
- Migration must not reassign Goal or child identities, change cascade rules,
  normalize owner text, or recalculate progress.
- Schema registration order remains deterministic and includes all existing
  habit and goal model types.
- Unknown future raw values fail rather than silently reopening a closed goal.
- Reopening later clears the optional value; it never deletes a lifecycle
  record because no separate record exists.
