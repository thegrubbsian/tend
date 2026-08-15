# Append and delete recent goal progress

## Approach

Add recent progress mutations on goals/goal-records/goal-creation (T-3vd0jv).
Start with `GoalProgressOperationsTests` and follow the existing logging
boundary: explicit clock and TimeZone, relationship identity, complete planning
before mutation, one mutation save, and operation-local rollback.

Define `GoalProgressDestination` with only Today and Yesterday. Add a main-actor
`GoalProgressOperations` service over one caller-supplied ModelContext, with
production and injectable-save initializers.

For every append, resolve the destination GoalDate from the supplied operation
instant and TimeZone. Yesterday is unavailable when it precedes the GoalDate
containing the goal's creation instant. Validate the Goal's persistence
identity, kind, scalar configuration, child collection, inverse relationships,
stored date keys, and sequence history before inserting.

Provide kind-specific methods:

- append a positive integer amount to an Accumulate goal as one GoalEntry;
- append any representable integer value to a Measure goal as one GoalReading.

Each child stores the resolved assigned date, exact operation timestamp, and the
next checked append sequence. Sequence is strictly increasing within the
goal's relevant child collection; scan and reject negative, duplicate, or
overflowing persisted sequence state rather than guessing an order. Cross-kind
append is a typed error. Save exactly once.

Delete accepts the Goal and a persisted GoalEntry or GoalReading. Validate
persistent identity, exact inverse membership, kind, scalar and sequence state,
and stored GoalDate. Authorize only when that date equals Today or Yesterday at
the explicit deletion instant; append timestamp never extends eligibility.
Remove exactly one child and save once. Expose no update API for child facts.

On append-save failure, detach the new child and inverse. On delete-save
failure, restore the exact child and inverse position/facts. Do not roll back
unrelated pending context work. Validation failures perform zero saves.
goals/goal-lifecycle (F-5aficd) later adds its closed-goal guard to this same
surface.

## Surfaces

- Create `Sources/TendCore/Goals/GoalProgressOperations.swift`.
- Create
  `Tests/TendCoreTests/Goals/GoalProgressOperationsTests.swift`.
- Reuse GoalDate calendar arithmetic and the Goal/child models from prior
  records tasks.
- Add small private validation helpers rather than a generic repository or
  command framework.
- Do not add progress calculation, closure, goal editing/deletion, UI, haptics,
  notifications, or habit logging changes.

## Tests

Bind feature criterion C3 to `GoalProgressOperationsTests`.

Append Today and Yesterday Accumulate amounts and Measure readings with exact
assigned dates, append timestamps, increasing sequences, inverse membership,
and one save. Cover multiple same-instant and same-day appends to prove sequence
records actual order. Prove Accumulate over-target append and signed Measure
values remain valid.

Reject zero/negative Accumulate amount, cross-kind append, detached/deleted or
foreign-context Goal, Yesterday before the creation date, malformed goal
configuration, invalid child inverses, malformed dates, negative or duplicate
sequences, and next-sequence overflow with no mutation or save.

Delete the first, middle, last, and only child while its assigned date remains
Today or Yesterday. Advance the explicit clock to prove an item becomes
immutable at the start of the second following local day, including DST and
time-zone changes. Reject foreign, detached, cross-kind, older, future, and
internally inconsistent children.

Inject append and delete save failures. Assert one attempted save, exact
relationship restoration, no orphan child, stable existing sequences, and
preservation of unrelated pending changes.

Run:

- `Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalProgressOperationsTests.swift`
- `Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalCreationOperationsTests.swift`
- `Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/GoalPersistenceTests.swift`
- `Scripts/tiller-swift-test`
- `swift build`

## Edge cases

- A Goal created Today may receive Today progress but not Yesterday progress.
- A Goal created Yesterday may receive progress for either eligible date.
- Back-filling Yesterday today stores today's append timestamp and yesterday's
  assigned GoalDate.
- Multiple readings on one date are valid and preserve append order.
- Deleting a Yesterday item at exactly local midnight one day later is still
  valid; at the next local midnight it is too old.
- A time-zone change can change which GoalDates are currently Today and
  Yesterday without rewriting stored dates.
- Repeated successful append calls are separate facts; no amount, value, date,
  or timestamp deduplication occurs.
