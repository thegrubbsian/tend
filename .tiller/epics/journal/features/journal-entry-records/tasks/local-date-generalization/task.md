# Generalize the shared civil-date value type

## Approach

Rename `GoalDate` and `GoalDateError` to domain-neutral `LocalDate` and
`LocalDateError`, including the source file, with language-server refactors so
every production and test reference moves in one clean cutover. Keep the value's
wire representation and implementation unchanged except for names: strict
`YYYY-MM-DD` parsing, Gregorian validity, ordering, previous/next arithmetic,
Codable behavior, and time-zone-aware start boundaries remain the same.

Rename the focused test suite and update Goal APIs to accept `LocalDate`
directly. Remove every old symbol and filename; do not leave a typealias,
deprecated spelling, wrapper, or second parser.

## Surfaces

- `Sources/TendCore/Goals/GoalDate.swift`, renamed to a shared
  `Sources/TendCore/Calendar/LocalDate.swift`
- Goal creation, management, progress, standing, detail, and persistence APIs
  under `Sources/TendCore`
- App Goal presentation and deterministic UI fixtures under `App/Tend`
- Goal and persistence tests under `App/TendTests`

## Tests

Rename `GoalDateTests` to `LocalDateTests` and keep every existing parsing,
ordering, boundary, Codable, DST, extreme-offset, and malformed-value case.
Run the focused LocalDate, Goal creation, Goal progress, Goal detail, Goal
standing, and persistence suites. The red step is the removed old symbol;
the green step proves every caller uses the shared name without changing
observable Goal behavior.

## Edge cases

Preserve rejection of malformed separators, impossible dates, unsupported year
boundaries, and unrepresentable adjacent days. Preserve exact start-of-day
behavior through skipped or repeated local times. Avoid formatting or calendar
presentation changes: this task changes vocabulary, not date semantics.
