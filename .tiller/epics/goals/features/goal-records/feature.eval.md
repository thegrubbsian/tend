---
node: F-e149jw
criteria:
  - id: C1
    statement: The local versioned SwiftData schema durably represents Goal, separate Accumulate entries and Measure readings, stable kind and GoalDate values, append order, exact optional inverse and cascade relationships, and migrates the complete habit-only store without changing or losing existing data.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/GoalPersistenceTests.swift" }
    required: true
  - id: C2
    statement: Goal creation normalizes and validates every shared and kind-specific field, rejects zero-span Measure and invalid deadline chronology, persists exactly one childless Goal with immutable kind and creation timestamp in one save, and removes only the inserted aggregate after save failure.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalCreationOperationsTests.swift" }
    required: true
  - id: C3
    statement: Progress operations append only positive Accumulate amounts or integer Measure readings to Today or eligible Yesterday, preserve assigned date and append order, delete only owned items still dated Today or Yesterday, reject cross-kind and malformed relationships, and save each mutation once with complete operation-local rollback.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalProgressOperationsTests.swift" }
    required: true
  - id: C4
    statement: Progress computation returns an uncapped checked Accumulate total and normalized fraction, or the date-and-sequence-latest Measure reading with direction-derived clamped distance and truthful current value, while rejecting invalid relationships, sequences, kinds, scalars, and arithmetic overflow without persistence mutation.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalProgressComputationTests.swift" }
    required: true
  - id: C5
    statement: Adding the goal schema, creation, progress operations, and progress computation preserves all existing habit persistence, bucket, logging, lifecycle, streak, history, management, and Today domain behavior.
    polarity: preserve
    binding: { type: test, run: "Scripts/tiller-swift-test" }
    baseline:
      surface: "Sources/TendCore existing habit domain and persistence behavior"
      captured_at: { kind: git_tree, value: "git:cf1df1a30fb440c8664020d61c2d8990fb3f5830", path: Sources/TendCore, observed_at: "2026-08-15T02:21:08Z" }
    required: true
---

# Acceptance

C1 owns faithful persistence, date-only values, aggregate shape, migration, and local-only container compatibility. C2 owns the only supported creation transaction. C3 owns recent append/delete authorization and mutation semantics. C4 owns both kinds' complete-history arithmetic and consumer-ready snapshots. C5 protects the existing habit domain while the shared schema expands.

All five criteria are satisfiable inside goals/goal-records (F-e149jw). Durable closure, rescoping, deletion of the whole Goal, deadline pace, and standing remain with goals/goal-lifecycle (F-5aficd). Forms, progress visuals, history interaction, and owner confirmation remain with goals/goal-experience (F-xowx7x).
