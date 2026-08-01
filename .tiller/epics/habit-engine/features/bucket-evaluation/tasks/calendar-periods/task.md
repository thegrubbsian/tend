# Calculate local calendar bucket periods

Build the pure calendar layer that gives every later bucket operation one
canonical interpretation of a daily or weekly period.

## Approach

- Add `CalendarBucketPeriod`, carrying cadence, canonical key, inclusive start,
  exclusive end, and exclusive grace end.
- Add `CalendarBucketSchedule` APIs to find the period containing an explicit
  instant, reconstruct a period from a persisted key, and advance to the next
  period.
- Construct a Gregorian calendar from an explicit `TimeZone`, force Monday as
  the weekly boundary, and derive every date by calendar arithmetic rather than
  seconds.
- Encode strict `day:YYYY-MM-DD` and `week:YYYY-MM-DD` keys from local
  components. Weekly keys always name the Monday start.
- Return typed errors for unsupported cadence values, malformed or impossible
  keys, and calendar operations that cannot produce a boundary. Do not read the
  wall clock, persist models, or introduce a general clock abstraction.

## Surfaces

- `Sources/TendCore/Buckets/CalendarBucketSchedule.swift`
- `Tests/TendCoreTests/Buckets/CalendarBucketScheduleTests.swift`

## Tests

- Bind acceptance criterion C1 to
  `CalendarBucketScheduleTests.swift`.
- Prove daily and weekly keys, Monday-Sunday ranges, start-inclusive/end-
  exclusive transitions, and year/month rollovers with literal fixtures.
- Cover spring-forward and fall-back days, including grace intervals that cross
  DST, and assert calendar-day semantics rather than fixed hours.
- Reconstruct the same key in multiple time zones and verify stable identity
  with recalculated absolute boundaries.
- Verify strict key rejection and deterministic results independent of host
  locale, time zone, and current date.

## Edge cases

- Reject non-Monday weekly keys and impossible dates rather than normalizing
  them.
- Handle repeated and nonexistent local clock times through calendar start-of-
  day operations; never synthesize a fixed 24-hour day.
- Keep POSIX key formatting stable at year boundaries and for single-digit
  months and days.
- Treat failed date addition or component extraction as an error, not a
  force-unwrap or fallback calendar.
