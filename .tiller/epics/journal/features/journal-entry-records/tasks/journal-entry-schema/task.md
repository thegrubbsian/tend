# Add the durable Journal entry schema

## Approach

Add a `JournalEntry` SwiftData model with a stable UUID, unique canonical
`LocalDate` key, verbatim body, `createdAt`, and `editedAt`. Advance the
versioned Tend schema and migration plan by one lightweight stage, carrying all
existing model types forward and adding JournalEntry without rewriting existing
records.

Keep the model intentionally flat. Do not add relationships to Habit,
HabitBucket, LogEntry, Goal, reminders, streaks, or presentation state. Put
timestamp maintenance and lifecycle authorization in later operations rather
than model observers or convenience setters.

## Surfaces

- `Sources/TendCore/Persistence/Models/JournalEntry.swift`
- `Sources/TendCore/Persistence/TendSchema.swift`
- `Sources/TendCore/Persistence/TendModelContainer.swift`
- Persistence test helpers and fixtures under `App/TendTests`

## Tests

Write failing persistence tests first for round-trip identity, canonical day,
unbounded multiline body, both timestamps, and unique-day enforcement. Extend
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
