---
node: F-6a3jmx
criteria:
  - id: C1
    statement: Daily and Monday-Sunday weekly periods produce canonical keys, local half-open boundaries, and one-calendar-day grace across DST, year, and time-zone boundaries from explicit inputs
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Buckets/CalendarBucketScheduleTests.swift" }
    required: true
  - id: C2
    statement: Bucket evaluation reports checked progress and exact open, grace, provisional, exempt, and final standing while finalization freezes an immutable target, unit, verdict, and grace-boundary timestamp
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Buckets/BucketEvaluatorTests.swift" }
    required: true
  - id: C3
    statement: Reconciliation materializes every due bucket in the current active interval, refreshes only non-final boundaries, finalizes elapsed grace buckets atomically, remains idempotent, and rejects duplicates or invalid persisted state without partial saves
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Buckets/BucketReconcilerTests.swift" }
    required: true
  - id: C4
    statement: The grace save, fossilized miss, multi-count reset, weekly slip, and target raise examples produce the normative bucket states and frozen requirements without invoking UI or wall-clock time
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Buckets/BucketEvaluationExampleTests.swift" }
    required: true
---

# Acceptance

The contract covers calendar identity and boundary arithmetic, evaluation of
persisted entry facts, finality, requirement snapshots, and persistence-aware
catch-up for the current active interval. Log append/delete authorization,
deactivation and same-period restoration, streak chains, at-risk display,
reminders, and UI remain with the dependent features that can satisfy those
behaviors. The seasonal-gap worked example is therefore not claimed here; the
Habit Activity Lifecycle and Streak Computation contracts must carry it.
