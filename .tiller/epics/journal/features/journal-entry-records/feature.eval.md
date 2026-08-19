---
node: F-rsayqb
criteria:
  - id: C1
    statement: The shared LocalDate cleanly replaces GoalDate while preserving strict canonical parsing, comparison, adjacent-day arithmetic, time-zone start boundaries, and every existing Goal civil-date behavior without an alias or parallel implementation.
    polarity: preserve
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Calendar/LocalDateTests.swift && Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalCreationOperationsTests.swift && Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalProgressOperationsTests.swift" }
    baseline:
      surface: "Sources/TendCore/Goals/GoalDate.swift and existing Goal civil-date callers"
      captured_at: { kind: git_tree, value: "git:ac3ece4dfda620e906f28d35a6028f133679ec67", path: Sources/TendCore/Goals, observed_at: "2026-08-19T22:23:34Z" }
    required: true
  - id: C2
    statement: The next permissive SwiftData schema stores durable JournalEntry identity, canonical local day, verbatim body, immutable creation time, and maintained edit time without relationships to habits, logs, goals, reminders, streaks, or verdicts, while migrating all existing records unchanged.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/PersistenceContainerTests.swift && Scripts/tiller-swift-test Tests/TendCoreTests/Persistence/JournalEntryPersistenceTests.swift" }
    required: true
  - id: C3
    statement: Journal entry operations allow creation and deletion only for today or yesterday, allow body edits forever, reject duplicate days and invalid graphs, maintain timestamps exactly, and roll every failed save back to the complete prior state.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Journal/JournalEntryOperationsTests.swift" }
    required: true
  - id: C4
    statement: Journal entry queries return zero or one entry by day, reverse-chronological entries, and inclusive written-day sets deterministically, while reporting malformed or duplicate persisted days instead of inventing a result or treating absence as failure.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Journal/JournalEntryQueryTests.swift" }
    required: true
  - id: C5
    statement: Adding Journal persistence and operations preserves every existing Habit, Goal, history, closure, Today, reminder, and durable-container behavior without creating Journal side effects in those domains.
    polarity: preserve
    binding: { type: command, run: "Scripts/tiller-xcode-test TendTests && Scripts/tiller-swift-test" }
    baseline:
      surface: "Sources/TendCore and App/TendTests before Journal persistence"
      captured_at: { kind: git_tree, value: "git:ac3ece4dfda620e906f28d35a6028f133679ec67", path: Sources/TendCore, observed_at: "2026-08-19T22:23:34Z" }
    required: true
---

# Acceptance

C1 prevents Journal from introducing a second civil-day vocabulary. C2 binds
the durable shape, permissive migration boundary, and domain isolation. C3
proves unique-day enforcement and the deliberate split between fossilized
existence and forever-editable prose. C4 supplies the deterministic reads
needed by later Journal surfaces without smuggling presentation into the
domain. C5 is the brownfield guard for the persistent graph this schema
extends.

All five criteria are satisfiable inside journal/journal-entry-records (F-rsayqb). The Journal destination, editor interaction, live daily garden, and Today invitation belong to later Journal features and are not required for this feature to pass.