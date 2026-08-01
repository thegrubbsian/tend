# Model buckets and log entries

Complete the version-one model graph with calendar buckets and their log
entries.

## Approach

- Add `HabitBucket` with stable UUID and cadence-qualified string identity:
  `day:YYYY-MM-DD` for daily periods and `week:YYYY-MM-DD` using the weekly
  period's Monday start. The later bucket engine derives the local date; this
  task persists its fixed POSIX Gregorian encoding without a time zone.
- Persist start-inclusive and end-exclusive `Date` boundaries separately from
  identity, plus cadence raw value, exemption flag, optional finalization
  timestamp, optional settled verdict, and optional target and unit snapshots.
- Add `LogEntry` with stable UUID, timestamp, positive-integer amount, and
  optional inverse relationships to its habit and bucket.
- Make Habit the aggregate owner of buckets and entries with optional cascading
  relationships. Give Bucket an optional entry collection and use nullification,
  not deny, for non-owning relationship changes.
- Add `TendSchemaV1` listing all four model types and
  `TendMigrationPlan` with version one as its initial schema.
- Keep period keys indexed only through normal fetches. Do not add a uniqueness
  constraint; the later bucket engine enforces one bucket per habit and period.
- Store facts only. Bucket state derivation, finalization, requirement snapshot
  mutation, entry validation, and immutable-history rules remain downstream.

## Surfaces

- `Sources/TendCore/Persistence/Models/Habit.swift`
- `Sources/TendCore/Persistence/Models/HabitBucket.swift`
- `Sources/TendCore/Persistence/Models/LogEntry.swift`
- `Sources/TendCore/Persistence/TendSchema.swift`
- `Tests/TendCoreTests/Persistence/BucketEntryModelTests.swift`

## Tests

- Round-trip the exact canonical keys and half-open boundaries for daily and
  weekly samples.
- Cover a 23-hour spring-forward day, a 25-hour fall-back day, and mutation of a
  non-final bucket's boundaries after a time-zone change without changing its
  key or creating another bucket.
- Cover open facts with nil snapshots and verdict, final facts with frozen
  snapshots and verdict, and exempt buckets.
- Save multiple positive entries, verify both inverse relationships, and confirm
  their aggregate survives a context save and refetch.
- Delete a habit and verify its buckets and entries are removed.
- Verify the version-one schema contains exactly the four specified models.

## Edge cases

- Permit a log timestamp outside the selected bucket because grace back-fill is
  represented by explicit bucket membership, not by rewriting when it was
  recorded.
- Keep finality fields optional as a coherent set; the bucket engine later owns
  the transaction that fills them.
- Preserve stable logical IDs without relying on database uniqueness or
  manufacturing duplicate buckets for same-period reactivation.
