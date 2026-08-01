# SwiftData Habit Model

Establish the versioned, local-only persistence boundary for Tend. This feature
delivers a `TendCore` Swift package containing the complete SwiftData shape that
the later bucket, logging, activity, and streak features build on.

## Summary

Tend stores habits and their full history on device in SwiftData. The schema
must represent every durable fact in the domain without implementing the rules
that interpret those facts. It starts versioned, survives container recreation,
and remains compatible with a future CloudKit-backed store while v1 explicitly
disables CloudKit and every other network path.

The package targets iOS 26 in Swift 6 language mode. A macOS 26 library target
exists only so persistence tests can run without an iPhone or simulator UI; it
does not create a macOS product.

## Behavior

### Versioned model

`TendSchemaV1` defines four SwiftData model types and
`TendMigrationPlan` names the schema from the first shipped version:

- **Habit** stores a stable UUID, name, immutable cadence value, current target
  and unit, pinned weekdays, optional reminder time, current active flag,
  creation timestamp, and best streak. The unit defaults to `times`, pinned
  weekdays use a lossless scalar representation, and reminder time is stored as
  local minutes after midnight rather than as a dated instant.
- **HabitActivityPeriod** stores a stable UUID, inclusive start timestamp,
  optional end timestamp, and its habit. These periods preserve inactive gaps
  without manufacturing missed buckets.
- **HabitBucket** stores a stable UUID, cadence, and a canonical period key:
  `day:YYYY-MM-DD` for a daily bucket and `week:YYYY-MM-DD` for a weekly
  bucket, using the bucket's Monday start date. The later bucket engine derives
  that local date before formatting it with the fixed POSIX Gregorian
  representation; the key stores no time zone. Stored `Date` boundaries are a
  half-open interval `[start, end)`, so DST days may span 23 or 25 hours.
  Exemption and finalization facts, optional settled verdict, and the target and
  unit snapshot taken at finality complete the record. Open and grace state
  remain derived by the later bucket engine.
- **LogEntry** stores a stable UUID, timestamp, positive-integer amount, habit,
  and bucket. The later logging feature owns validation and append/delete
  behavior; this feature owns faithful persistence.

Stable UUIDs are ordinary attributes, not SwiftData uniqueness constraints.
Likewise, one bucket per habit and calendar interval is enforced by the later
bucket engine using the period key, because CloudKit cannot enforce SwiftData
unique constraints. The schema must never require duplicate buckets to express
reactivation: the answered lifecycle decision restores the same current bucket
and retains its entries.

### Ownership and deletion

Habit is the aggregate owner of activity periods, buckets, and log entries.
Deleting a habit cascades through all three collections. Other relationships
nullify rather than deny deletion, and every relationship has an explicit
inverse. A bucket retains aggregate history and its frozen requirement after
finality; the later domain features enforce when those fields may change.

### Local persistence

`TendModelContainer` creates:

- a production file-backed container using `cloudKitDatabase: .none`;
- an in-memory container for isolated tests; and
- a file-backed container at an injected temporary URL for durability and
  migration tests.

The factory uses `TendSchemaV1` and `TendMigrationPlan` in every configuration.
Container creation and `ModelContext.save()` failures remain thrown errors; the
core package does not terminate the process or silently fall back to volatile
storage. A successful explicit save must be readable after the container and
context are destroyed and reopened against the same store URL.

No generic repository layer is introduced. Later domain services operate on a
`ModelContext`, define their own transactions, and save explicitly.

### CloudKit-ready, sync disabled

The schema follows Apple's CloudKit compatibility constraints from its first
version:

- no unique constraints;
- every relationship is optional and has an inverse;
- no relationship uses the deny delete rule; and
- every nonoptional stored attribute has a schema-visible default.

This is model compatibility only. Tend v1 has no iCloud entitlement, CloudKit
container, synchronization behavior, network request, account, analytics, or
telemetry. The production model configuration explicitly disables automatic
CloudKit discovery.

## Non-goals

This feature does not calculate calendar buckets, settle verdicts, validate log
mutations, transition activity state, compute streaks, schedule reminders, or
render UI. Those behaviors belong to the dependent features that can satisfy
their own acceptance contracts.

## Notes

- The persistence shape follows Apple's
  [SwiftData CloudKit compatibility guidance](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices).
- CloudKit schema choices are expensive to reverse after production promotion,
  so versioning, stable identifiers, optional relationships, explicit inverses,
  and additive evolution are established before user data exists.
- The package contains no third-party dependency. SwiftData, Foundation, and
  Swift Testing are sufficient.
