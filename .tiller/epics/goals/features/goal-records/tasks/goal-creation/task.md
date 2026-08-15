# Create validated goals atomically

## Approach

Build the supported Goal creation transaction on
goals/goal-records/goal-persistence (T-6g59mr). Start with
`GoalCreationOperationsTests`. Keep SwiftData models permissive for migration;
enforce owner-entered invariants at the operation boundary.

Define `GoalCreationFields` with name, kind, target, unit defaulting to `times`,
optional baseline, and optional GoalDate deadline. Add a main-actor
`GoalCreationOperations` service over one caller-supplied ModelContext, with a
production initializer and an internal injectable save seam matching existing
TendCore operations.

`create(fields:at:timeZone:)` normalizes and validates the whole proposal before
insertion:

- trim name and unit and reject either when empty;
- require target greater than zero;
- require nil baseline for Accumulate;
- require an integer baseline different from target for Measure;
- resolve any deadline's following local-day boundary and require it to be
  later than the creation instant.

Insert exactly one Goal with the normalized configuration, requested immutable
kind, exact supplied creation timestamp, and empty entry/reading collections.
Do not add a baseline reading, target-1 completion, direction flag, open flag,
closure, or derived progress. Save once and return the persisted Goal.

On save failure, detach the inserted Goal and restore only inverse state created
by the operation. Preserve unrelated pending caller changes. Expose typed
validation and persistence failures rather than returning a partially inserted
or fabricated Goal.

## Surfaces

- Create `Sources/TendCore/Goals/GoalCreationOperations.swift`.
- Create
  `Tests/TendCoreTests/Goals/GoalCreationOperationsTests.swift`.
- Reuse Goal, GoalKind, GoalDate, and container APIs from
  goals/goal-records/goal-persistence (T-6g59mr).
- Do not add update/delete lifecycle operations, progress children, app forms,
  Today behavior, reminders, or Pencil changes.

## Tests

Bind feature criterion C2 to `GoalCreationOperationsTests`.

Cover normalized Accumulate creation with default and custom units; increasing
and decreasing Measure creation; optional deadlines; exact creation timestamp;
empty child relationships; one save; and a returned Goal that survives
container reopening.

Reject whitespace-only name/unit, zero and negative target, Accumulate baseline,
missing Measure baseline, Measure baseline equal to target, malformed deadline,
and a deadline whose full local day ends at or before creation. Cover a deadline
on the creation date, spring-forward and fall-back deadline days, and multiple
time zones with calendar-derived boundaries.

Inject a save failure after insertion. Assert the error propagates, the Goal and
relationships are removed, the context contains no operation-owned pending
change, unrelated pending habits remain, and exactly one save was attempted.

Run:

- `Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalCreationOperationsTests.swift`
- `Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/GoalPersistenceTests.swift`
- `Scripts/tiller-swift-test`
- `swift build`

## Edge cases

- Measure baseline may be negative, zero, above target, or below target; only
  equality with target is invalid.
- Target remains a positive integer for both kinds even when a Measure baseline
  is negative.
- A goal created during its deadline day is valid until that local day ends.
- A goal cannot import Yesterday progress during creation; creation has no
  child payload.
- Kind and created-at cannot be changed through the returned creation fields or
  a convenience mutation API.
- Repeated create calls are distinct owner actions and create distinct
  aggregates.
