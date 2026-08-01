# Calendar Bucket Evaluation

## Summary

Build the deterministic bucket engine that turns a habit, its persisted
activity interval, its log entries, an explicit instant, and the device's local
time zone into honest daily or weekly bucket state. The engine owns calendar
period identity, open/grace/final evaluation, requirement snapshots, and
catch-up after the app has not run. It does not own log mutation, habit
activation transitions, streaks, reminders, or UI.

## Behavior

### Calendar periods

- All time-dependent APIs receive an explicit `Date` and `TimeZone`; production
  callers may supply the current values, while tests never depend on the wall
  clock or host time zone.
- Period arithmetic uses a Gregorian calendar in the supplied local time zone.
  A daily period is one local calendar day. A weekly period is Monday through
  Sunday, independent of locale defaults or pinned reminder days.
- Daily keys are `day:YYYY-MM-DD`. Weekly keys are `week:YYYY-MM-DD`, where the
  date is the period's Monday. Keys use fixed-width POSIX Gregorian components
  and contain no time-zone identifier.
- Period boundaries are start-inclusive and end-exclusive. A bucket is open
  before its end, in grace from its end until one local calendar day after its
  end, and final at or after that grace boundary.
- Calendar addition, not fixed-hour arithmetic, determines every boundary. A
  spring-forward day may be 23 hours, a fall-back day may be 25 hours, and the
  one-day grace interval follows the same rule.
- A bucket's persisted key never changes. When the local time zone changes, the
  engine recalculates the boundaries of non-final buckets from their keys
  without replacing those records. If the new local date is a different key,
  it is a different calendar interval and may be materialized normally. Final
  bucket keys and boundaries are immutable.

### Evaluation and finality

- Entry progress is the checked sum of the bucket's persisted entry amounts.
  A nonpositive amount, nonpositive requirement, unknown cadence or verdict,
  malformed period key, or integer overflow is a domain error rather than a
  guessed result.
- Open and grace buckets use the habit's current target and unit. Their standing
  is `pending-met` when the sum meets or exceeds the target and
  `pending-unmet` otherwise. Both remain provisional and editable by the later
  Log Entry Operations feature.
- When grace expires, the engine settles the bucket exactly once. It records
  the grace boundary as `finalizedAt`, freezes the current target and unit into
  the bucket, and stores `met` or `missed` from the entry sum. A later
  reconciliation never recomputes or rewrites those facts.
- A final bucket is evaluated only from its frozen target, unit, and verdict.
  Missing or contradictory final facts are reported as invalid persisted state;
  the engine does not repair history silently.
- An exempt bucket reports exempt standing and is never finalized or restored
  by this feature. Habit Activity Lifecycle owns exemption and restoration.
- Requirement-editing callers must reconcile the habit before changing its
  target or unit. This guarantees that every bucket whose grace already expired
  freezes the requirement that was in force at its finality boundary.

### Reconciliation

- Reconciliation operates on one habit in one `ModelContext` using one explicit
  instant and time zone. It validates the complete change before one context
  save; construction, validation, calendar, and save errors are thrown with no
  partial fallback.
- An active habit must have exactly one open activity period. The engine
  materializes every missing calendar bucket from that activity period's start
  through the supplied instant, so leaving the app closed cannot erase missed
  days or weeks. An inactive habit produces no new buckets.
- Existing buckets are matched by habit and canonical period key. Repeated
  reconciliation with the same inputs is idempotent. Duplicate records for one
  habit and key are an invariant error, never merged or selected arbitrarily.
- Reconciliation refreshes non-final boundaries, creates the current and
  elapsed buckets that are due, and finalizes every non-exempt bucket whose
  grace has expired. It does not create buckets before the current activity
  period, mutate activity periods, add or delete log entries, or compute
  streaks.

## Ownership and surfaces

- Pure calendar and evaluation values live under `TendCore/Buckets` and have no
  SwiftData context dependency.
- The reconciler is the sole persistence-aware surface in this feature. Later
  logging, lifecycle, habit-editing, streak, reminder, and UI features call it
  rather than duplicating bucket arithmetic.
- The feature adds no third-party dependency, background scheduler, timer,
  notification behavior, or generic repository.

## Definition of done

Device-free tests prove daily and weekly identity, Monday week boundaries, DST
and time-zone behavior, exact grace transitions, provisional and final
verdicts, immutable snapshots, deterministic catch-up, idempotency, duplicate
rejection, and the applicable normative examples from the domain model.
