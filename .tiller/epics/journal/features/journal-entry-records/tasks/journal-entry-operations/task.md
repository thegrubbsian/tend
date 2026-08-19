# Enforce Journal entry lifecycle rules

## Approach

Build one `JournalEntryOperations` boundary for create, edit, and delete. Each
operation receives its `ModelContext`, operation instant, and owner time zone;
it derives today and yesterday with `LocalDate` and authorizes existence
changes against that two-day window.

Creation refuses a duplicate day, sets both timestamps to the operation
instant, and saves exactly the supplied body. Editing verifies a live local
entry and permits replacement at any age; a real body change updates only
`editedAt`, while a no-op is inert. Deletion verifies the same ownership and
graph invariants, then refuses any entry older than yesterday. Snapshot every
mutated field and membership before saving so an injected or real save failure
restores the complete prior graph.

Expose typed errors for ineligible day, duplicate day, malformed date, detached
model, deleted model, foreign context, and persistence failure. Do not trigger
habit logging, reminders, streaks, Goal progress, or notifications.

## Surfaces

- `Sources/TendCore/Journal/JournalEntryOperations.swift`
- A small Journal write-window helper beside the operations when needed
- Existing persistence/context test doubles reused by `App/TendTests`
- `App/TendTests/JournalEntryOperationsTests.swift`

## Tests

Write the operation contract tests before implementation. Cover today and
yesterday creation/deletion, past and future refusal, duplicate-day refusal,
forever editing, exact timestamp transitions, no-op editing, verbatim bodies,
save rollback, detached/deleted/foreign models, DST boundaries, and extreme
time zones. Assert that Habit, LogEntry, Goal, reminder, and streak state remain
byte-for-byte unchanged around every Journal mutation.

## Edge cases

The operation instant, not wall-clock globals, decides authorization. A time
zone change may alter which two days are currently eligible but never rewrites
an entry's stored day. Concurrent duplicate creation must fail truthfully.
Editing an old entry to an empty body is an edit, not deletion; the day keeps
its historical existence.
