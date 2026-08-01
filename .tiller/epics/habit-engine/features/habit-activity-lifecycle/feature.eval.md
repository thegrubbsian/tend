---
node: F-aotv97
criteria:
  - id: C1
    statement: Deactivation reconciles an active persisted habit before closing its sole open activity period at the explicit operation instant, makes the habit inactive, exempts every remaining editable current or grace bucket, and preserves all entries and final buckets.
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Lifecycle/HabitActivityOperationsTests.swift" }
    required: true
  - id: C2
    statement: Same-period reactivation starts one new open activity period at the explicit instant and, when the latest closed activity boundary shares the resolved current period, restores the exact exempt current bucket with its entries and refreshed calendar boundaries without restoring an older exempt bucket or creating a duplicate period key.
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Lifecycle/HabitActivityOperationsTests.swift" }
    required: true
  - id: C3
    statement: Later-period reactivation creates only the daily or Monday-through-Sunday weekly bucket containing the reactivation instant, creates no buckets across the inactive gap, and honors exact local calendar and time-zone boundaries through repeated lifecycle cycles.
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Lifecycle/HabitActivityOperationsTests.swift" }
    required: true
  - id: C4
    statement: Lifecycle transitions use persistent relationship identity, reject duplicate transitions and inconsistent activity or bucket state with typed errors, and propagate reconciliation, calendar, evaluation, fetch, and persistence failures without speculative repair or unintended mutation.
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Lifecycle/HabitActivityOperationsTests.swift" }
    required: true
  - id: C5
    statement: Every successful transition performs exactly one lifecycle mutation save; a failed deactivation save rolls back exemption, period closure, and the active flag while retaining committed reconciliation facts, and a failed reactivation save removes inserted relationships and restores the inactive bucket state.
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Lifecycle/HabitActivityOperationsTests.swift" }
    required: true
---

# Acceptance

The contract covers the persistence-aware lifecycle domain mutations this feature
owns. All bindings use isolated in-memory SwiftData containers, explicit
instants and time zones, real calendar periods and bucket evaluation, and an
injectable lifecycle save boundary.

C1 owns deactivation and the domain rule that all non-final buckets, including a
provisionally met grace bucket, become exempt without losing contributions. C2
owns the answered same-period restoration decision. C3 owns inactive gaps and
cadence/calendar boundaries. C4 and C5 own deterministic refusal, failure
propagation, transaction count, and rollback behavior shared by both operations.

Streak values and frozen-chain computation, reminder scheduling, habit creation
and deletion, and UI state are satisfiable only by their dependent features and
are not acceptance conditions here.
