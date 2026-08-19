# Add the durable Journal entry schema

## Approach

Add a `JournalEntry` SwiftData model with a stable UUID, canonical `LocalDate`
key, verbatim body, `createdAt`, and `editedAt`. Advance the
versioned Tend schema and migration plan by one lightweight stage, carrying all
existing model types forward and adding JournalEntry without rewriting existing
records.

Keep the model intentionally flat. Do not add relationships to Habit,
HabitBucket, LogEntry, Goal, reminders, streaks, or presentation state. Put
timestamp maintenance and lifecycle authorization in later operations rather
than model observers or convenience setters.
Keep the stored graph permissive for migration and CloudKit-compatible loading:
do not add a unique constraint or deny rule. The operation boundary enforces
one entry per day, and read queries detect corrupt duplicates.

## Surfaces

- `Sources/TendCore/Persistence/Models/JournalEntry.swift`
- `Sources/TendCore/Persistence/TendSchema.swift`
- `Sources/TendCore/Persistence/TendModelContainer.swift`
- Persistence test helpers and fixtures under `Tests/TendCoreTests`

## Tests

Write failing persistence tests first for round-trip identity, canonical day,
unbounded multiline body, both timestamps, permissive duplicate loading, and
the absence of unique/deny constraints. Extend
container migration tests to open the prior schema, migrate representative
Habit and Goal graphs, add a Journal entry, reopen the store, and prove every
record is intact. Bind the completed suites to
`PersistenceContainerTests` and `JournalEntryPersistenceTests`.

## Edge cases

Reject or surface malformed stored day keys; never silently repair them during
migration. Verify uniqueness survives a store reopen and a competing insert.
Exercise empty, whitespace-only, multiline, Unicode, and very large bodies
without trimming or title synthesis. A migration failure must leave the prior
store readable by its original schema and must not partially mutate test
fixtures.
