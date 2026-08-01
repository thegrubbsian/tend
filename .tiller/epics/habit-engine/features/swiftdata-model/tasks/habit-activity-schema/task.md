# Model habits and activity periods

Implement the root habit record and the activity periods needed to preserve
inactive gaps.

## Approach

- Add `Habit` and `HabitActivityPeriod` as final SwiftData model classes.
- Give every nonoptional persisted attribute a property-level default visible
  to the SwiftData schema while exposing explicit initializers for real records.
- Store the complete habit definition: stable UUID, name, cadence raw value,
  target, unit, pinned-weekday mask, optional reminder minute, active flag,
  creation timestamp, and best streak.
- Store activity periods with stable UUID, start, optional end, and an optional
  inverse relationship to their habit.
- Make the habit-to-period relationship optional, explicitly inverted, and
  cascading. Do not implement activate/deactivate transitions in the model
  classes; the lifecycle feature owns those transactions.
- Do not use `@Attribute(.unique)`, `#Unique`, or a deny delete rule.

## Surfaces

- `Sources/TendCore/Persistence/Models/Habit.swift`
- `Sources/TendCore/Persistence/Models/HabitActivityPeriod.swift`
- `Tests/TendCoreTests/Persistence/HabitModelTests.swift`

## Tests

- Round-trip every habit property through an in-memory SwiftData container.
- Cover daily and weekly cadence, no reminder, multiple pinned days, default
  `times`, active and inactive flags, and nonzero best streak.
- Save open and closed activity periods and verify both relationship directions.
- Delete a habit and verify its activity periods are removed.

## Edge cases

- Preserve an open activity period with a nil end date.
- Keep model storage capable of representing imported invalid data; name,
  target, cadence immutability, and lifecycle validation belong to later domain
  services rather than property observers that SwiftData can bypass.
- Ensure default values required for CloudKit compatibility do not replace the
  explicit values passed when creating a real habit.
