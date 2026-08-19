# Render each entry's live Habit garden

## Approach

Extract one shared, read-only Habit-day projection from the existing bucket,
activity-period, and evaluation rules rather than reimplementing history inside
Journal. Given a `LocalDate`, current instant, time zone, and queried Habit
graphs, return stable rows for every Habit active that day with name,
progress/result, and Almanac state. Do not reconcile, create buckets, log, or
save merely to read.

Build a Journal garden model that fingerprints Habit inputs and refreshes on
entry selection, Habit graph changes, scene activation, local context changes,
and retry. Isolate a malformed Habit graph to one unavailable row while
retaining valid siblings and deterministic Habit ordering.

Render the garden beneath the selected entry's prose using the established
garden-bed cells and Habit state colors. Store no snapshot or relationship on
`JournalEntry`.

## Surfaces

- A shared read-only Habit-day query under `Sources/TendCore/History`
- Existing Habit detail projection refactored only enough to reuse the proven
  single-day rules
- `App/Tend/Journal/JournalDayGardenModel.swift`
- `App/Tend/Journal/JournalDayGardenView.swift`
- `Tests/TendCoreTests/History/JournalDayGardenQueryTests.swift`
- `App/TendTests/JournalDayGardenModelTests.swift`
- `App/TendUITests/JournalDayGardenUITests.swift`

## Tests

Write failing tests for daily and weekly Habits, active/inactive intervals,
met/missed/open/grace/exempt states, partial progress, before-creation and
future exclusion, deterministic order, malformed sibling isolation, DST,
time-zone changes, and refresh after real logging/correction/archive/reactivate
operations. Assert projection performs no inserts, deletes, reconciliations, or
saves and JournalEntry bytes never change.

## Edge cases

An entry can predate a Habit and must not invent a row. Weekly Habits use the
truthful bucket containing the entry day, not a fabricated daily result. A
missing required bucket is unavailable, not missed. A log edit changes the live
garden on refresh without rewriting the prose record.
