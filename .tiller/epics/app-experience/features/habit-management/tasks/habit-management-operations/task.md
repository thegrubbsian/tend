# Implement validated habit management operations

## Approach

Add the one supported CRUD boundary for owner-entered habit configuration to
TendCore. Follow the existing main-actor operation pattern used by
`HabitActivityOperations`, `LogEntryOperations`, and
`HabitStreakComputation`: own a `ModelContext`, inject save behavior internally
for failure tests, validate model ownership before mutation, snapshot values
that may need restoration, save deliberately, and roll back on failure.

Define a public, value-semantic editable-fields type containing name, target,
unit, `PinnedWeekdays`, and optional `ReminderTime`. Normalize name and unit by
trimming leading/trailing whitespace. Return typed errors for empty normalized
name, target below one, empty normalized unit, and detached/deleted/foreign
models. Preserve internal whitespace and arbitrary owner-written units.

`HabitManagementOperations.create(fields:cadence:at:timeZone:)` must:

1. validate and normalize fields before changing the context;
2. normalize pinned weekdays to `.none` for Daily and preserve the supplied
   valid bitset for Weekly;
3. derive the containing period through `CalendarBucketSchedule`;
4. construct an active `Habit`, one open `HabitActivityPeriod` beginning at the
   supplied instant, and one nonexempt `HabitBucket` with the derived key and
   calendar boundaries;
5. establish both sides of all relationships, insert once, and save once; and
6. return the persisted Habit only after success.

A failed create removes or rolls back every inserted object. Do not create an
active Habit without its activity period/current bucket, depend on a later
reconciliation to repair it, or issue multiple saves.

`update(_:fields:at:timeZone:)` has no cadence argument. Validate that the Habit
belongs to the operation context and has a supported persisted cadence. If it is
active, reconcile it at the supplied instant and local time zone before
assigning the new fields; this freezes any newly final bucket against the old
requirement. An inactive habit has no mutable buckets, so skip reconciliation
without reactivating or creating a bucket. Normalize daily pinned days, snapshot
all editable properties, assign them together, and save. If the assignment save
fails, restore the prior fields, roll back, and rethrow; a successful active
reconciliation that finalized elapsed history remains valid even when the later
edit fails.

`delete(_:)` validates ownership, deletes the Habit, and saves. Rely on the
existing cascade relationships for activity periods, buckets, and entries.
Rollback and rethrow a failed delete. Confirmation belongs to the app task, not
this operation.

Keep `Habit` storage permissive for migrations and imports. Do not add property
observers, model validation, convenience setters that bypass the operation,
schema changes, a repository protocol, or a second persistence abstraction.

## Surfaces

- Create
  `Sources/TendCore/Management/HabitManagementOperations.swift`; colocate the
  editable value and operation errors unless a second source file materially
  improves clarity.
- Create
  `Tests/TendCoreTests/Management/HabitManagementOperationsTests.swift`.
- Do not modify `Habit`, `HabitBucket`, `HabitActivityPeriod`, `LogEntry`,
  `TendSchemaV1`, `Package.swift`, the app target, or the Xcode project unless a
  test exposes an actual source defect in an existing owned dependency.

## Tests

Write the operation tests first and prove they fail because the API/behavior is
absent. Use real in-memory `ModelContainer` instances, model contexts, the real
calendar schedule/reconciler, and injected save failures; do not mock SwiftData
or assert source text.

Cover:

- normalized daily creation at a DST-adjacent instant with exactly one active
  period and the exact current daily bucket;
- weekly creation during the middle of a week with Monday/Sunday boundaries;
- default and arbitrary unit preservation, daily pinned-day clearing, weekly
  zero/multiple pinned-day preservation, and reminder preservation;
- rejection of whitespace-only name/unit and zero/negative target before any
  insertion;
- one-save creation plus full rollback on a save error;
- edit of every mutable field without any API or side effect that changes
  cadence;
- a requirement edit after bucket finality, proving the finalized bucket keeps
  old target/unit snapshots while open/grace evaluation uses the new values;
- detached, deleted, foreign-context, unsupported-cadence, and failed-edit
  behavior;
- hard deletion of active and inactive habits, cascading activity periods,
  buckets, and entries; and
- failed deletion leaving the complete graph persisted.

Run:

- `Scripts/tiller-swift-test
  Tests/TendCoreTests/Management/HabitManagementOperationsTests.swift`
- `Scripts/tiller-swift-test`
- `swift build`

## Edge cases

- Trimming must not collapse internal spaces or rewrite case.
- A target of exactly one is valid; `Int.max` is valid if SwiftData can persist
  it.
- Weekly pinned days may be empty even when a reminder exists.
- Daily fields never retain stale weekly pins after create or update.
- Creation at local midnight belongs to the new day/week according to
  `CalendarBucketSchedule`; do not use fixed-duration arithmetic.
- Edit reconciliation happens before target/unit assignment so elapsed history
  cannot be silently re-judged.
- Editing an inactive habit changes configuration without creating buckets or
  reactivating it.
- Deleting an already deleted or foreign Habit is an error, not silent success.
