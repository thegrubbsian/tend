# Reconcile streak state and persist finalized bests

## Approach

Build the main-actor SwiftData operation around the calculator established by
habit-engine/streak-computation/streak-chain-calculation (T-dqajj8). Start with
failing integration tests in an isolated in-memory `TendModelContainer`, using
explicit instants and time zones, then add
`HabitStreakComputation.compute(habit:at:timeZone:)`.

The service owns one caller-supplied `ModelContext`, a `BucketReconciler`, a
`BucketEvaluator`, and an injectable save closure used only by tests. Its public
initializer captures `context.save`; an internal initializer captures the same
context with a caller-supplied save closure.

Implement the operation in this order:

1. Reject a deleted, detached, or foreign-context habit by persistent model
   identity before lifecycle or streak mutation.
2. Decode the habit's cadence, require a positive current target, and require a
   nonnegative stored best before reconciliation. Use the existing
   `BucketEvaluationError` cases for cadence and target; use
   `HabitStreakComputationError.invalidBestStreak` for best.
3. If the habit is active, reconcile it at the supplied instant and time zone.
   If inactive, do not reconcile.
4. Fetch every related `HabitBucket` by the habit's `persistentModelID`. Detect
   duplicate period keys before calculation.
5. Sort deterministically by `startAt`, then `endAt`, then `periodKey`. Evaluate
   every bucket with `BucketEvaluator` and map its key, phase, and standing into
   the calculator input without duplicating verdict arithmetic.
6. Invoke `StreakCalculator` with the decoded cadence and stored best. If the
   derived finalized candidate does not exceed `Habit.bestStreak`, return the
   result without a streak-owned save.
7. On a strict finalized increase, assign `Habit.bestStreak`, save once, and
   return the state. If that save throws, call `context.rollback()` and rethrow
   the original error. Reconciliation already saved before this point remains
   committed.

Propagate `BucketReconciliationError`, `BucketEvaluationError`, the calendar
errors they wrap, SwiftData fetch failures, and persistence failures. Emit the
already-defined `HabitStreakComputationError.detachedHabit` and
`.duplicatePeriodKey` cases for operation-owned validation; reuse its
calculator-owned invalid-state cases unchanged.

## Surfaces

- Create `Sources/TendCore/Streaks/HabitStreakComputation.swift` for the
  persistence-aware service, identity checks, deterministic fetch/order,
  dependency calls, best-streak save, and rollback.
- Create `Tests/TendCoreTests/Streaks/HabitStreakComputationTests.swift` for
  SwiftData integration and feature worked examples.
- Consume `HabitStreakState`, `StreakCalculator`, and
  `HabitStreakComputationError` from
  habit-engine/streak-computation/streak-chain-calculation (T-dqajj8).
- Reuse `BucketReconciler`, `BucketEvaluator`, `CalendarBucketSchedule`, and the
  existing persistence models without changing their ownership.

No schema migration, model field, reconciler hook, lifecycle callback, logging
callback, UI model, reminder API, timer, or dependency is part of this task.

## Tests

Use real SwiftData relationships and refetch persisted models where persistence
is the contract. Name each test for the domain rule or failure it defends.

- Cover daily and weekly chains containing final met, final missed, open
  pending-met, grace pending-met, grace pending-unmet, and exempt buckets.
- Reproduce the normative grace save, fossilized miss, multi-count reset, weekly
  slip, and seasonal gap examples from `design/02-domain-model.md`.
- For the approved risk interpretation, prove twelve final met days, an unmet
  grace Tuesday, and a met open Wednesday return thirteen days at risk.
- Prove inactive computation performs no reconciliation or save, skips exempt
  non-final buckets and absent inactive periods, returns the frozen settled
  chain, and clears risk.
- Reactivate the seasonal habit through `HabitActivityOperations`, log into its
  new current bucket through `LogEntryOperations`, and prove current becomes
  forty-one while best remains forty until that bucket finalizes.
- Prove pending-met open and grace buckets never increase persisted best;
  reconciliation of a new final record increases it once; smaller historical
  results never lower it; and a no-change computation performs no streak-owned
  save.
- Exercise exact local midnight, Monday weekly rollover, spring-forward,
  fall-back, and time-zone-key changes without fixed-duration date arithmetic.
- Prove persistent identity isolates two habits sharing the same ordinary UUID,
  and duplicate keys, detached habits, unsupported cadence, nonpositive target,
  invalid best values, impossible evaluation state, and dependency errors
  produce precise failures without reconciliation or best-streak mutation when
  operation-owned validation can reject first.
- Inject a best save failure after a finalized increase. Assert the original
  error escapes, the in-memory and refetched best remain unchanged, and any
  reconciliation facts saved earlier remain intact.

Run
`Scripts/tiller-swift-test Tests/TendCoreTests/Streaks/HabitStreakComputationTests.swift`,
then the calculator tests, bucket reconciler tests, lifecycle tests, logging
tests, the complete `Scripts/tiller-swift-test` suite, `swift build`, and the
generic iOS `xcodebuild` used by the preceding Habit Engine features. Finish
with a task-sized commit containing only the integration service and its tests.

## Edge cases

- The caller's time zone governs only current evaluation and reconciliation;
  never rename historical keys or assume their stored dates were created in the
  same zone.
- Stored start timestamps define chronology across time-zone changes. End
  timestamps and keys make ties deterministic; duplicate keys remain invalid.
- An active operation may legitimately cause one reconciliation save followed
  by one streak-best save. Do not merge those ownership boundaries or claim the
  read operation is globally side-effect free.
- An inactive habit with no buckets has current zero and its nonnegative stored
  best. A real frozen streak is derived from the final buckets retained across
  the inactive gap.
- A due-for-finalization evaluation after active reconciliation is inconsistent
  state. Refuse it instead of updating best from unsaved finality.
- Do not infer missing historical buckets, repair activity periods, or
  manufacture inactive-gap records. Those invariants belong to reconciliation
  and lifecycle operations.
