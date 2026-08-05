# Project Editable Logging Scopes

## Approach

Add a focused TendCore read boundary beside `LogEntryOperations` for the exact
editable state a logging surface needs. Implement a main-actor
`HabitLoggingComputation` with one public
`snapshot(for:at:timeZone:)` operation. It reconciles the supplied persisted
active habit once, evaluates the cadence period containing the supplied instant,
and returns:

- copied habit identity, name, cadence, target, and unit facts;
- one current-open `HabitLoggingBucketSnapshot`;
- one optional immediately preceding `grace` snapshot;
- copied period key, phase, progress, target, unit, and met state per bucket;
- newest-first `HabitLoggingEntrySnapshot` values carrying the live persisted
  entry, its `PersistentIdentifier`, UUID, timestamp, and amount.

The live entry reference is present only so the app can pass the exact validated
model back to `LogEntryOperations.delete`; presentation uses the copied fields.
Do not expose mutable arrays as the snapshot contract or let the app rediscover
entries by UUID, timestamp, amount, or index.

Reuse `BucketReconciler`, `BucketEvaluator`, and `CalendarBucketSchedule`.
Select the current daily or Monday-through-Sunday key from the schedule. Derive
the preceding period through calendar APIs and include it only when exactly one
related bucket evaluates to `grace`. Validate that every selected bucket and
entry is persisted, belongs to the supplied habit, and agrees across both
relationship directions before publishing anything.
Where this validation is identical to the private relationship walk already in
`HabitTodayComputation`, extract one internal TendCore validator and make both
computations consume it. Do not ship a second graph-validity convention.

Define a small typed `HabitLoggingComputationError` for inactive/detached habit,
missing or duplicate selected bucket, missing/foreign/detached relationships,
and unexpected current/grace phases. Preserve existing calendar, evaluation,
reconciliation, overflow, and save errors rather than flattening them to empty
state. Construct the full replacement before returning it.

## Surfaces

- Create `Sources/TendCore/Logging/HabitLoggingComputation.swift` for public
  snapshot values, typed relationship/selection failures, and the computation.
- Create
  `Tests/TendCoreTests/Logging/HabitLoggingComputationTests.swift`.
- Preserve the public API and mutation semantics of
  `Sources/TendCore/Logging/LogEntryOperations.swift`.
- Modify `Sources/TendCore/Today/HabitTodayComputation.swift` and its focused
  tests only if extracting the shared internal relationship validator is needed;
  its public snapshot behavior must remain byte-for-byte equivalent.
- Do not edit app views, Today presentation, persistence schema, bucket schedule,
  evaluator, reconciler semantics, streak computation, or lifecycle operations.

## Tests

Run:

```bash
Scripts/tiller-swift-test Tests/TendCoreTests/Logging/HabitLoggingComputationTests.swift
Scripts/tiller-swift-test Tests/TendCoreTests/Logging/LogEntryOperationsTests.swift
Scripts/tiller-swift-test
swift build
```

The focused suite must prove:

- daily and weekly current period selection uses the owner-local calendar and
  weekly rows remain available on unpinned weekdays;
- exactly one preceding bucket appears during grace and disappears at grace end;
- weekly grace is available on Monday through evaluated periods, not a weekday
  branch;
- current and grace progress, target, unit, met state, and period key are exact;
- entries are copied newest first with stable persistent identity and a
  deterministic tie-break, including duplicate ordinary UUIDs and timestamps;
- empty entry relationships produce zero progress and an empty list;
- over-target progress remains truthful and integer overflow fails;
- inactive, detached, deleted, missing, duplicate, foreign, null, and
  bidirectionally malformed habit/bucket/entry graphs fail without a partial
  snapshot;
- reconciliation creates missing current periods, finalizes expired work, saves
  once, and preserves rollback/failure behavior;
- local midnight, Monday rollover, spring-forward, fall-back, and a time-zone
  change select the same periods as `CalendarBucketSchedule`.

## Edge cases

- A previous final, exempt, due-for-finalization, open-future, or absent bucket is
  never advertised as grace.
- A met grace bucket remains editable and is included; the app decides whether
  to draw the unfinished marker from progress versus target.
- Bucket entries may be `nil`; selected entries may not have missing or foreign
  inverse links.
- Stable ordering cannot depend on SwiftData relationship array order.
- No snapshot value caches progress back into a model or changes target/unit
  semantics for open and grace buckets.
