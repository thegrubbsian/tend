# Project the Journal overview

## Approach

Build an observable `JournalOverviewModel` around `JournalEntryQuery`. From one
explicit instant, time zone, calendar, and locale, project today's state, past
rows, month bounds, selected month, and binary day cells. Derive every row title
from the body's first line at refresh time; use a localized quiet fallback for
an existing empty body.

Keep date arithmetic and written-day identity in `LocalDate`. Reuse the Habit
garden's month-navigation geometry and presentation model shape, but define
Journal-specific binary states so missed, grace, risk, progress, and streak
cannot leak into the API. Preserve selected month across refreshes and clamp it
only when the earliest/current bounds move past it.

Refresh on first appearance, scene activation, local-day schedule entry,
time-zone or locale change, entry graph fingerprint change, and retry. A load
failure retains no invented rows and exposes one retryable error.

## Surfaces

- `App/Tend/Journal/JournalOverviewModel.swift`
- A Journal month projection type under `App/Tend/Journal`
- Shared Almanac month-grid geometry only where extraction avoids duplicated
  layout logic without merging Habit and Journal state semantics
- `App/TendTests/JournalOverviewModelTests.swift`

## Tests

Write failing tests for empty/today/past entries, reverse chronology, first-line
updates, empty-body fallback, month bounds, leap day, cross-year navigation,
written versus absent cells, clay today marker metadata, deletion clamping,
malformed and duplicate data, retry, local midnight, time-zone/locale changes,
and deterministic repeated refresh.

## Edge cases

An old empty body still represents a written day. Future corrupt entries must
fail projection rather than extend the month range. The current month remains
navigable with no entries. Do not use DateFormatter output as row identity and
do not write or reconcile the store while projecting.
