# Seed Deterministic Today States

## Approach

Extend the existing DEBUG-only UI-test store fixture registry with four explicit
Today variants:

- `today-mixed`: five active habits with three unresolved rows, two met rows,
  daily and weekly cadence, exact quantity and binary progress, and one daily
  open-grace streak risk;
- `today-all-tended`: a nonempty active set whose current buckets are all met;
- `today-inactive`: persisted habits with no active habit;
- `today-failure`: valid active siblings plus one habit whose stored raw cadence
  is deliberately corrupted after valid creation.

Each seed captures `launchInstant` once and uses the injected UI-test time zone
for every calendar derivation and operation. Compute relative daily and weekly
periods with `CalendarBucketSchedule`; never subtract fixed 86,400-second days or
assume the launch weekday. Seed valid graphs through public
`HabitManagementOperations`, `HabitActivityOperations`, and
`LogEntryOperations`, then verify them through `HabitTodayComputation`.

The failure variant is the sole exception: after creating a valid aggregate
through public operations, set one raw cadence to a documented unsupported value
and save so the real production computation and unavailable-row handling are
exercised. Do not construct duplicate buckets, detached graphs, or fake
presentation values.

Fixtures require exactly one enabled flag, valid named store, reset flag, and
supported fixture name. They seed only after the reset and never on a same-store
relaunch. Preserve strict option parsing so a fixture token cannot be consumed
as the store name and malformed launch arguments fail closed.

No release build, ordinary launch, preview, or runtime sample data path may
reach this registry.

## Surfaces

- Create `App/Tend/Application/TodayDashboardUITestFixture.swift`.
- Modify `App/Tend/Application/TendUITestStore.swift` only to register and
  dispatch the four exact Today fixture names.
- Extend `App/TendTests/TendApplicationModelTests.swift` for launch-option,
  reset, store isolation, seed-state, and relaunch persistence contracts.
- Consume the TendCore projection from
  app-experience/today-dashboard/current-bucket-projection.
- Do not edit Today views, presentation models, production container creation,
  schema models, or release behavior.

## Tests

Run:

```bash
Scripts/tiller-xcode-test TendTests/TendApplicationModelTests
Scripts/tiller-xcode-test TendTests
swift build
```

Tests must prove:

- every fixture refuses missing/duplicate enabled, store, reset, and fixture
  arguments plus unsupported names and traversal-like store names;
- fixture names are never accepted as missing store-name values;
- reset seeds each variant exactly once in an isolated named file store;
- `today-mixed` computes five active rows, exact three/two unresolved/met
  partition, exact entry aggregates, one daily risk, and an all-week weekly row;
- `today-all-tended` computes a nonempty fully met set;
- `today-inactive` persists history but computes no active row;
- `today-failure` has valid siblings and one exact unsupported-cadence failure;
- independent named stores cannot observe each other;
- relaunch without reset or fixture preserves the seeded store without adding
  entries, changing identifiers, or reopening the store during the same app
  process;
- production launch arguments return the production container path and never
  seed fixtures.

## Edge cases

- The launch date may be Monday, a DST transition, month/year boundary, or
  ISO-week boundary; all expected keys derive from the same calendar API.
- The mixed fixture’s header truth is `2 of 5`; the Pencil board’s illustrative
  `3 of 5` does not override persisted facts.
- A weekly habit is active all week even when the launch weekday is unpinned.
- Over-target entries remain distinct append history and are not normalized to
  the target.
- The inactive fixture deactivates through the public lifecycle operation and
  retains history.
- The malformed failure habit is named and isolated so tests never mistake it
  for a valid zero-progress row.
