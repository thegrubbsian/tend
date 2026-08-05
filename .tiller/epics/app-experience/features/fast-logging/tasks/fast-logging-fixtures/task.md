# Seed Deterministic Logging Journeys

## Approach

Extend the DEBUG-only named-store registry with two Fast Logging fixture
families seeded entirely through public TendCore operations and verified through
`HabitLoggingComputation` plus `HabitTodayComputation`:

- `fast-logging-daily`: daily target-one and multi-count exact-`times` habits,
  one non-`times` `time` habit, one partially complete quantity habit with two
  distinct current entries, one completed quantity habit, and one unfinished
  daily grace bucket reachable from an at-risk row;
- `fast-logging-weekly`: weekly exact-`times` and quantity habits with distinct
  current entries plus an unfinished preceding weekly bucket. The test supplies
  a Monday fixed instant so Last Week is genuinely in grace.

Use memorable unique owner names and exact integer amounts so UI assertions can
prove dispatch, quick-add, Finish, custom amount, set total, entry delete, Undo,
current/grace selection, completed access, and same-store relaunch without
ambiguous elements. Include duplicate timestamps and ordinary UUIDs where
stable persistent identity must break ties, but create and mutate all valid
relationships through public operations.

Capture `launchInstant` and time zone once. Derive prior/current daily and weekly
periods through `CalendarBucketSchedule`; never subtract 86,400 seconds or assume
the runner’s locale/weekday. Seed prior work chronologically so the intended
grace and streak states are real. Verify every exact snapshot before returning.

Keep fixture parsing strict: one enabled flag, named store, reset flag, supported
fixture, fixed instant, and time zone. Seed only after reset, never on same-store
relaunch. No release, preview, ordinary launch, or runtime sample-data path may
reach the fixture registry.

## Surfaces

- Create `App/Tend/Application/FastLoggingUITestFixture.swift`.
- Modify `App/Tend/Application/TendUITestStore.swift` only to register and
  dispatch `fast-logging-daily` and `fast-logging-weekly`.
- Extend `App/TendTests/TendApplicationModelTests.swift` for parsing, isolated
  seeding, exact persisted facts, and relaunch behavior.
- Reuse existing fixed-instant/time-zone launch arguments and named file-store
  conventions.
- Do not edit Today views, logging presentation, Almanac tokens, persistence
  schema, release container creation, or domain operation semantics.

## Tests

Run:

```bash
Scripts/tiller-xcode-test TendTests/TendApplicationModelTests
Scripts/tiller-xcode-test TendTests
swift build
```

Tests must prove:

- both names obey the existing strict option grammar and refuse missing,
  duplicate, unsupported, and traversal-like values;
- reset creates an isolated named store once; relaunch without reset/fixture
  preserves exactly the mutated store and adds no fixture entry;
- the daily family has exact current and grace keys, target-one/multi-count
  `times`, exact non-`times` boundary, partial/completed quantity states,
  distinct entries, and one real risk state;
- the weekly family launched on Monday has exact This Week/Last Week keys,
  unfinished prior progress, current progress, exact entry amounts, and weekly
  presence independent of pinned weekdays;
- all expected progress, target, unit, cadence, met/risk state, entry identity,
  timestamp order, and bucket phase come from production TendCore projections;
- independent fixture/store names cannot observe each other;
- production arguments return the production container and never seed Fast
  Logging data.

## Edge cases

- Test launch instants may cross month/year, ISO-week, DST, or time-zone
  boundaries; every key comes from the schedule for the injected zone.
- `time` is deliberately a quantity unit; only `times` is direct count logging.
- Completed quantity and completed `times` rows remain present so the interactive
  completed-check contract can be exercised.
- Prior grace entries retain their real append timestamps and selected bucket
  relationship; do not forge display strings.
- Fixtures establish facts only. They contain no test-only action routing,
  bypass authorization, or presentation values.
