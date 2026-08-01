# Reactivate habits and restore the current bucket

## Approach

Extend `HabitActivityOperations` with the reactivation transaction, reusing the
persistence, timeline, calendar, bucket-identity, save, and rollback conventions
established by `activity-deactivation`.

Validate that the habit is persisted in this context, currently inactive, has
no open activity period, has at least one valid closed activity period, and that
the requested instant is not earlier than the latest closed boundary. Require
every existing non-final bucket on the inactive habit to be exempt. Resolve the
daily or Monday-through-Sunday weekly period containing the instant with
`CalendarBucketSchedule`.
Resolve the latest closed activity period's end under the same schedule. An
existing current-key bucket is eligible for restoration only when that boundary
falls inside the resolved current period; otherwise the state is inconsistent.


Fetch buckets by persistent habit relationship and index them by period key. For
the resolved current key:

- If no bucket exists, create exactly one unsnapshotted, non-final,
  non-exempt `HabitBucket` with the resolved boundaries and attach it to the
  habit.
- If one bucket exists, require the latest closed boundary to share its current
  period and require the bucket to be exempt, non-final, cadence-compatible, and
  evaluable as the current calendar period. Clear only `isExempt`, refresh its
  start and end boundaries, and retain its persistent identity and every
  existing entry.
- If multiple buckets exist, or the current bucket is final, non-exempt,
  mismatched, or otherwise inconsistent, throw a typed error without mutation.

Never modify any non-current bucket. This leaves a grace bucket exempted during
deactivation permanently exempt, including the previous week on Monday. Never
iterate calendar periods across the inactive gap and never call reconciliation
in a way that creates catch-up buckets.

Create one new `HabitActivityPeriod` starting at the exact operation instant,
attach it to the habit, and set `isActive` true. Persist the active flag,
activity period, and bucket creation or restoration with exactly one mutation
save. On failure, explicitly detach inserted models where SwiftData inverse
relationships require it, roll back the context, and restore the prior inactive
state and bucket exemption.

Do not compute streak values here. The durable activity intervals and exempt
bucket chain are the downstream input to Streak Computation.

## Surfaces

- `Sources/TendCore/Lifecycle/HabitActivityOperations.swift`: add reactivation,
  same-period restoration/current-bucket creation, and rollback completion.
- `Tests/TendCoreTests/Lifecycle/HabitActivityOperationsTests.swift`: extend the
  lifecycle suite with same-period, inactive-gap, daily/weekly, validation, and
  failure coverage.
- The existing persistence schema, bucket evaluator, calendar schedule,
  reconciler, and logging APIs remain the source of truth and are not duplicated
  or replaced.

## Tests

Bind feature criteria C2 and C3 and complete the reactivation portions of C4 and
C5 in `HabitActivityOperationsTests.swift`.

- Reactivate a daily habit later in the same day and a weekly habit later in the
  same week. Assert a new open activity period begins at the exact instant, the
  exact exempt current bucket is restored, existing entries count again, its
  boundaries refresh, no duplicate key appears, and one mutation save occurs.
- Deactivate and reactivate a weekly habit on Monday with both last week's grace
  and this week's current bucket exempt. Assert only this week's current bucket
  is restored and prior grace remains permanently exempt.
- Reactivate in a later day or week after a long inactive span. Assert only the
  containing current bucket is created, no gap buckets appear, and final and
  older exempt history is unchanged.
- Cover repeated deactivate/reactivate cycles, same-instant touching activity
  boundaries, exact local midnight and Monday transitions, daylight-saving
  changes, and a device time-zone key change. Assert periods remain ordered and
  non-overlapping and bucket keys remain unique.
- Refuse already-active and detached/deleted habits, inactive habits with an
  open or missing closed activity period, backward/overlapping chronology, any
  non-final non-exempt bucket in the inactive chain, duplicate current keys, a
  current key unrelated to the latest closed activity boundary, and final,
  cadence-mismatched, malformed, invalid-progress, or otherwise unrestorable
  current buckets. Assert the precise typed dependent or lifecycle error and
  zero mutation saves.
- Inject save failures for both current-bucket restoration and new-bucket
  creation. Assert the habit remains inactive, no open period remains, restored
  exemption returns, inserted bucket/activity relationships are removed, all
  entries remain attached, and the context has no pending changes.

Run the focused lifecycle test file, bucket/logging regressions, full package
suite, `swift build`, and the generic iOS build.

## Edge cases

- Reactivation at exactly the last `endedAt` is valid and creates touching,
  non-overlapping activity periods; an earlier instant is rejected.
- The period key is resolved from the supplied time zone. A new key after a
  device time-zone change is added without renaming or restoring a historical
  key from the old zone.
- An exempt current bucket can contain zero, one, or many entries and can
  already meet the requirement. Restoration preserves all of them.
- A current-key bucket carrying finalization snapshots or a final verdict is
  immutable even if its exemption flag is corrupt; refuse it rather than
  clearing facts.
- An inactive habit has no legal open activity period. A habit with no prior
  closed activity period is not a reactivation candidate and is rejected rather
  than treated as creation.
- Pinned weekdays never change weekly bucket selection, restoration, or gap
  creation.
