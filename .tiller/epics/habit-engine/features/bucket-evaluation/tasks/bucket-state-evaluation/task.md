# Evaluate bucket state and finality

Build the pure rules layer that turns one persisted bucket and its entries into
checked progress, lifecycle phase, and provisional or settled standing.

## Approach

- Add explicit value types for `BucketPhase`, `BucketStanding`,
  `BucketEvaluation`, and bucket-domain errors. Keep them independent of
  SwiftData contexts and UI presentation.
- Evaluate an open or grace bucket against the habit's current target and unit;
  evaluate a settled bucket only from its frozen snapshot and verdict.
- Sum entry amounts with overflow detection and reject nonpositive amounts,
  nonpositive targets, unknown raw values, partial finality facts, and
  contradictory exempt/final state.
- Derive open, grace, and due-for-finalization boundaries from
  `CalendarBucketSchedule` and an explicit instant. Equality at the bucket end
  enters grace; equality at grace end enters finality.
- Produce the complete facts a reconciler must persist when grace expires:
  target snapshot, unit snapshot, verdict, and the exact grace boundary as the
  finalization timestamp. Do not mutate a model or save a context in this task.
- Leave add/delete authorization, lifecycle transitions, streak calculation,
  reminders, and display formatting to their dependent features.

## Surfaces

- `Sources/TendCore/Buckets/BucketEvaluator.swift`
- `Tests/TendCoreTests/Buckets/BucketEvaluatorTests.swift`

## Tests

- Bind acceptance criterion C2 to `BucketEvaluatorTests.swift`.
- Cover exact open-to-grace and grace-to-final boundary instants for daily and
  weekly buckets.
- Cover sums below, equal to, and above the target; multiple entries; current
  requirement changes for open and grace buckets; and frozen final snapshots.
- Verify exempt standing and all-or-nothing finality facts.
- Prove deterministic errors for invalid cadence/verdict values, nonpositive
  requirements and entries, overflow, malformed keys, and contradictory
  persisted state.

## Edge cases

- An elapsed bucket with no final facts is a valid finalization candidate; a
  bucket with only some final facts is corrupt.
- A fully settled bucket is returned unchanged even when the habit's current
  target, unit, entries, instant, or time zone later differ.
- Empty entries sum to zero without allocating an intermediate collection.
- Exempt buckets never produce a finalization candidate.
