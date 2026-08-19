# Render and route the Today Journal invitation

## Approach

Feed the production Journal query through `TodayDestinationChrome` into the
single Today refresh path. Render a conditional `JOURNAL` section after every
Habit and Goal section. Its raised card has one card-wide action and concise
today-writing copy; the unavailable variant replaces that action with Retry.
Omit the entire section when today's durable entry exists.

Route the action through the shell and Journal routing model established by
`journal/journal-experience`; select Journal and request today's exact
`LocalDate` editor without constructing an editor or mutation operation in
Today. Preserve state during tab changes and make repeated route requests
idempotent.

Build deterministic DEBUG fixtures for eligible, complete, unavailable,
first-launch, inactive-only, all-tended, relaunch, and real Journal mutation
journeys. Reuse existing Today and Journal fixture composition instead of
adding a second app launch path.

## Surfaces

- `App/Tend/Shell/TodayDestinationChrome.swift`
- Existing shell and Journal routing models under `App/Tend/Shell` and
  `App/Tend/Journal`
- `App/Tend/Today/TodayView.swift`
- `App/Tend/Application/TendUITestStore.swift` and a focused Journal fixture
- `App/TendUITests/TodayJournalInvitationUITests.swift`
- `App/TendUITests/TodayJournalMutationJourneyUITests.swift`

## Tests

Start with failing UI contracts for exact section ordering, omitted heading,
single action, unavailable retry, accessibility label/hint, Dynamic Type-safe
growth, and floating-pill clearance. Prove the card opens today's editor,
saving removes it, deleting restores it, relaunch preserves the result, and no
duplicate entry or route appears. Re-run existing Today dashboard, Goal
surfacing, fast logging, shell, reminder, and first-launch UI suites.

## Edge cases

The card must remain hittable and untruncated with long localized copy and two
larger Dynamic Type sizes. VoiceOver sees one action, not nested decorative
elements. Do not show yesterday, progress, status, streak, dismissal, reminder,
or notification controls. A Journal failure card may retry only Journal
projection and must retain all valid sibling content and current logging state.
