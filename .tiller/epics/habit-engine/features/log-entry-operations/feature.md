# Log Entry Operations

## Summary

Provide the one on-device mutation surface for recording and correcting habit
contributions. It turns the bucket engine's current and grace states into
authorized SwiftData appends and deletes without weakening finality, inventing
daily sub-buckets for weekly habits, or moving persistence rules into the UI.

## Behavior

### Operation context and bucket selection

- `LogEntryOperations` runs on the main actor over one caller-supplied
  `ModelContext`. Every time-dependent operation receives an explicit `Date`
  and `TimeZone`; production callers may pass the current values, while tests
  never use the wall clock or host time zone.
- Append and set-total operations accept a `LogEntryDestination`: `.current`
  resolves the canonical bucket containing the supplied instant, and
  `.periodKey(String)` explicitly selects a persisted bucket of the same habit.
  The explicit form is the back-fill path. A raw UUID is never aggregate
  identity, and a bucket belonging to another habit cannot be selected.
- The habit must be active. A destination is editable only when it is the
  current open bucket or is presently in grace under the supplied calendar.
  Future, final, exempt, older-than-grace, malformed, missing, and
  cadence-mismatched destinations are rejected with typed errors.
- At an exact period boundary, `.current` selects the new period. At an exact
  grace boundary, the prior bucket is final and no longer editable. Daily grace
  therefore exposes yesterday; weekly grace exposes last week only on Monday.
- After rejecting invalid scalar or root-ownership inputs, every operation that
  reaches bucket authorization reconciles the habit first. It calls the
  dependency's `BucketReconciler` rather than duplicating calendar materializing
  or finalization logic, then re-evaluates the selected bucket before mutation.

### Append

- Appending accepts a positive integer amount. The selected bucket's checked
  progress plus the new amount must be representable as `Int`; zero, negative,
  and overflowing contributions are domain errors and are never persisted.
- A successful append creates exactly one `LogEntry` related to both the habit
  and selected bucket. Its timestamp is the supplied operation instant.
  Membership, not timestamp containment, determines which bucket receives the
  contribution, so a grace back-fill keeps the time it was actually recorded.
- Entries may take progress beyond the target; the target is a completion
  threshold, not a cap. No aggregate or provisional verdict is stored on the
  entry or bucket. `BucketEvaluator` derives the new progress and standing from
  persisted entries.

### Delete and correction

- Deleting accepts the habit and one persisted entry, verifies the entry's
  SwiftData relationship identity to that habit and its bucket, reconciles, and
  authorizes the bucket under the same current-or-grace rule as append.
- A successful delete removes exactly that entry. Deleting the last entry is
  valid, and a deletion may move a provisional bucket from pending-met to
  pending-unmet. Final, exempt, inactive, foreign, detached, or internally
  inconsistent entries are rejected without mutation.
- Entries are append-and-delete only. There is no in-place amount, timestamp,
  habit, or bucket edit. Correcting an amount means deleting the incorrect
  entry and appending a replacement. The later UI's transient Undo action is
  this same delete operation and adds no separate domain state or time limit.

### Set total

- Set total is bucket-scoped entry sugar. It accepts a nonnegative total,
  authorizes the selected bucket exactly as append does, and compares the value
  with that bucket's checked current sum.
- A greater total appends exactly one entry for the positive difference. An
  equal total is a no-op and creates no entry or mutation save. A lower total
  is a typed error; the caller must delete incorrect entries first. A zero
  total is therefore valid only as the equal no-op for an empty bucket.
- Daily habits set the selected day's total. Weekly habits set the selected
  week's total, including the prior week while it is in grace on Monday. Weekly
  logging never creates or infers daily sub-buckets.

### Persistence and failure semantics

- Every requested entry change is completely validated and planned before its
  entry mutation is applied. Each actual append, delete, or positive set-total
  delta is followed by exactly one mutation save.
- On mutation application or save failure, pending entry changes and inverse
  relationships are rolled back and the original error is rethrown. Validation
  failures and equal-total no-ops perform no mutation save.
- Reconciliation is a committed prerequisite with its own atomic save. Catch-up
  buckets or finality it records remain valid even if the requested entry
  mutation is subsequently refused or its save fails; only the entry mutation
  is rolled back. This preserves calendar truth rather than coupling it to an
  invalid logging request.
- Repeated requests are not globally deduplicated: each successful append is a
  real contribution. Set-total is idempotent only when the requested total
  already equals the persisted bucket sum.

## Ownership and scope

- The operation surface and its typed errors live under `TendCore/Logging`.
  SwiftData models remain storage records, `BucketReconciler` remains the sole
  catch-up/finality authority, and `BucketEvaluator` remains the progress and
  phase authority. No repository, generic command bus, cached aggregate, or
  third-party dependency is introduced.
- This feature provides domain operations, not presentation. Quick-add chip
  values, the `times` one-tap shortcut, scope-control labels, transient Undo
  timing, haptics, animations, streak recomputation, activity transitions, and
  habit-detail UI belong to their dependent features.

## Definition of done

Device-free SwiftData tests prove current and grace appends, relationship and
timestamp semantics, editable deletion, exact finality enforcement, daily and
weekly selection, checked amounts and totals, deterministic typed failures,
single-save mutation behavior, rollback, equal-total no-op behavior, and the
fossilized-miss and weekly set-total boundaries without a device, UI, network,
or wall clock.
