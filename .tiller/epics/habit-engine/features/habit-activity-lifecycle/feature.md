# Habit Activity Lifecycle

## Summary

Provide the persistence-aware domain operations that suspend and resume habit
tracking without manufacturing misses, deleting history, or weakening final
bucket immutability. The feature turns `Habit.isActive`,
`HabitActivityPeriod`, and bucket exemption into one coherent transaction
boundary for daily and weekly habits.

The lifecycle is independent of presentation, reminders, and streak rendering.
Every operation runs on the main actor over one caller-supplied SwiftData
`ModelContext`, receives an explicit operation instant and time zone, and uses
persistent model identity rather than the models' ordinary UUID attributes.

## Behavior

### Operation surface and invariants

- Add a `HabitActivityOperations` domain service with explicit `deactivate` and
  `reactivate` operations. Production callers supply a habit, `Date`, and
  `TimeZone`; the service never reads the wall clock.
- A transition accepts only a habit persisted in the service's model context.
  Deactivation requires an active habit with exactly one open activity period.
  Reactivation requires an inactive habit with no open period and a valid closed
  activity history.
- Activity periods are ordered, non-overlapping intervals. Deactivation sets
  the open period's `endedAt` to the exact operation instant. Reactivation
  creates a new open period whose `startedAt` is that exact instant. Touching
  boundaries and a zero-length closed active interval are valid; backward or
  overlapping chronology is not.
- Repeating the transition already in force is a typed refusal rather than a
  silent no-op. Missing, multiple, foreign, detached, contradictory, or
  chronologically invalid persistence state is rejected without guessed
  repair.
- At most one bucket may exist for a habit and calendar period key. The
  lifecycle never uses matching UUID attributes as a substitute for persistent
  relationship ownership.

### Deactivation

1. Validate the persisted habit, active state, and activity-period invariants
   before changing lifecycle state.
2. Reconcile the habit at the operation instant while it is still active. This
   creates any elapsed buckets and finalizes anything whose grace has expired
   against the facts in force before deactivation.
3. Evaluate the reconciled buckets under the supplied time zone. Mark every
   still-editable current or grace bucket exempt, whether its provisional
   standing is met or unmet. Leave final buckets and previously exempt
   non-current history unchanged; an exempt current bucket on an active habit is
   contradictory state and is refused.
4. Close the sole open activity period at the operation instant and set the
   habit inactive. Do not delete or detach any log entry.
5. Persist the exemption, activity-period, and active-flag changes with one
   lifecycle mutation save. A reconciliation save may have happened first. If
   the lifecycle save fails, roll back only the lifecycle mutation; already
   committed reconciliation and finalization facts remain.

While the habit is inactive, reconciliation remains a no-op, logging remains
unauthorized, and no buckets are created. The inactive span is therefore a real
gap in the bucket chain rather than a sequence of misses.

### Reactivation

1. Validate the persisted habit, inactive state, closed activity history,
   operation chronology, and inactive bucket chain before mutation. Every
   existing non-final bucket must already be exempt.
2. Resolve the daily or Monday-through-Sunday weekly period containing the
   operation instant in the supplied time zone.
3. If the latest closed activity period ended inside the resolved current
   period and exactly one exempt, non-final bucket already has that period key,
   restore that same persisted bucket, refresh its calendar boundaries, and
   retain every existing entry. This is same-period restoration; no replacement
   or duplicate bucket is created. A current-key bucket without that matching
   activity boundary is inconsistent and is refused.
4. If no current-key bucket exists, create exactly that one current bucket. Do
   not backfill any day or week crossed while the habit was inactive.
5. Leave every other exempt bucket permanently exempt. In particular, when a
   weekly habit is deactivated and reactivated on Monday, the current week's
   bucket may be restored while the prior week's exempt grace bucket stays
   exempt.
6. Start one new open activity period at the operation instant, set the habit
   active, and persist the complete transition with one mutation save. A save
   failure restores the inactive state, closed activity history, bucket
   exemption or absence, and inverse relationships.

Calendar boundaries are half-open. Reactivating exactly at local midnight or
the start of a Monday selects the new day or week. A time-zone change uses the
period key resolved for the supplied time zone and never renames historical
keys.

### Validation and failure semantics

- Operation-specific typed errors distinguish detached habits, duplicate
  transitions, invalid activity-period state or chronology, duplicate bucket
  keys, and a current bucket that cannot legally be restored.
- Unsupported cadence, invalid requirement, calendar calculation, bucket
  evaluation, reconciliation, fetch, and persistence failures propagate with
  their original typed errors where one exists.
- Validation and calendar/evaluation failures perform no lifecycle mutation
  save. Every successful transition performs exactly one lifecycle mutation
  save.
- Rollback restores both sides of SwiftData relationships. The service never
  leaves an inserted activity period or bucket attached after a failed save.

## Acceptance

The acceptance contract covers deterministic daily and weekly deactivation,
same-period restoration, later-period reactivation without catch-up, exact
activity timestamps, persistent identity, entry preservation, finality,
calendar boundaries, corrupt-state refusal, one-save behavior, and rollback.
Bindings use isolated in-memory SwiftData containers, explicit instants and
time zones, and the real bucket reconciler, evaluator, and schedule.

## Out of scope

- Habit creation, ordinary field editing, cadence changes, permanent deletion,
  and UI confirmation belong to Habit Management.
- Reminder cancellation or rescheduling belongs to Local Reminders.
- Current streak, best streak, frozen-streak, and at-risk computation belong to
  Streak Computation.
- Roster, Today, Habit Detail, animation, copy, and haptics belong to the app
  experience features.
- This feature does not change the persistence schema, edit or delete log
  entries, infer anti-cheating policy, or restore any non-current exempt bucket.

## Definition of done

Every acceptance criterion is green in device-free SwiftData tests, the full
TendCore suite and generic iOS build pass, and downstream streak and habit
management code can perform lifecycle transitions without duplicating calendar,
exemption, persistence, or rollback rules.
