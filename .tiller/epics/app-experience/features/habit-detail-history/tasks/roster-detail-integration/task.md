# Integrate and verify the owner detail journey

## Approach

Integrate app-experience/habit-detail-history/habit-detail-surface (T-f5rev3)
into the existing All Habits owner flow, then prove the complete feature and
record its evidence without attesting the human gates.

Make each active and inactive roster row selectable while preserving its
existing trailing swipe actions, context menu, and VoiceOver custom actions.
Present the selected `HabitDetailView` full screen from the Habits destination
so the shell's floating tab pill is absent until Back returns to the same
roster. Use stable habit identity rather than row index or formatted name.
Back dismisses exactly one presentation; Edit remains owned inside detail.

Do not convert the two-destination shell into a router or add a third tab.
Do not wire Today cards ahead of app-experience/today-dashboard. Keep the
roster's New/Edit/Archive/Reactivate/Delete behavior unchanged when invoked
through its established actions.

Extend the DEBUG-only named file-backed UI-test composition with an optional
`habit-detail` fixture. Seed only a reset named store and use public TendCore
management, logging, lifecycle, streak, and reconciliation boundaries at
deterministic calendar-relative instants. The fixture must provide:

- an active daily habit old enough for met, missed, inactive-gap, grace, and
  current-open facts plus editable current and grace entries;
- an active weekly habit old enough for month-boundary strips and final/open
  facts; and
- an inactive habit with a frozen chain and dormant history.

Use stable owner-visible names and identifiers. Seed relative to one captured
launch instant and explicit time zone so DST and weekday changes cannot create
an impossible graph. Never write model fields directly when a public operation
can produce the state. Relaunch without reset reuses the same store and never
duplicates the fixture. Production composition cannot observe fixture
arguments, seed data, or use a test clock.

Create one `HabitDetailUITests` suite that starts from a unique reset store and
exercises the feature through owner-visible and accessible controls:

1. open active Daily detail from All Habits and prove the tab pill is absent;
2. verify title, metadata, current/best units, risk state when applicable,
   current month, legend, and recent entries;
3. select daily final, open, grace, inactive, and pre-creation/future facts on
   the pages where the fixture provides them and verify exact callout state;
4. navigate to both month bounds and prove disabled chevrons do not move past
   them;
5. delete one editable entry, verify the row/progress/history refresh, and prove
   the action dispatched once;
6. Edit a mutable field, cancel once, save once, return to the same detail, and
   verify finalized facts remain frozen while current facts update;
7. Archive and verify frozen/dormant detail, then Reactivate and verify the
   current bucket is due;
8. return to All Habits and verify established row actions remain available;
9. open Weekly detail and verify intersecting unnumbered strips, boundary-week
   callout, and week streak units;
10. open inactive detail and verify Reactivate without fabricated editable
    entries;
11. terminate and relaunch the same store without reset, then verify the
    successful mutations and final history persist; and
12. return with Back and prove shell selection remains Habits.

Use identifiers for reliable lookup, but assert owner-visible text, values,
enabled/selected traits, callout facts, and persisted outcomes. Never assert
private hierarchy, animation duration, fixture internals, or exact rendered
dates derived from the test runner instead of the app's own labels.

Exercise compact iPhone and centered iPad at default and two larger Dynamic Type
sizes. Capture the daily current month, daily historical month with callout,
weekly strips, recent entries, inactive detail, Edit return, and operation
failure/retry where a deterministic failure seam exists. Compare them with the
Habit Detail board and prose.

Run the accessibility pass with VoiceOver where physical simulator support is
available. Otherwise record the exact limitation and combine XCTest
labels/traits/hit-region evidence with a human device follow-up; never claim
VoiceOver traversal was observed when it was not. Verify Back, month controls,
every real bucket, Edit, entry deletion, Archive/Reactivate, and retry without a
swipe gesture. Check full labels, 44-point targets, reading order, forced light
appearance, Reduce Motion, safe-area clearance, and owner-written wrapping.

Store screenshots and a machine-readable manifest under
`.tiller/evidence/roster-detail-integration/`. Attach test runs and factual
adaptation observations to task and feature gates. Evidence records only what
was observed and leaves C5/C6 for the human to attest.

## Surfaces

- Modify `App/Tend/Habits/HabitRosterView.swift` for stable row selection and
  full-screen detail presentation.
- Modify `App/Tend/Shell/HabitsDestinationChrome.swift` only if it must supply a
  presentation dependency; preserve shell destination ownership.
- Extend `App/Tend/Application/TendUITestStore.swift` or add a focused
  DEBUG-only fixture source beside it.
- Create `App/TendUITests/HabitDetailUITests.swift`.
- Modify existing UI-test helpers and launch configuration only to share stable
  named-store/fixture behavior.
- Add evidence only under `.tiller/evidence/roster-detail-integration/`.
- Modify the Xcode project only if synchronized groups do not discover new
  sources/tests.
- Do not change Today, fast logging, notifications, persistence schema, domain
  semantics, tab destinations, Pencil comps, distribution, or release-device
  configuration.

## Tests

Write the end-to-end UI suite before wiring row selection and observe the
navigation contract fail. Keep every store name unique, reset only during
explicit setup, and clean up fixture arguments between launches.

Run:

- `Scripts/tiller-xcode-test TendUITests/HabitDetailUITests`
- `Scripts/tiller-xcode-test TendUITests/HabitManagementUITests`
- `Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests`
- `Scripts/tiller-xcode-test TendTests/HabitDetailModelTests`
- `Scripts/tiller-xcode-test TendTests/HabitRosterModelTests`
- `Scripts/tiller-xcode-test TendTests/HabitFormModelTests`
- `Scripts/tiller-xcode-test TendTests/TendApplicationModelTests`
- `Scripts/tiller-swift-test`
- `swift build`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Then launch the app and directly smoke-test the complete owner journey on the
target iPhone and iPad simulators before recording evidence and running
`tiller check task` plus the feature evaluation. Do not narrow a failing suite
away; distinguish implementation failure, test pollution, and unavailable
simulator capability with captured output.

## Edge cases

- Row actions and row selection must not dispatch together from one gesture.
- A detail presentation survives roster sorting changes because it holds stable
  habit identity, not an index.
- If the habit is deleted externally while detail is presented, dismiss safely
  to the roster without dereferencing an invalid model.
- Back during an in-flight operation does not duplicate or silently cancel a
  persisted write.
- Fixture seeding is idempotent across relaunch and isolated from production and
  every other named UI-test store.
- Current calendar month, weekday, locale, DST, and simulator time zone can vary
  without invalidating fixture relationships or owner-visible assertions.
- iPad remains the same full-screen flow with readable centered content and no
  sidebar.
- Larger text may stack metadata and stats but cannot clip Back, Edit, recent
  entries, lifecycle action, or the last scrollable content behind a safe area.
