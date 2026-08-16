---
node: F-5aficd
criteria:
  - id: C1
    statement: Goal closure persists exactly nil, harvested, or let-go disposition; the schema migration preserves every existing goal and progress relationship as open; and unknown stored lifecycle values fail honestly instead of defaulting to open.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/GoalLifecyclePersistenceTests.swift" }
    required: true
  - id: C2
    statement: Standing computation resolves the deadline through the supplied local calendar, calculates linear expectation from creation to the end of the deadline day, classifies open goals as on pace, behind, or past due with equality on pace and past due dominant, reports the next time-only refresh, and never persists derived state.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalStandingComputationTests.swift" }
    required: true
  - id: C3
    statement: Goal management validates and atomically updates every editable field without exposing kind or created-at mutation or snapshotting old scope, and permanently deletes an owned open or closed goal with all progress children while rejecting invalid ownership and restoring all operation-owned state after save failure.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalManagementOperationsTests.swift" }
    required: true
  - id: C4
    statement: Closing an owned open goal stores exactly the requested harvested or let-go disposition from any progress or standing, reopening clears only that disposition, closed goals reject progress append and delete-item operations, repeated or invalid transitions fail with typed errors, no computation auto-closes, and each successful transition saves once with complete rollback on failure.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalLifecycleOperationsTests.swift" }
    required: true
  - id: C5
    statement: Adding goal lifecycle state, computation, schema migration, and operations preserves all existing habit persistence, bucket, logging, activity, streak, history, management, and Today domain behavior.
    polarity: preserve
    binding: { type: test, run: "Scripts/tiller-swift-test" }
    baseline:
      surface: "Sources/TendCore existing habit domain and persistence behavior"
      captured_at: { kind: git_tree, value: "git:28d55bbad3876369e1d5d9e10e35b7397311909c", path: Sources/TendCore, observed_at: "2026-08-15T02:02:27Z" }
    required: true
---

# Acceptance

C1 owns the minimum durable lifecycle state and its migration from goals/goal-records (F-e149jw). C2 owns pure expectation and standing facts, including the deadline-day and time-only refresh semantics consumed by later UI features. C3 owns rescoping and permanent deletion as persistence transactions. C4 owns deliberate closure and reopening without progress-dependent policy. C5 is the brownfield guard for the shared TendCore schema and model container.

All five criteria are satisfiable inside goals/goal-lifecycle (F-5aficd) after its recorded prerequisite. Goal creation and progress-item arithmetic remain with goals/goal-records (F-e149jw). Forms, owner confirmation, visual standing, and history interaction remain with goals/goal-experience (F-xowx7x), while Today inclusion remains with goals/today-goal-surfacing (F-e8yd2r).
