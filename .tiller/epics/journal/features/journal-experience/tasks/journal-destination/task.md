# Assemble the complete Journal destination

## Approach

Add Journal as the fourth `ShellDestination`, after Habits, with its Almanac
book symbol, tab identifier, accessibility focus, and selected capsule.
Implement `JournalDestinationChrome` with production Journal and Habit queries,
one local-day timeline schedule, and the established shell routing model.

Compose the tested overview, editor, entry prose, binary month garden, live
Habit garden, retry states, and deletion flow into one Journal surface. Use the
Journal reference board for layout and existing Almanac tokens/components for
type, color, spacing, cells, raised pages, keyboard avoidance, and floating-pill
clearance. Do not introduce native TabView, NavigationStack persistence, a
second query model, search, or placeholder screens.

Create deterministic DEBUG fixtures for empty, today-written, yesterday
back-fill, old editable, legal/forbidden delete, multiple months, empty body,
load failure, save failure/retry, Habit mutation, large Dynamic Type, and
relaunch journeys.

## Surfaces

- `App/Tend/Shell/ShellDestination.swift`
- `App/Tend/Shell/FloatingTabPill.swift`
- `App/Tend/Shell/AlmanacShellView.swift`
- New production composition under `App/Tend/Journal`
- `App/Tend/Application/TendUITestStore.swift` and Journal fixtures
- `App/TendUITests/AlmanacShellUITests.swift`
- `App/TendUITests/JournalExperienceUITests.swift`

## Tests

Start with failing end-to-end UI contracts for the four-tab order, empty
invitation, automatic create/edit, yesterday back-fill, old edit, delete
authorization, reverse rows, first-line updates, month navigation, live garden,
truthful failures, VoiceOver order, keyboard clearance, backgrounding, and
relaunch. Run the complete app unit and UI suites after focused Journal tests.
Capture review screenshots for every normative Journal board state.

## Edge cases

Keep one visible root destination at a time and preserve shell selection during
backgrounding. Long prose, long first lines, localization, landscape, and two
larger Dynamic Type sizes must not truncate actions or put text behind the
keyboard or tab pill. Reduce Motion removes nonessential transitions. A query
failure keeps route identity recoverable and never substitutes empty history.
