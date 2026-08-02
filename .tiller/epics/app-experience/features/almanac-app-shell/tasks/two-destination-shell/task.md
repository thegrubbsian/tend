# Build accessible Today and Habits shell navigation

## Approach

Build the final root shell on the application composition from
app-experience/almanac-app-shell/ios-application-composition (T-9vxtaq) and the
visual APIs from app-experience/almanac-app-shell/almanac-foundations
(T-bil50m). Keep navigation state local to the shell; do not add a router,
navigation coordinator, persisted preference, or model query for two sibling
destinations.

Define:

- `enum ShellDestination: String, CaseIterable, Identifiable` with `.today` and
  `.habits`.
- `AlmanacShellView` with `@State` selection initialized to `.today`.
- `TodayDestinationChrome` accepting an injectable `Date` for deterministic
  previews and tests while production uses the owner's current local date.
- `HabitsDestinationChrome`.
- `FloatingTabPill(selection:)`.

`TendRootView` renders `AlmanacShellView` inside the production model-container
environment established by `TendApp`. The shell uses a switch over the selected
destination rather than retaining duplicate hidden screens. Scene
backgrounding leaves the shell instance and selection intact. Process
termination recreates the shell and therefore returns to Today; do not use
`SceneStorage`, `AppStorage`, or SwiftData for selection.

The destination chrome is intentionally complete at this feature's boundary:

- Today formats the owner's local date as localized weekday, middle dot, and
  localized month/day, then applies locale-aware uppercase and Almanac tracking;
  the serif title is “Today”. Do not include the year.
- Habits uses the serif title “Habits”.
- Both fill the screen with paper, respect safe areas, use 20-point horizontal
  padding, center content at a 600-point maximum on regular width, and leave a
  real unadorned content region for dependent features.

No destination may show placeholder words, sample habits, a disabled add
button, empty-state copy, dashboard cards, roster rows, or a navigation action.
app-experience/habit-management and app-experience/today-dashboard add those
bodies after this feature.

Place `FloatingTabPill` with `safeAreaInset(edge: .bottom)` so destination
content never falls beneath it. On compact width it keeps at least 21-point
horizontal and bottom insets and follows the available width. On regular width,
center it at a 360-point maximum—the 402-point phone board minus its two
21-point margins—rather than stretching across the iPad. The pill is 62 points
high, radius 36,
paper-raised with the 1-point hairline, and has no shadow. It contains two equal
54-point active regions inside a 4-point inset.

Each tab is a SwiftUI `Button`. The active tab is a moss capsule with paper icon
and uppercase label. The inactive tab is transparent with ink-faint icon and
label. Today uses `AlmanacIcon.today`; Habits uses `list.bullet`. Each button:

- has at least a 44-point hit target;
- exposes “Today” or “Habits” as its VoiceOver label;
- adds `.isSelected` only when active;
- uses stable identifiers `shell.tab.today` and `shell.tab.habits`;
- updates selection without a custom animation.

The destination roots use `shell.destination.today` and
`shell.destination.habits` identifiers. Fixed pill geometry remains fixed while
labels scale through two larger Dynamic Type steps. Tighten internal spacing
before truncating, but do not ellipsize either label. Incidental system
transitions must honor Reduce Motion; no haptic belongs to shell navigation.

## Surfaces

- Create `App/Tend/Shell/ShellDestination.swift`.
- Create `App/Tend/Shell/AlmanacShellView.swift`.
- Create `App/Tend/Shell/FloatingTabPill.swift`.
- Create `App/Tend/Shell/TodayDestinationChrome.swift`.
- Create `App/Tend/Shell/HabitsDestinationChrome.swift`.
- Modify `App/Tend/TendRootView.swift` to install the final shell.
- Replace the launch-only UI smoke coverage with
  `App/TendUITests/AlmanacShellUITests.swift`; remove obsolete smoke tests rather
  than leaving overlapping assertions.
- Modify the Xcode project only if its groups are not filesystem-synchronized.
- Do not modify TendCore, Package.swift, the Pencil comp, persistence models, or
  domain operations.

## Tests

Write failing UI tests before the final shell exists. The suite must launch a
fresh process and assert Today's destination and tab are present, Today is
selected, Habits is not selected, and the native tab-bar query is empty. Tap
Habits and assert the destination plus selected traits invert. Send the app to
the background and activate it to prove Habits remains selected. Terminate and
launch the process again to prove Today is selected.

Use identifiers for element lookup but assert owner-visible labels and selected
semantics as the contract. Do not assert Swift source, view type names, exact
hierarchy depth, or incidental animation timing.

Run:

- `Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests`
- `Scripts/tiller-xcode-test TendTests/TendApplicationModelTests`
- `Scripts/tiller-swift-test`
- `swift build`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination
  'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Then launch on a compact iPhone and iPad simulator and compare screenshots with
the Today and All Habits boards in `.tiller/design/comps/tend.pen`. Verify the
402-point comp maps to safe-area layout without fixed screen coordinates, the
pill remains 62 points with 21-point minimum insets, iPad content and pill are
centered, and
no native tab chrome or shadow appears.

Manually check default Dynamic Type plus two larger steps, VoiceOver labels and
selected state, 44-point targets, deep-variant contrast, forced light
appearance while the simulator is dark, and Reduce Motion. Record these
observations as feature-gate evidence; never attest them on the human's behalf.

## Edge cases

- Background/foreground must preserve selection; only constructing a new shell
  resets it.
- iPad split width and landscape use the same two destinations and centered
  maximum width, not a sidebar or stretched pill.
- Home-indicator and keyboard safe areas may move the pill but must not cover
  destination chrome.
- Extra-large text must not change button ordering, clip icons, or make labels
  ambiguous.
- VoiceOver focus follows the newly selected destination without making the
  entire pill one combined control.
- The custom sprout and list symbol use the same apparent weight and alignment.
- The local date eyebrow follows the owner's locale, calendar, and time zone;
  it never uses fixed UTC formatting.
- Destination switching performs no SwiftData fetch, save, network request,
  notification work, haptic, or analytics event.
