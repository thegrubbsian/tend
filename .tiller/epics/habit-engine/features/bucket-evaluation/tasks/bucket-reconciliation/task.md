# Reconcile persisted buckets deterministically

Add the persistence-aware orchestration that materializes every bucket due in
the current active interval and settles elapsed grace periods exactly once.

## Approach

- Add a `BucketReconciler` over `ModelContext`,
  `CalendarBucketSchedule`, and `BucketEvaluator`. Its public operation accepts
  one habit, explicit instant, and explicit time zone.
- Require exactly one open activity period for an active habit. Enumerate every
  calendar period from that activity start through the supplied instant; an
  inactive habit creates nothing.
- Fetch the habit's existing buckets once, index them by canonical key in
  memory, and reject duplicates before mutation. Do not add a uniqueness
  constraint or repository abstraction.
- Plan and validate the complete reconciliation before applying changes:
  create missing buckets, refresh boundaries only for non-final records, skip
  exempt records, and finalize every non-exempt elapsed grace bucket using the
  evaluator's frozen facts.
- Save the context once. On apply or save failure, roll back pending changes
  and rethrow; never substitute an in-memory store or leave a partially applied
  reconciliation.
- Preserve final buckets byte-for-byte at the model-property level. Repeated
  reconciliation with identical inputs must create no records and change no
  facts.
- Document the call-order invariant for later mutation features: reconcile
  before changing target or unit, adding or deleting entries, or changing
  activity state. Do not implement those mutations here.

## Surfaces

- `Sources/TendCore/Buckets/BucketReconciler.swift`
- `Tests/TendCoreTests/Buckets/BucketReconcilerTests.swift`
- `Tests/TendCoreTests/Buckets/BucketEvaluationExampleTests.swift`

## Tests

- Bind acceptance criterion C3 to `BucketReconcilerTests.swift` and C4 to
  `BucketEvaluationExampleTests.swift`.
- Use isolated in-memory SwiftData containers and explicit activity periods,
  instants, and time zones.
- Cover daily and weekly catch-up after multiple elapsed periods, creation
  mid-period, inactive no-op behavior, idempotent re-entry, non-final time-zone
  boundary refresh, immutable final records, and exact snapshot/finalization
  facts.
- Verify duplicate keys, missing or multiple open activity periods, invalid
  persisted values, and save failures do not partially persist changes.
- Translate the grace save, fossilized miss, multi-count reset, weekly slip,
  and target raise examples into literal device-free fixtures.

## Edge cases

- Reconciliation at an exact period or grace boundary uses the new phase.
- A long absence creates and settles every due bucket in the current active
  interval; not launching the app cannot erase misses.
- Existing exempt buckets remain exempt and are not restored. Historical
  activity intervals and same-period restoration belong to Habit Activity
  Lifecycle.
- If a time-zone change makes the supplied instant belong to a different
  canonical key, materialize that interval normally while retaining every
  existing key; never rename or merge history.
