---
node: F-vrsbxv
criteria:
  - id: C1
    statement: Append operations create exactly one positive entry in the canonical current bucket or an explicitly selected editable grace bucket, preserve the operation timestamp and both SwiftData relationships, and expose the resulting checked progress for daily and weekly habits
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Logging/LogEntryOperationsTests.swift" }
    required: true
  - id: C2
    statement: Delete operations remove exactly the selected entry only while its habit is active and its bucket is current or in grace; final, exempt, older, future, foreign, detached, and inconsistent records are rejected without entry mutation
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Logging/LogEntryOperationsTests.swift" }
    required: true
  - id: C3
    statement: Logging authorization follows reconciliation at explicit calendar boundaries, reports deterministic typed failures for invalid input, corrupt state, arithmetic overflow, and save errors, saves each actual entry mutation once, and rolls back that mutation completely while retaining valid reconciled calendar facts
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Logging/LogEntryOperationsTests.swift" }
    required: true
  - id: C4
    statement: Set total appends one positive difference against the selected daily or weekly bucket sum, performs no entry mutation when equal, rejects lower totals, and never creates daily sub-buckets for a weekly habit
    polarity: introduce
    binding: { type: test, ref: "Tests/TendCoreTests/Logging/BucketTotalOperationsTests.swift" }
    required: true
---

# Acceptance

The contract covers the persistence-aware domain mutations this feature owns:
current logging, explicit grace back-fill, correction by deletion, and
bucket-scoped set-total sugar. Each binding uses isolated in-memory SwiftData
containers, explicit instants and time zones, and the real bucket reconciliation
and evaluation surfaces.

Quick-add derivation, one-tap and sheet presentation, transient Undo timing,
haptics, streak computation, activity lifecycle transitions, and habit-detail
rendering remain with the dependent features that can satisfy those behaviors.
They are not acceptance conditions here.
