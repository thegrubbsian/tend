---
node: F-vbsg1a
criteria:
  - id: C1
    statement: Daily and weekly current streaks count consecutive final-met and pending-met buckets, assign no partial credit to pending-unmet buckets, reset only at a final miss, skip exempt buckets, and report the habit cadence needed to name the count in days or weeks.
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Streaks/StreakCalculatorTests.swift" }
    required: true
  - id: C2
    statement: A pending-unmet grace bucket preserves but does not increment the surviving chain and marks a nonzero displayed streak at risk, so twelve final met days followed by an unmet grace day and a pending-met current day display thirteen days at risk; an unmet open bucket or a grace bucket before the latest final miss does not mark the result at risk.
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Streaks/StreakCalculatorTests.swift" }
    required: true
  - id: C3
    statement: Exempt buckets and bucketless inactive periods contribute neither successes nor misses, inactive computation returns the frozen settled chain without reconciliation, and reactivation continues that chain from the bucket containing the explicit reactivation instant across daily, weekly, calendar-boundary, DST, and time-zone changes.
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Streaks/HabitStreakComputationTests.swift" }
    required: true
  - id: C4
    statement: "Habit.bestStreak is a monotonic persisted high-water mark established only by finalized met chains: provisional met buckets can raise current but not best, a strict finalized increase saves once, and a smaller derived history never lowers the stored value."
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Streaks/HabitStreakComputationTests.swift" }
    required: true
  - id: C5
    statement: Streak computation uses the supplied ModelContext, instant, time zone, persistent habit identity, BucketReconciler, and BucketEvaluator; it rejects detached habits, duplicate keys, negative bests, due-for-finalization or impossible evaluation states with typed errors, propagates dependency, fetch, and save failures, and rolls back a failed best mutation while retaining reconciliation facts already committed.
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Streaks/HabitStreakComputationTests.swift" }
    required: true
---

# Acceptance

The contract covers deterministic chain arithmetic and the thin persistence-aware
operation owned by this feature. All bindings use explicit instants and time
zones. Calculator checks run without persistence; integration checks use isolated
in-memory SwiftData containers, real bucket evaluation and reconciliation, and
an injectable streak save boundary.

C1 owns the hard-reset chain and cadence-bearing result. C2 records the approved
at-risk interpretation: an unresolved grace bucket remains a savable link but
does not earn credit. C3 owns lifecycle gaps and arbitrary calendar behavior.
C4 records the approved final-only best-streak rule rather than allowing editable
provisional evidence to establish a permanent record. C5 owns orchestration,
identity, refusal, error propagation, save count, and rollback.

Target and unit editing, bucket creation and finality, log mutation, activity
transitions, localized day/week copy, roster and detail presentation, visual
at-risk treatment, reminders, and on-device release evidence remain satisfiable
only by their owning or dependent features and are not acceptance conditions
here.
