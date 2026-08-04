# Project Current Bucket Facts

## Approach

Add a focused TendCore read boundary for the facts Today needs instead of
reimplementing bucket or streak semantics in the app target.

Create main-actor `HabitTodayComputation` with a public
`snapshot(for:at:timeZone:)` method and an immutable, equatable, sendable
`HabitTodaySnapshot`. The snapshot contains cadence, current period key,
aggregate progress, target, unit, current streak, at-risk state, and
provisional-met state.

Validate that the habit is persisted in the computation’s `ModelContext`,
belongs to that context, is not deleted, and is active. Run the existing
`HabitStreakComputation` once so reconciliation, finalization, best-streak
updates, grace handling, and save rollback retain their established behavior.
Derive the current period with `CalendarBucketSchedule`, fetch the bucket for
that exact habit relationship and period key, require exactly one match, and
evaluate it once with `BucketEvaluator`.

Map the current evaluation only when it is the open current period and has a
real aggregate. Treat impossible or malformed states as typed errors; never
substitute zero, select the nearest bucket, or assemble partial facts after a
failure. Keep SwiftData fetches relationship-scoped so duplicate UUIDs in other
aggregate graphs remain irrelevant.

Do not change any SwiftData model, migration, bucket lifecycle, entry operation,
streak calculator, or existing public operation contract.

## Surfaces

- Create
  `Sources/TendCore/Today/HabitTodayComputation.swift` for the snapshot, typed
  projection errors, public initializer, production implementation, and narrow
  internal dependency seam used by tests.
- Create
  `Tests/TendCoreTests/Today/HabitTodayComputationTests.swift` for the complete
  contract.
- Reuse `CalendarBucketSchedule`, `BucketEvaluator`,
  `HabitStreakComputation`, and relationship-qualified SwiftData fetches.
- Do not edit app-target Today views or presentation code in this task.

## Tests

Run:

```bash
Scripts/tiller-swift-test Tests/TendCoreTests/Today/HabitTodayComputationTests.swift
Scripts/tiller-swift-test
swift build
```

The focused suite must prove:

- daily selection uses the owner-local day containing the sampled instant;
- weekly selection uses the containing Monday-through-Sunday bucket on every
  weekday, independent of pinned reminder days;
- repeated entries aggregate exactly, including zero and over-target progress;
- pending-met and pending-unmet map truthfully;
- current streak and grace-derived risk come from the same reconciliation;
- the missing current bucket is created through normal reconciliation;
- inactive, detached, deleted, foreign-context, invalid requirement, invalid
  cadence, missing current, duplicate current, malformed relationship, and
  evaluation failures are not softened;
- reconciliation and best-streak save failures preserve rollback behavior;
- local midnight, Monday rollover, DST spring-forward, DST fall-back, and a
  time-zone change select the correct stable key;
- one habit’s duplicate ordinary UUID in another aggregate cannot affect the
  fetch.

Tests build valid graphs through public TendCore operations. Use direct model
mutation only where the case itself is imported malformed data or an injected
save failure.

## Edge cases

- An active habit whose activity interval begins after the sampled instant is an
  error, not a future zero-progress row.
- The current aggregate may exceed its target and remains unbounded in the
  snapshot.
- A Monday weekly snapshot may simultaneously have an open current week and an
  editable prior grace week; progress comes from the current week while risk
  comes from the streak computation.
- Calendar keys, not fixed seconds or ISO date slicing, choose the current
  period.
- One snapshot uses one instant and one time zone end to end.
