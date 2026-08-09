# Plan bounded local reminder occasions

## Approach

Write the deterministic planning boundary for
device-readiness/local-reminders (F-zbcv8j) without importing
UserNotifications. Start with failing app-unit tests and express all platform
inputs as values: habit UUID and name, cadence, target and unit, pinned
weekdays, reminder minute, active state, the current TendCore period key,
progress and met state, plus an injected instant, calendar, time zone, locale,
and request limit.

Define focused value types for planner input and output. An output occurrence
must carry a stable identifier derived from the habit UUID and local occurrence,
its absolute fire date and local date components, habit UUID, title, body, and
bucket period key. Keep system request construction out of these types.

Use the existing `ReminderTime`, `PinnedWeekdays`,
`CalendarBucketSchedule`, and localized amount formatting rather than adding
parallel cadence, weekday, bucket, or unit rules. Enumerate only dates strictly
after the injected instant. Daily habits contribute one occasion per local day;
weekly habits contribute one per selected weekday. Ask Calendar for matching
local times with an explicit missing/repeated-time policy so DST gaps and folds
are deterministic.

Suppress every occurrence whose period key equals a met current period. Do not
suppress later periods. Content uses the habit name and a cadence-aware
remaining-requirement line: current occurrences use `max(target - progress, 0)`
and future occurrences use the configured target. The exact stored unit remains
owner text, with the existing singular handling for one `times`.

Respect the platform limit without starving a habit. Reserve each eligible
habit's earliest occurrence, sort those reservations by fire date and UUID, then
fill remaining slots from all next occurrences in chronological order with the
same stable tie-break. Stop at the injected limit; do not construct an unbounded
calendar horizon or add a priority-queue abstraction unless the measured
dozen-habit path needs it.

## Surfaces

- Add a focused reminders folder under `App/Tend/Reminders/` containing the
  value types, content formatter if needed, and planner.
- Add `App/TendTests/ReminderPlanTests.swift`.
- Reuse public TendCore calendar and habit value types.
- Do not modify SwiftData models, TendCore bucket semantics, existing habit
  forms, mutation models, shell navigation, or the Xcode project unless
  filesystem-synchronized groups fail to discover the new files.

## Tests

Cover observable plans for:

- daily reminders before and after today's reminder time;
- weekly reminders on one and several pinned weekdays, including several
  occasions in the same weekly bucket;
- inactive habits, no reminder time, weekly no-pin configuration, and one
  occasion regardless of target;
- current partial progress, met-current-bucket suppression, future-bucket
  retention, and reappearance when the current bucket becomes unmet;
- stable identifiers and deterministic ordering when times match;
- spring-forward missing times, fall-back repeated times, year/week rollover,
  and two distinct time zones without using the wall clock;
- limits below and above the eligible habit count, next-occurrence reservation,
  chronological fill, exact 64-request cap, and zero capacity; and
- localized title/body facts, including one `times`, multi-count, quantity, and
  daily versus weekly scope.

Run `Scripts/tiller-xcode-test TendTests/ReminderPlanTests` and
`xcodebuild -project Tend.xcodeproj -scheme Tend -destination
'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`.

The smoke test constructs the five release habits at one injected local instant,
prints or inspects the next planned occurrence for each, marks one daily and the
weekly bucket met, replans, and observes only those current-period occasions
disappear.

## Edge cases

- An invalid cadence, reminder minute, pin bitset, target, or empty owner text
  makes that habit ineligible without corrupting the rest of the plan.
- A reminder exactly equal to the injected instant is past for planning
  purposes; no catch-up notification is emitted.
- Meeting a weekly bucket suppresses every later pinned day that week, not just
  the next pin.
- UUID and local occurrence form identity; mutable name, progress, target, unit,
  and time are content, not identity.
- Calendar enumeration must terminate for empty weekly pins and tiny limits.
- Planning allocates no history-sized collection and fetches no SwiftData data.
