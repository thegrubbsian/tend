# Provide deterministic Journal entry queries

## Approach

Add a read-only `JournalEntryQuery` that validates persisted entries before
projecting them. Provide lookup by `LocalDate`, reverse-chronological listing,
and an inclusive written-day set for a supplied date window. Sort by canonical
day descending and stable UUID as the defensive tie-break; do not rely on
SwiftData relationship or fetch order.

Treat duplicate days and malformed keys as domain failures. Return absence as
absence—never a missed state, placeholder entry, count, streak, or verdict.
Keep first-line extraction and localized date formatting in the later
presentation feature.

## Surfaces

- `Sources/TendCore/Journal/JournalEntryQuery.swift`
- Focused query fixtures under `Tests/TendCoreTests`
- `Tests/TendCoreTests/Journal/JournalEntryQueryTests.swift`

## Tests

Write failing tests for empty stores, exact-day hits and misses, reverse order,
stable tie-breaking of corrupt duplicate days, inclusive month boundaries,
cross-year windows, malformed persisted keys, and repeated deterministic
projection. Prove queries perform no writes and leave all timestamps and
non-Journal graphs unchanged.

## Edge cases

Reject an inverted date window rather than swapping it silently. Handle leap
days and the minimum/maximum supported LocalDate boundaries without overflow.
Do not collapse a data-integrity failure into an empty Journal, because later
screens need a truthful retry state.
