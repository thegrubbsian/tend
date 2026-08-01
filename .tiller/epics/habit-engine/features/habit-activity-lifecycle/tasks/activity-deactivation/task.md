# Deactivate habits and exempt editable buckets

## Approach

Add a persistence-aware `HabitActivityOperations` service under `TendCore`.
The service is main-actor isolated, owns one caller-supplied `ModelContext`, and
accepts an explicit operation instant and time zone. Give it a production
initializer and the same internal injectable lifecycle-save seam used by the
existing reconciliation and logging operations.

Define a typed `HabitActivityOperationError` for failures owned by this
boundary: detached or deleted habit, already-inactive transition, inconsistent
open activity-period count, invalid activity chronology, duplicate bucket key,
and a bucket phase/key that cannot occur in a valid active timeline. Preserve
the typed errors emitted by `BucketReconciler`, `BucketEvaluator`,
`CalendarBucketSchedule`, SwiftData fetches, and the save closure.

Implement deactivation in this order:

1. Verify the habit belongs to this context by persistent model identity, is
   active, has exactly one open activity period, and has a non-overlapping
   activity timeline whose open period starts no later than the operation
   instant. Refuse before mutation if those invariants fail.
2. Call `BucketReconciler.reconcile` while the habit is still active. This
   commits any missing buckets and finalizes expired grace before exemption.
   Never recreate reconciliation rules in the lifecycle service.
3. Fetch this habit's buckets by persistent relationship identity, reject
   duplicate period keys, and evaluate them under the supplied time zone.
   Existing final and exempt non-current buckets remain untouched. Every valid
   open or grace bucket becomes exempt, including a provisionally met grace
   bucket. Reject an exempt current bucket, a future provisional bucket, or
   another contradictory phase/key rather than repairing it.
4. Set the open activity period's `endedAt` to the exact operation instant and
   set `habit.isActive` false. Do not delete, detach, retimestamp, or rewrite any
   `LogEntry`.
5. Save the lifecycle mutation once. On failure, roll back exemption, period
   closure, the active flag, and inverse changes while retaining any
   reconciliation facts committed in step 2.

Keep persistence, activity-timeline, bucket-fetch, and bucket-classification
helpers private but shaped for reuse by the dependent reactivation task. Do not
add activation logic, model convenience methods, UI behavior, reminder calls,
or streak computation in this task.

## Surfaces

- `Sources/TendCore/Lifecycle/HabitActivityOperations.swift`: new operation
  service, typed errors, deactivation transaction, and shared validation
  helpers.
- `Tests/TendCoreTests/Lifecycle/HabitActivityOperationsTests.swift`: isolated
  SwiftData coverage for deactivation and its failure boundary.
- Existing `Habit`, `HabitActivityPeriod`, `HabitBucket`, `LogEntry`,
  `BucketReconciler`, `BucketEvaluator`, and `CalendarBucketSchedule` APIs are
  consumed as-is. No schema migration is part of this task.

## Tests

Bind feature criteria C1 and the deactivation portions of C4 and C5 to
`HabitActivityOperationsTests.swift`.

- Deactivate daily and weekly habits with exact operation timestamps. Assert
  the sole open activity period closes, `isActive` becomes false, the mutation
  saves once, and subsequent reconciliation while inactive creates nothing.
- Cover current plus grace buckets for both cadences, including met and unmet
  progress. Assert every still-editable bucket is exempt, every entry and
  relationship is retained, and final or previously exempt buckets are
  unchanged across every persisted domain field.
- Exercise exact local midnight, Monday, grace-end, daylight-saving, and time
  zone boundaries with explicit calendars and instants. Confirm reconciliation
  finalizes expired history before the remaining current/grace set is exempted.
- Prove two habits with the same ordinary UUID cannot cross ownership, and
  detached/deleted habits, duplicate transitions, missing or multiple open
  periods, overlapping/backward activity intervals, duplicate bucket keys,
  future provisional buckets, unsupported cadence, invalid requirements, and
  corrupt bucket state fail with the intended typed error and no lifecycle
  mutation save.
- Inject a lifecycle save failure after reconciliation changed persisted
  history. Assert reconciliation remains committed while exemption, period
  closure, active state, entries, and inverse relationships return to their
  pre-transition values.

Run the focused lifecycle test file, the existing bucket and logging regression
tests, the full Swift package suite, `swift build`, and the generic iOS
`xcodebuild` used by prior Habit Engine tasks.

## Edge cases

- Deactivation at the activity period's exact start is valid and closes a
  zero-length active interval; an earlier instant is invalid.
- A met open or grace bucket is still non-final and therefore becomes exempt.
- A bucket whose grace expires exactly at the operation instant finalizes before
  exemption and must remain immutable.
- A weekly deactivation on Monday may exempt both the new current week and the
  previous week's grace bucket. Pinned weekdays never alter this behavior.
- Existing entries may have timestamps outside the bucket after legitimate
  back-fill. Exemption never partitions or filters them by timestamp.
- If reconciliation or post-reconciliation evaluation fails, no lifecycle
  changes are applied. Reconciliation work already committed before a later
  refusal is historical fact and is not undone.
- Repeated deactivation is a typed error, not a no-op and not another activity
  period boundary.
