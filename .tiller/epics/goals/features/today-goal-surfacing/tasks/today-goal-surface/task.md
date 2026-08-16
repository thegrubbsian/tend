# Render and verify the Today Goals section

## Approach

Build the conditional section on
goals/today-goal-surfacing/today-goal-presentation (T-g3o7wd). Start with
`TodayGoalSurfacingUITests`, then extend only the existing Today destination and
deterministic fixture composition. Do not create a second Today screen,
navigation route, or goal progress component.

Wire the production Goal `@Query` into `TodayModel` beside the existing habit
query. Feed both queries, Timeline date, scene phase, and environment context
through the one established refresh path. Rebuild the single
`LocalDayTimelineSchedule` when the model's earliest Goal transition changes;
presentation assignment must not retrigger a refresh loop.

Render GOALS after TO TEND/TENDED content in `TodayView`. Omit the complete
section for an empty Goal-row collection. For each successful row:

- show exact owner name and kind-specific progress text;
- reuse `GoalProgressView` for an Accumulate track or Measure span and pace tick;
- show localized deadline plus explicit on-pace, behind, or past-due text;
- apply moss, accessible ochre, or withered Almanac treatment;
- combine the complete facts into one accessibility element and silence
  decorative geometry.

Render unavailable rows with recoverable name, neutral progress, explicit
unavailable facts, concise error, and one 44-point retry control. Goal cards
remain informational: no tap gesture, button trait, detail navigation, progress
sheet, closure action, haptic, or logging affordance.

Compose GOALS below first-launch, inactive-only, mixed, unresolved, and tended
habit bodies without changing their rows or header fraction. Suppress `All
tended.` when GOALS is nonempty; restore it after the last Goal leaves if every
habit still qualifies. Leave the Goals tab as the route to detail and mutation.
Do not render the Journal card or fourth tab shown in the eventual Pencil board.

Extend the existing DEBUG-only file-backed fixture registry rather than adding
another persistence architecture. Reuse Goal-experience seeding helpers and
public domain operations to provide stable Today-specific stores:

- mixed habits plus behind Accumulate, near on-pace Measure, and past-due Goal;
- valid distant, no-deadline, harvested, and let-go siblings that stay absent;
- all-tended habits with one eligible Goal;
- first-launch/no-habit and inactive-habit bodies with eligible Goals;
- one unavailable Goal with valid siblings;
- a mutation journey whose progress, edit, closure, reopening, and deletion
  move exact persistent identities into or out of Today.

Use one injected instant, calendar, TimeZone, and Locale for seeding and launch.
The malformed fixture may corrupt only one otherwise valid Goal after public
creation. Fixtures remain unreachable from release, preview, or ordinary launch
and never reseed a named store on relaunch.

## Surfaces

- Modify `App/Tend/Shell/TodayDestinationChrome.swift` only for Goal query/model
  wiring and the existing schedule input.
- Modify `App/Tend/Today/TodayView.swift` for the conditional GOALS section and
  unavailable retry.
- Reuse `App/Tend/Goals/GoalProgressView.swift`.
- Modify the DEBUG Goal or Today UI-test fixture and
  `App/Tend/Application/TendUITestStore.swift` only to add explicit named
  Today-Goal variants through existing dispatch.
- Create `App/TendUITests/TodayGoalSurfacingUITests.swift`.
- Modify focused Today/Goals UI tests only where combined-state assertions
  belong.
- Modify the Xcode project only if synchronized groups do not discover the new
  file.
- Attach deterministic screenshots and Tiller evidence during acceptance; do
  not hand-edit machine-owned gate state.
- Do not modify TendCore, goal forms/detail/roster semantics, habit cards,
  logging, reminder routing, Almanac tokens, Journal, or the Pencil file.

## Tests

Bind feature criterion C3 to `TodayGoalSurfacingUITests`.

Launch independent named stores and assert exact section order, Goal order,
owner-visible Accumulate/Measure/past-due facts, deadline and standing text,
pace treatment, absent ineligible/closed names, unchanged habit fraction, and
omitted empty GOALS heading. Cover first-launch plus Goals, inactive-only plus
Goals, all habits met with a Goal suppressing `All tended.`, and the line
returning when the final Goal leaves.

Exercise the real Goals tab/detail operations to append progress, edit a
deadline, harvest, reopen, and delete; return to Today and verify the exact
persistent row enters, remains, moves, or disappears without duplicates.
Relaunch the same store without reset and prove facts and eligibility persist.

The failure fixture must show valid siblings plus one named unavailable card and
working retry, with no false progress, `All tended.`, notification request, or
silent omission. Assert successful Goal cards are not buttons and expose no
tap/action; retry is the only GOALS control.

Run:

- `Scripts/tiller-xcode-test TendUITests/TodayGoalSurfacingUITests`
- `Scripts/tiller-xcode-test TendUITests/TodayDashboardUITests`
- `Scripts/tiller-xcode-test TendUITests/GoalExperienceUITests`
- `Scripts/tiller-xcode-test TendUITests`
- `Scripts/tiller-xcode-test TendTests/TodayGoalModelTests`
- `Scripts/tiller-xcode-test TendTests/TodayGoalRefreshTests`
- `Scripts/tiller-xcode-test TendTests`
- `Scripts/tiller-swift-test`
- `swift build`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination
  'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- `swift format lint --recursive --strict Sources Tests App`

After command gates pass, launch compact iPhone and centered iPad states against
the `Today v2` board in
`/Users/jcgrubbs/dev/tend-design/comps/tend.pen`. Repeat mixed and failure states
at two larger Dynamic Type steps. Inspect VoiceOver order and complete card
facts, GOALS heading, decorative silence, retry traits, contrast, forced light,
Reduce Motion, scroll reachability, safe area, and floating-pill clearance.
Record evidence without attesting the human manual gate.

## Edge cases

- The eventual four-tab comp is reference context; this feature renders only
  the functional Today, Goals, and Habits tabs supplied by its prerequisite.
- Long names, owner units, large integers, deadline text, and standing wrap
  before covering the progress visual or pill.
- GOALS may be the only needful content while the first-launch or inactive
  habit body remains visible.
- A Goal that returns on pace but remains within seven days stays; the test must
  not expect pace alone to remove it.
- An over-target unclosed Goal keeps truthful text and may remain near-deadline
  or past due.
- Pixel screenshots cannot attest VoiceOver speech, notification absence,
  persistence, or action dispatch; pair them with focused test evidence and
  record manual limitations honestly.
