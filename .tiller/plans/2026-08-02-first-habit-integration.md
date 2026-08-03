# First-Habit Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete app-experience/habit-management/first-habit-integration (T-94vmmx) with a persisted zero-habit Today flow, deterministic file-backed UI-test composition, one complete owner journey, and device/accessibility evidence.

**Architecture:** Today reads the shared SwiftData context directly with `@Query<Habit>` and owns only the zero-count body plus presentation of the existing `HabitFormView(mode: .new)`. DEBUG composition recognizes explicit UI-test launch arguments and opens a validated named file store under Application Support/TendUITests; release composition references only `TendModelContainer.production`. A single `HabitManagementUITests` journey exercises the owner contract against one named store, removes the reset argument before relaunch, and asserts owner-visible accessibility facts.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, TendCore, Swift Testing, XCTest/XCUITest, Xcode 26, iOS 26.

## Global Constraints

- Preserve the existing two-destination shell and Today selection ownership.
- Render exactly `Tend is a quiet place to grow the habits you want to keep.` and `Plant a habit` only when persisted Habit count is zero.
- Add no onboarding flag, `AppStorage`, one-time dismissal, nonempty Today placeholder, sample data, in-memory UI-test fallback, or direct SwiftData mutation from views.
- Keep UI-test launch handling inside `#if DEBUG`; release composition selects `TendModelContainer.production` without inspecting test arguments.
- A named UI-test store persists across relaunch without reset; reset deletes only that validated name's test directory.
- Reuse `HabitFormView(mode: .new)` and `HabitManagementOperations` for creation.
- Do not modify TendCore behavior, the persistence schema, Almanac tokens, Pencil comps, dashboard/detail/logging/reminder ownership, shell selection state, or distribution configuration.
- All owner actions remain reachable without swipe, all targets remain at least 44 points, appearance remains forced light, and Reduce Motion must not hide state.

---

### Task 1: Lock the complete owner journey in a failing UI contract

**Files:**
- Create: `App/TendUITests/HabitManagementUITests.swift`
- Preserve: `App/TendUITests/AlmanacShellUITests.swift`

**Interfaces:**
- Consumes: current identifiers `shell.tab.today`, `shell.tab.habits`, `shell.destination.today`, `habits.add`, and `habits.row.<UUID>`; field labels `Habit name`, `Target`, `Unit`; owner-visible Save, cadence, weekday, reminder, lifecycle, and deletion labels.
- Produces: launch arguments `-tend-ui-testing`, `-tend-ui-test-store <name>`, and optional `-tend-ui-test-reset`; one test `testCompleteFirstHabitOwnerJourney()`.

- [ ] **Step 1: Create one reset-once suite and launch helper**

```swift
final class HabitManagementUITests: XCTestCase {
  private let storeName = "HabitManagementUITests-owner-journey"

  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  private func launch(reset: Bool) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-tend-ui-testing",
      "-tend-ui-test-store", storeName,
    ] + (reset ? ["-tend-ui-test-reset"] : [])
    app.terminate()
    app.launch()
    return app
  }
}
```

- [ ] **Step 2: Assert cold Today and invalid New habit behavior**

In `testCompleteFirstHabitOwnerJourney()`, launch with reset, assert `today.empty` and the exact first-launch sentence, open `today.plant-habit`, then prove Save is disabled for an empty name, target `0`, and empty unit. Switch to Weekly, enable `Reminder, none`, assert `Reminder warning. No reminder will fire until a day is pinned.`, and assert Save becomes enabled once name/target/unit are valid despite zero pins.

- [ ] **Step 3: Create Daily and Weekly habits through real controls**

Create Daily `Read deliberately`, target `1`, unit `times`. Assert the Today introduction disappears without switching tabs. Open the Habits add action, create Weekly `Write field notes`, target `2`, unit `pages`, pin Monday and Wednesday, enable a reminder, and Save.

- [ ] **Step 4: Assert active roster facts and full streak units**

Locate rows by owner-visible labels and assert values include `1 time`, `Daily`, `0 days`, `Active` for the Daily habit and `2 pages`, `Weekly`, localized `Mon, Wed`, `0 weeks`, `Active` for the Weekly habit.

- [ ] **Step 5: Edit every mutable field while cadence is locked**

Open Edit from each row's non-swipe action surface. Assert `Cadence, Daily, locked` or `Cadence, Weekly, locked` and the exact locked explainer. Change both names, targets, units, reminder configuration, and weekly pins; Save and assert the new roster facts while cadence remains unchanged.

- [ ] **Step 6: Exercise lifecycle and both deletion branches**

Archive the weekly row and assert it moves to INACTIVE with `dormant`, `held at 0 weeks`, and `Inactive`; Reactivate and assert ACTIVE/`0 weeks`. Open deletion, assert the full consequence counts and `This can't be undone.`, Cancel, and prove the row remains. Reopen and confirm permanent deletion; prove the row disappears.

- [ ] **Step 7: Relaunch without reset and return to zero Today**

Terminate the app, set launch arguments without `-tend-ui-test-reset`, relaunch the same store, and assert the surviving edited Daily row and its facts. Delete it permanently, switch to Today, and assert `today.empty`, the exact sentence, and `Plant a habit` return.

- [ ] **Step 8: Record required screenshots inside the journey**

Attach screenshots named `First launch Today`, `New Habit`, `Weekly warning`, `All Habits`, `Edit Habit`, and `Delete confirmation` at the corresponding verified states using `XCTAttachment(screenshot:)` with `.keepAlways` lifetime.

- [ ] **Step 9: Run the suite and preserve the first truthful failure**

Run: `Scripts/tiller-xcode-test TendUITests/HabitManagementUITests`

Expected before implementation: the test builds, launches, and fails because `today.empty` and `Plant a habit` do not exist. Do not weaken the assertion or skip later journey steps.

- [ ] **Step 10: Commit the red contract**

```bash
git add App/TendUITests/HabitManagementUITests.swift
git commit -m "test: lock first habit owner journey"
```

---

### Task 2: Add deterministic DEBUG-only named file stores

**Files:**
- Create: `App/Tend/Application/TendUITestStore.swift`
- Modify: `App/Tend/TendApp.swift:10-16`
- Modify: `App/TendTests/TendApplicationModelTests.swift`

**Interfaces:**
- Produces: `TendUITestStore.containerFactory(arguments:fileManager:applicationSupportDirectory:) -> ModelContainerFactory?` under `#if DEBUG`.
- Consumes: `TendModelContainer.fileBacked(at:)` and the launch arguments from Task 1.
- Invariant: absence of `-tend-ui-testing` returns `nil`; presence with missing/invalid store name returns a throwing factory, never production or in-memory storage.

- [ ] **Step 1: Add failing startup composition tests**

Add tests to `TendApplicationModelTests` proving:

```swift
@Test("UI test stores persist by name until explicitly reset")
func uiTestStorePersistsByNameUntilExplicitReset() throws

@Test("resetting one UI test store preserves every other store")
func uiTestStoreResetIsNameScoped() throws

@Test("invalid UI test configuration cannot fall through to production")
func invalidUIStoreConfigurationThrows() throws
```

Use a unique temporary Application Support directory, create habits only through `HabitManagementOperations`, release the first container before reopening, fetch `Habit` with `FetchDescriptor`, and remove the temporary root in `defer`.

- [ ] **Step 2: Run startup tests and verify the missing type fails compilation**

Run: `Scripts/tiller-xcode-test TendTests/TendApplicationModelTests`

Expected: compile failure naming missing `TendUITestStore`.

- [ ] **Step 3: Implement strict argument parsing and scoped reset**

Implement a DEBUG-only type with these constants and behaviors:

```swift
#if DEBUG
enum TendUITestStore {
  static let enabledArgument = "-tend-ui-testing"
  static let nameArgument = "-tend-ui-test-store"
  static let resetArgument = "-tend-ui-test-reset"

  static func containerFactory(
    arguments: [String],
    fileManager: FileManager = .default,
    applicationSupportDirectory: URL? = nil
  ) -> ModelContainerFactory?
}
#endif
```

Accept store names containing only ASCII letters, digits, `-`, and `_`. Resolve `<Application Support>/TendUITests/<name>/Tend.store`. On explicit reset remove only `<name>`, then recreate it. Missing, duplicate, empty, or invalid names produce a factory that throws a localized configuration error. The returned factory calls `TendModelContainer.fileBacked(at:)`; it never seeds rows or catches the open error.

- [ ] **Step 4: Compile-gate test composition in TendApp**

```swift
init() {
  #if DEBUG
  let makeContainer = TendUITestStore.containerFactory(
    arguments: ProcessInfo.processInfo.arguments
  ) ?? TendModelContainer.production
  #else
  let makeContainer: ModelContainerFactory = TendModelContainer.production
  #endif
  _applicationModel = State(initialValue: TendApplicationModel(makeContainer: makeContainer))
}
```

This leaves release code with no test-argument branch and preserves the existing once-only open in `TendApplicationModel`.

- [ ] **Step 5: Run startup tests and prove persistence/reset isolation passes**

Run: `Scripts/tiller-xcode-test TendTests/TendApplicationModelTests`

Expected: all startup and UI-test store tests pass.

- [ ] **Step 6: Commit file-store composition**

```bash
git add App/Tend/Application/TendUITestStore.swift App/Tend/TendApp.swift App/TendTests/TendApplicationModelTests.swift
git commit -m "test: add named persisted UI stores"
```

---

### Task 3: Install the zero-habit Today body

**Files:**
- Modify: `App/Tend/Shell/TodayDestinationChrome.swift`
- Modify: `App/Tend/Habits/HabitRosterView.swift:94-110`

**Interfaces:**
- Consumes: shared environment `ModelContext`, `Habit`, and `HabitFormView(mode: .new)`.
- Produces: identifiers `today.empty` and `today.plant-habit`; roster add VoiceOver label `New habit` while retaining identifier `habits.add`.

- [ ] **Step 1: Add direct persisted-count rendering**

Import SwiftData and TendCore, add `@Query private var habits: [Habit]`, and add `@State private var isPresentingNewHabit = false`. Keep the date eyebrow and Today title unchanged. When `habits.isEmpty`, place one introduction block below the title:

```swift
VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
  Text("Tend is a quiet place to grow the habits you want to keep.")
    .almanacTextStyle(.body)
    .fixedSize(horizontal: false, vertical: true)

  Button("Plant a habit") {
    isPresentingNewHabit = true
  }
  .buttonStyle(AlmanacPrimaryButtonStyle())
  .accessibilityHint("Opens a new habit form.")
  .accessibilityIdentifier("today.plant-habit")
}
.accessibilityIdentifier("today.empty")
```

Present `HabitFormView(mode: .new)` with `.sheet(isPresented:)`. Do not add any body when the query is nonempty; the existing title and spacer remain.

- [ ] **Step 2: Align roster add accessibility copy**

Change only the roster add control's VoiceOver label from `Add habit` to `New habit`. Keep its stable `habits.add` identifier and existing 44-point target.

- [ ] **Step 3: Run the UI journey through first creation**

Run: `Scripts/tiller-xcode-test TendUITests/HabitManagementUITests`

Expected: cold Today, New form, invalid-field, valid warning, and first-save assertions pass; continue fixing only concrete journey failures without adding a second state owner.

- [ ] **Step 4: Commit Today integration**

```bash
git add App/Tend/Shell/TodayDestinationChrome.swift App/Tend/Habits/HabitRosterView.swift
git commit -m "feat: add persisted first habit flow"
```

---

### Task 4: Stabilize the full persisted journey and shell regressions

**Files:**
- Modify: `App/TendUITests/HabitManagementUITests.swift`
- Modify: `App/TendUITests/AlmanacShellUITests.swift`
- Modify application/form/roster sources only for observed owner-contract failures.

**Interfaces:**
- Consumes: named-store arguments, Today identifiers, existing form labels, row identifiers and values, context menus/accessibility actions.
- Produces: deterministic reset/relaunch helpers shared conceptually but not through a new production abstraction.

- [ ] **Step 1: Move shell tests off in-memory launch composition**

Give each shell test a stable, suite-scoped store name and launch with explicit reset. Before any same-test relaunch that must preserve state, remove `-tend-ui-test-reset`. Preserve all current Today/Habits selection assertions and the existing roster smoke journey.

- [ ] **Step 2: Make field editing deterministic without implementation assertions**

Use accessible field labels and select-all replacement through XCUI keyboard commands or repeated delete only after the field is focused. Assert enabled/disabled Save state, owner-visible field errors, reminder warning copy, cadence locked labels, and saved row values; do not assert SwiftUI hierarchy depth.

- [ ] **Step 3: Use non-swipe lifecycle and deletion affordances**

Exercise the row context menu for Edit, Archive/Reactivate, and Delete in the integration journey. Keep existing swipe coverage in `AlmanacShellUITests` as a separate contract. Assert confirmation title, complete consequence, reversible archive alternative for active rows, already-archived explanation for inactive rows, and Cancel behavior.

- [ ] **Step 4: Run the complete integration suite until green**

Run: `Scripts/tiller-xcode-test TendUITests/HabitManagementUITests`

Expected: one complete journey passes from reset through persisted relaunch and final zero-habit Today.

- [ ] **Step 5: Run shell regressions**

Run: `Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests`

Expected: every shell and roster smoke test passes against isolated named file stores.

- [ ] **Step 6: Commit journey stabilization**

```bash
git add App/TendUITests/HabitManagementUITests.swift App/TendUITests/AlmanacShellUITests.swift App/Tend
git commit -m "test: prove complete persisted habit journey"
```

---

### Task 5: Capture compact, iPad, Dynamic Type, and accessibility evidence

**Files:**
- Modify only concrete UI sources when direct observation exposes a contract failure.
- Evidence source: Xcode `.xcresult` screenshots and direct simulator accessibility hierarchy.

**Interfaces:**
- Consumes: the single journey's launch/store arguments and screenshot names.
- Produces: observed evidence for layout, text wrapping, controls, appearance, and Reduce Motion; no manual attestation.

- [ ] **Step 1: Run compact iPhone at default and two larger sizes**

Use an iOS 26 compact iPhone simulator. Run the journey at default, `accessibility-medium`, and `accessibility-extra-extra-extra-large`. Check that the long edited habit name wraps, fields and actions remain reachable, the keyboard does not cover Save or Reminder, and the floating tab pill does not cover the last row/action.

- [ ] **Step 2: Run centered iPad at default and two larger sizes**

Use an iOS 26 iPad simulator with default, `accessibility-medium`, and `accessibility-extra-extra-extra-large`. Confirm the same two-destination shell, centered `AlmanacMetrics.readableContentWidth`, no sidebar, and no edge-to-edge stretched rows/forms.

- [ ] **Step 3: Inspect the six required captured states**

Export and inspect `First launch Today`, `New Habit`, `Weekly warning`, `All Habits`, `Edit Habit`, and `Delete confirmation`. Compare paper surfaces, New York/serif and tracked-label typography, moss/clay/ochre/withered state colors, spacing, pinned-day circles, absence of shadows/alarm red/native Form chrome, and readable maximum width.

- [ ] **Step 4: Inspect accessibility hierarchy and action reachability**

Verify VoiceOver-visible labels/hints/values for Today add, roster add, Name/Target/Unit, Daily/Weekly, all weekdays and selected traits, Reminder and warning, locked cadence and exact explanation, full day/week streak phrases, Edit, Archive/Reactivate, Delete, Cancel, confirmation consequence, and retry controls. Verify every actionable frame is at least 44 by 44 points.

- [ ] **Step 5: Verify forced light and Reduce Motion**

Run once with dark system appearance and confirm the app remains light. Enable Reduce Motion and repeat creation, section movement, sheet dismissal, and deletion; confirm state remains clear without animation dependence.

- [ ] **Step 6: Commit only evidence-driven fixes**

If observation required source changes, commit those exact files with `fix: preserve habit management adaptation`. If no source change was needed, record the observation in the final run notes without creating an evidence-only source file.

---

### Task 6: Run the complete contract and submit the task

**Files:**
- Verify every changed source and test.
- Tiller updates: `.tiller/board.md`, the task ledger, and generated event files.

**Interfaces:**
- Consumes: app-experience/habit-management/first-habit-integration (T-94vmmx) implementation.
- Produces: green task gates, an open task PR, and Tiller state `in_review`.

- [ ] **Step 1: Run required focused suites**

```bash
Scripts/tiller-xcode-test TendUITests/HabitManagementUITests
Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests
Scripts/tiller-xcode-test TendTests/HabitFormModelTests
Scripts/tiller-xcode-test TendTests/HabitRosterModelTests
Scripts/tiller-xcode-test TendTests/TendApplicationModelTests
Scripts/tiller-swift-test
swift build
xcodebuild -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

- [ ] **Step 2: Review the final diff and request independent review**

Check every changed file against the task surfaces and non-goals. Reject any sample data, production test-argument branch, onboarding state, nonempty Today placeholder, direct model mutation, unstable UI assertion, or unowned project-file churn. Request a focused code review and fix every correctness finding.

- [ ] **Step 3: Run and commit Tiller task gates**

```bash
tiller check task T-94vmmx
git add .tiller
git commit -m "chore: check first-habit integration"
```

- [ ] **Step 4: Push, open the task PR, and submit**

Push `tiller/app-experience/habit-management`, run `gh pr create --base main --head tiller/app-experience/habit-management`, read the returned PR URL, and pass its numeric suffix to `tiller submit task T-94vmmx --pr`. Commit and push the generated `.tiller` review-state delta before the human merges.

- [ ] **Step 5: Render the execution seam**

Run `tiller readout execute`, reproduce it verbatim, append only factual notes from this run, and stop at `in_review` without attesting any human gate.
