# Update and delete goals atomically

## Approach

Add persistence-aware goal management on
goals/goal-lifecycle/goal-standing-computation (T-c72xj8), reusing the
prerequisite Goal model, progress relationships, calendar-date value, and
SwiftData ownership conventions. Start with `GoalManagementOperationsTests`.

Define a public `GoalEditableFields` containing name, target, unit, optional
deadline, and optional baseline. Deliberately omit kind, created-at, closure,
and progress children. Add a main-actor `GoalManagementOperations` service over
one caller-supplied `ModelContext`, with a production initializer and internal
injectable save seam matching existing TendCore management operations.

`update` validates the persisted Goal by persistent model identity and
normalizes the complete proposed value before mutation:

- trim name and unit and reject either when empty;
- require target greater than zero;
- require nil baseline for Accumulate;
- require an integer baseline different from target for Measure;
- resolve any deadline with the supplied Calendar and TimeZone and require its
  exclusive following-day boundary to be later than `createdAt`.

Allow updates for open, harvested, and let-go goals. Apply every editable field
together and save once. Do not reconcile, rewrite, partition, or snapshot
existing entries/readings. Do not compute and persist progress or standing.
After success, callers use the existing progress and standing computations,
which immediately reinterpret the full history under the new scope.

`delete` accepts an owned open or closed Goal, deletes it through its
ModelContext, relies on the approved cascade relationships to remove every
accumulate entry or measure reading, and saves once. Confirmation remains an app
responsibility.

For both operations, refuse detached, deleted, and foreign-context goals before
mutation. Capture the exact fields and relationships owned by the operation.
On save failure, restore those facts and remove only operation-created pending
changes; never roll back unrelated caller work.

## Surfaces

- Create `Sources/TendCore/Goals/GoalManagementOperations.swift`.
- Create
  `Tests/TendCoreTests/Goals/GoalManagementOperationsTests.swift`.
- Reuse the prerequisite Goal and progress child models and
  goals/goal-lifecycle/goal-standing-computation (T-c72xj8) deadline semantics.
- Modify model relationship definitions only if the prerequisite cascade is
  incomplete; keep any correction in this task with a migration-safe test.
- Do not modify kind-specific progress math, closure operations, app forms,
  Today, reminders, habit management, or Pencil comps.

## Tests

Bind feature criterion C3 to `GoalManagementOperationsTests`.

Cover normalized successful updates for open and both closed dispositions;
Accumulate and increasing/decreasing Measure goals; target, baseline, unit,
name, and deadline changes; removed deadlines; and immediate recomputation of
progress and standing without mutated history or stored snapshots.

Reject empty normalized name/unit, zero or negative target, unexpected
Accumulate baseline, missing or target-equal Measure baseline, invalid
deadline chronology, detached/deleted goal, and a goal from another context.
Assert zero saves and no field or relationship mutation on validation failure.

Delete open, harvested, and let-go goals of both kinds with zero, one, and many
progress children. Save and reopen the store to prove the Goal and every child
are absent while unrelated goals and habits remain. Inject update and delete
save failures and assert one attempted save, complete restoration, intact
inverse relationships, and preservation of unrelated pending context changes.

Run:

- `Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalManagementOperationsTests.swift`
- `Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/GoalLifecyclePersistenceTests.swift`
- the focused goal records/progress tests created by goals/goal-records
  (F-e149jw)
- `Scripts/tiller-swift-test`
- `swift build`

## Edge cases

- Editing a closed goal changes the arc used after reopening but does not clear
  its closure.
- Moving a deadline before the current instant is valid when the deadline's
  full local day still follows creation; the recomputed open goal becomes past
  due.
- Moving a deadline to a date whose full local day ended before creation is
  invalid.
- Measure direction may reverse when baseline moves across target, but baseline
  may never equal target.
- Updating fields to their current normalized values still performs one
  explicit requested save; it is not silently converted into a no-op.
- Delete confirmation is not represented by a boolean domain parameter.
- Kind and created-at mutation remain impossible through the public update
  signature.
