# Streak Computation

## Summary

Provide one deterministic source of truth for a habit's current streak,
finalized best streak, cadence unit, and at-risk state. The feature turns the
persisted bucket and activity history produced by Bucket Evaluation and Habit
Activity Lifecycle into a value that app-experience features can render without
reimplementing chain arithmetic, reading the wall clock, or inferring inactive
periods.

The approved design separates pure chain calculation from a thin
persistence-aware operation. The calculator owns only ordered bucket-state
arithmetic. The operation owns SwiftData identity, reconciliation, evaluation,
and monotonic persistence of `Habit.bestStreak`.

## Behavior

### Operation surface and result

- Add a public `HabitStreakState` value with `currentStreak`, `bestStreak`,
  `isAtRisk`, and the habit's immutable `HabitCadence`. The value is
  `Equatable` and `Sendable`; presentation code owns pluralization and copy such
  as "12 days" or "9 weeks."
- Add a main-actor `HabitStreakComputation` service initialized with one
  caller-supplied `ModelContext`. Its public operation accepts a `Habit`, an
  explicit `Date`, and an explicit `TimeZone`; it never reads the wall clock or
  creates another persistence container.
- The operation accepts only a non-deleted habit persisted in that exact
  context. It fetches buckets by the habit's persistent model identity, never
  by the ordinary `Habit.id` UUID, so two habits with equal UUID attributes
  cannot share a streak.
- Active habits reconcile through `BucketReconciler` before calculation so all
  elapsed grace buckets are final, catch-up is complete for the current active
  interval, and the bucket containing the operation instant exists. Inactive
  habits do not reconcile or manufacture buckets.
- Every bucket is evaluated through `BucketEvaluator` at the supplied instant
  and time zone. The calculator receives those evaluations in deterministic
  chronological order; stored bucket start, end, and key provide stable
  tie-breaking without renaming historical time-zone keys.

### Current chain

- Scan the ordered evaluations from oldest to newest. A final met bucket or a
  provisionally met open or grace bucket contributes one link. A final missed
  bucket resets the accumulated current chain to zero.
- A pending-unmet open or grace bucket contributes no link but does not break
  the chain while it remains editable. This preserves the optimistic display
  without awarding credit that has not been earned.
- Exempt buckets contribute no link and do not break the chain. Periods with no
  buckets because the habit was inactive are absent from the input and likewise
  contribute neither a success nor a miss.
- The result is at risk only when a pending-unmet grace bucket remains in the
  surviving segment after the latest final miss and the displayed current
  streak is greater than zero. A pending-unmet open bucket alone is not at risk.
- Concretely, twelve final met daily buckets through Monday, an unmet Tuesday
  bucket in grace, and a pending-met Wednesday bucket produce a current streak
  of thirteen days with `isAtRisk == true`. Tuesday is a savable link but does
  not yet add to the count.
- A bucket still reported as due for finalization after the required
  reconciliation, or a phase and standing combination that cannot be produced
  by `BucketEvaluator`, is rejected as invalid state rather than silently
  treated as settled.

### Finalized best streak

- `Habit.bestStreak` is a durable high-water mark established only by finalized
  met evidence. This records the approved interpretation that provisional
  completion changes the current streak immediately but cannot establish a
  permanent best.
- Independently scan finalized bucket standings in chronological order. Final
  met increments the finalized run, final missed resets it, and exempt or
  provisional buckets do not change it. The greatest finalized run is the
  derived best candidate.
- Return the greater of the persisted `Habit.bestStreak` and the derived
  finalized candidate. Persist only when the candidate strictly exceeds the
  stored value, and never lower an existing best. A negative stored best is
  invalid persisted state.
- If no best increase is required, calculation performs no streak-owned save.
  If an increase is required, update the habit and save once. A failed save
  rolls back the best-streak mutation and rethrows the original error.
  Reconciliation facts committed before a later best-streak failure remain
  committed, matching the transaction boundary used by lifecycle operations.

### Lifecycle, calendar, and failure behavior

- Deactivation's exempt current and grace buckets disappear from both streak
  counts without erasing older final facts. While inactive, the current streak
  is the last chain supported by settled history and the at-risk flag is false.
- Reactivation resumes from that chain across the absent inactive gap. In the
  seasonal-gap example, a finalized forty-day chain remains forty while
  inactive; a provisionally met reactivation bucket displays forty-one while
  the persisted best remains forty, and finalizing that bucket permits the best
  to become forty-one.
- Daily midnight, weekly Monday, spring-forward, fall-back, and caller-supplied
  time-zone changes are resolved by the existing calendar, reconciliation, and
  evaluation components. Streak code does not assume fixed-duration days or
  weeks and does not reinterpret historical period keys.
- Duplicate period keys, detached habits, unsupported cadence, nonpositive
  current requirements, invalid persisted best values, impossible evaluation
  states, reconciliation failures, calendar failures, evaluation failures,
  fetch failures, and save failures are surfaced deterministically. Validate
  operation-owned invariants before reconciliation can save; validation never
  repairs history speculatively.

### Ownership and scope

- `StreakCalculator` owns pure chain arithmetic and is independently testable
  without a `ModelContext`.
- `HabitStreakComputation` owns persistence-aware orchestration and is the
  public downstream entry point.
- Bucket creation and finalization remain in `BucketReconciler`; bucket standing
  remains in `BucketEvaluator`; activity transitions remain in
  `HabitActivityOperations`; log mutation remains in `LogEntryOperations`.
- Roster, Today, Habit Detail, localized unit copy, visual at-risk treatment,
  reminders, and haptics remain with their dependent app-experience and
  device-readiness features.
- This feature adds no schema migration, cached current-streak field,
  background job, timer, notification behavior, generic repository, or
  third-party dependency.

## Definition of done

Every acceptance criterion is green in deterministic device-free tests. The
full TendCore suite and generic iOS build pass, and downstream habit-management
code can obtain truthful current, finalized-best, and at-risk state without
duplicating persistence identity, reconciliation, bucket evaluation, inactive
gap, or chain rules.
