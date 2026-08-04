# Render Almanac Today Surface

## Approach

Replace only the nonempty placeholder inside `TodayDestinationChrome` with the
approved Almanac dashboard. Retain the existing production `@Query`, shared
New-habit sheet, forced-light shell, date eyebrow, landing destination,
two-destination tab pill, and DEBUG fixed-date seam.

Create a focused `TodayView` that renders `TodayModel` presentation values:

- existing first-launch introduction and `Plant a habit` control;
- plain `No active habits.` body for an inactive-only store;
- localized date, `Today`, and truthful met/active fraction;
- TO TEND raised cards, optional risk line, progress track, exact progress
  meta, and ambient progress ring;
- `All tended.` when appropriate;
- TENDED compact rows with filled checks;
- visible unavailable cards with one retry control.

Use existing Almanac palette, type, spacing, radius, stroke, readable-width, and
safe-area tokens. Add local view geometry only where the approved Today board
requires a shape that no token represents. Do not change the token definitions
to make one board fit.

Render the 52-point ring as a static visual seam: empty hairline, clockwise
clamped moss arc, or complete check. Hide its geometry from accessibility and
give it no gesture, button trait, action closure, haptic, sheet, or write. Keep
the whole factual card as one combined accessibility element. The only row
control in this feature is retry on an unavailable row.

Drive boundary refresh through exactly one
`TimelineView(LocalDayTimelineSchedule(...))`. Feed its date, the environment
calendar/time zone/locale, scene activation, and the query’s stable persisted
facts into `TodayModel.refresh`. Avoid an update loop: presentation changes must
not retrigger store refresh. Query changes after habit-management operations
must update Today without relaunch.

At accessibility sizes, change name/streak and progress layouts from horizontal
to vertical before text clips. Keep the dashboard scrollable above the floating
tab pill. On iPad, preserve the paper field and centered readable width rather
than adding a sidebar or stretching cards.

## Surfaces

- Modify `App/Tend/Shell/TodayDestinationChrome.swift` only at the Today content
  seam and its injected model/query wiring.
- Create `App/Tend/Today/TodayView.swift` for dashboard states and cards.
- Create `App/Tend/Today/TodayProgressRing.swift` if isolating the ring keeps the
  main view readable; otherwise keep the private shape beside `TodayView`.
- Create `App/TendUITests/TodayDashboardUITests.swift` for the production
  destination journey using the approved deterministic fixtures.
- Consume `TodayModel` and the DEBUG fixture family from predecessor tasks.
- Do not edit the root shell model, Habit Detail, All Habits, New/Edit form,
  domain operations, SwiftData schema, or Almanac token values.

## Tests

Run:

```bash
Scripts/tiller-xcode-test TendUITests/TodayDashboardUITests
Scripts/tiller-xcode-test TendUITests/HabitManagementUITests
Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests
Scripts/tiller-xcode-test TendTests/TodayModelTests
swift build
```

The Today UI suite launches independent named stores in the explicit
America/Los_Angeles fixture time zone and proves:

- a mixed store lands on Today with exact `2 of 5`, TO TEND and TENDED ordering,
  three daily/weekly unresolved rows, two compact met rows, exact progress and
  streak facts, and one daily grace-risk line;
- weekly rows remain present on an unpinned launch weekday;
- the all-met store shows `All tended.` plus TENDED rows and no empty TO TEND
  list;
- the inactive-only store shows no fraction, no success claim, and no habit
  card;
- the failure store keeps valid siblings plus one unavailable row and exact
  retry semantics;
- the ambient ring cannot be found as a button or accessibility action and
  interacting elsewhere does not alter persisted progress;
- the same named store relaunches without reseeding and retains owner-visible
  facts;
- creating, editing, archiving, reactivating, and deleting through existing
  Habits flows refreshes Today by persistent identity;
- first launch and shell selection still satisfy their established suites.

Use deterministic identifiers and full owner-visible labels. Do not target rows
by `firstMatch`, array index, or a substring that could select multiple cards.

## Edge cases

- Very long owner names and units wrap without covering the ring or tab pill.
- Over-target progress shows truthful text and a complete, nonoverflowing ring.
- Zero and unavailable progress have visually different, nonfabricated states.
- A failed row prevents `All tended.` and retains one reachable retry.
- Scene reactivation and a Timeline tick cannot produce duplicate rows.
- A ring visually resembling a control must still expose no control semantics
  until app-experience/fast-logging supplies a real write.
- Reduce Motion changes no meaning because this surface adds no semantic
  animation.
