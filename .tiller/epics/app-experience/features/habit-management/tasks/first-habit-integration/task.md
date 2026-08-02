# Integrate first-habit management flows

## Approach

Complete the feature on app-experience/habit-management/all-habits-roster
(T-ogl6he). Add the zero-habit Today body, deterministic file-backed UI-test
composition, end-to-end UI coverage, and final device/layout evidence without
changing the shell's two-destination ownership.

Query the shared model context inside Today. When the Habit count is zero,
render exactly one body sentence—`Tend is a quiet place to grow the habits you
want to keep.`—and one filled moss `Plant a habit` action beneath the existing
date/title chrome. Present the same `HabitFormView` in New mode. A successful
save removes the introduction immediately. Deleting the last habit restores it;
derive this only from persisted Habit count, with no onboarding flag,
`AppStorage`, or one-time dismissal state.

When at least one Habit exists, leave the Today body intentionally available to
app-experience/today-dashboard. Do not add cards, progress, sample copy, a
spinner, a disabled placeholder, or a second empty-state message.

Add DEBUG-only launch configuration for UI tests that chooses a named,
file-backed TendCore container under a test-only application directory and can
reset that named store before launch. The same name must persist across process
relaunch when reset is absent. Production launch continues to call
`TendModelContainer.production()` exactly once and cannot observe test
arguments. Do not seed Habit rows, use an in-memory fallback, or bypass
`HabitManagementOperations`.

Create a single UI suite that starts from a reset empty store and exercises the
complete owner flow through accessible controls:

1. cold launch on Today, read the first-launch sentence, open New habit;
2. prove invalid name/target/unit cannot Save and the Weekly no-pin reminder
   warning does not block a valid Save;
3. create one Daily and one Weekly habit, including pins and a reminder;
4. switch to Habits and verify active section facts, requirement/cadence/pins,
   and streak units;
5. Edit both forms, prove cadence is locked, and save every mutable field;
6. Archive and Reactivate, verifying section and dormant/held copy after each;
7. cancel deletion and prove the habit/history remains;
8. confirm permanent deletion and prove the row is gone;
9. terminate/relaunch the same store and prove surviving data persists; and
10. delete the final habit, return to Today, and observe the zero-habit body.

Use identifiers for reliable lookup but assert owner-visible labels, values,
traits, warnings, confirmation consequence, and persisted relaunch behavior.
Do not assert exact view depth, source symbols, animation timing, or debug-only
implementation details.

Exercise compact iPhone and centered iPad layouts at default and two larger
Dynamic Type sizes. Compare against All Habits and Edit Habit comp boards.
Check keyboard avoidance, tab-pill clearance, long-name wrapping, absence of
shadows/alarm red/native Form chrome, and readable maximum width. Use VoiceOver
to exercise the add/form/day/row/confirmation/retry controls, including Edit,
Archive/Reactivate, and Delete without relying on swipe. Verify 44-point
targets, selected day traits, locked cadence explanation, full streak phrases,
forced light appearance, and Reduce Motion. Record observations as feature-gate
evidence; never attest manual criteria for the human.

## Surfaces

- Modify `App/Tend/Shell/TodayDestinationChrome.swift` or add a focused Today
  zero-habit body source under `App/Tend/Habits/`.
- Modify app composition only as needed for DEBUG-only named file-backed
  UI-test stores while preserving production behavior.
- Create `App/TendUITests/HabitManagementUITests.swift`.
- Modify `App/TendUITests/AlmanacShellUITests.swift` only if deterministic store
  isolation is required; preserve all existing shell contracts.
- Modify `Tend.xcodeproj` only if filesystem-synchronized groups do not include
  new sources automatically.
- Do not modify the Pencil comp, Almanac tokens, TendCore behavior, shell
  selection model, dashboard/detail/logging/reminder implementations, or
  distribution configuration.

## Tests

Write the UI suite before installing the Today body/integration hooks and
observe the first contract fail. Keep test data isolated by a unique named
file-backed store and reset only at explicit suite setup. No test may depend on
the developer's production store, simulator residue, ordering from another
test, or sample fixtures compiled into the app.

Run:

- `Scripts/tiller-xcode-test TendUITests/HabitManagementUITests`
- `Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests`
- `Scripts/tiller-xcode-test TendTests/HabitFormModelTests`
- `Scripts/tiller-xcode-test TendTests/HabitRosterModelTests`
- `Scripts/tiller-xcode-test TendTests/TendApplicationModelTests`
- `Scripts/tiller-swift-test`
- `swift build`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination
  'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Then launch and directly exercise the complete flow on a compact iPhone and
iPad simulator. Capture screenshots for All Habits, New Habit, Edit Habit,
weekly warning, delete confirmation, and first-launch Today. Run the
accessibility/adaptation pass described above and attach concrete observations
to the task/feature gates.

## Edge cases

- A failed store open still uses the existing honest startup failure surface;
  it never shows the zero-habit state.
- Resetting one UI-test store cannot delete another test store or production
  data.
- Relaunch without reset preserves the created/edited state; launch with reset
  is deterministically empty.
- Deleting the last Habit while Today is not selected still causes Today to show
  first-launch content when selected.
- Creating the first Habit from Today dismisses the form and removes only the
  zero-habit body; it does not switch destinations.
- Background/foreground and process relaunch retain the shell behavior from
  Almanac App Shell.
- iPad uses the same flows and no sidebar; keyboard and floating pill never
  cover the last form field or action.
- Dynamic Type wrapping never truncates owner-written names or hides row actions
  from VoiceOver.
