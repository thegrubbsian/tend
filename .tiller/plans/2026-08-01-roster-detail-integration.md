# Roster Detail Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the approved Habit Detail destination into All Habits and prove the complete persisted owner journey with a deterministic DEBUG-only fixture, end-to-end UI coverage, and reviewable visual/accessibility evidence.

**Architecture:** `HabitRosterView` owns one optional selection keyed by the selected habit's SwiftData `PersistentIdentifier` and presents the existing `HabitDetailView` with `fullScreenCover`; the shell and detail model remain unchanged. `TendUITestStore` recognizes one reset-only `habit-detail` fixture, delegates seeding to a focused DEBUG-only source, and builds all state through public TendCore management, reconciliation, logging, lifecycle, streak, and detail-computation boundaries. One `HabitDetailUITests` suite owns the end-to-end journey, relaunch coverage, adaptive checks, and screenshot attachments.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, TendCore, Swift Testing, XCTest/XCUITest, Xcode 26, iOS 26 simulators, Tiller.

## Global Constraints

- Work only on `tiller/app-experience/habit-detail-history` in `.worktrees/habit-detail-history`; every authored commit message includes `T-0i5tqj`.
- Preserve roster New/Edit/Archive/Reactivate/Delete swipe actions, context menus, and VoiceOver custom actions.
- Present detail full screen from the Habits destination; do not add a router, shell destination, tab, sidebar, Today wiring, or competing tab pill.
- Selection uses SwiftData `PersistentIdentifier`, never row index or formatted name; sorting cannot change the selected owner.
- The fixture is compiled only under `#if DEBUG`, requires `-tend-ui-testing`, a valid named store, `-tend-ui-test-reset`, and the exact fixture value `habit-detail`.
- Seed from one captured launch instant in explicit `America/Los_Angeles` time, and set the UI-test process `TZ` to the same identifier.
- Seed model state only through public TendCore operations; never assign persisted model fields directly when an operation can produce the state.
- A non-reset relaunch omits both fixture and reset arguments, reuses the same named store, and cannot duplicate fixture data.
- Production and ordinary DEBUG launches cannot observe fixture arguments, fixture data, or a test clock.
- Assertions use accessibility identifiers for lookup but verify owner-visible labels, values, enabled/selected traits, callout facts, and persisted outcomes.
- Keep forced-light Almanac styling, Reduce Motion semantics, minimum 44-point controls, safe-area behavior, and owner-written wrapping unchanged.
- Store only extracted screenshots and `manifest.json` under `.tiller/evidence/roster-detail-integration/`; do not commit `.xcresult` bundles.
- Never attest feature criteria C5 or C6; evidence remains for the human gate.

---

### Task 1: Deterministic DEBUG Habit Detail Fixture

**Files:**
- Modify: `App/TendTests/TendApplicationModelTests.swift`
- Modify: `App/Tend/Application/TendUITestStore.swift`
- Create: `App/Tend/Application/HabitDetailUITestFixture.swift`

**Interfaces:**
- Consumes: `HabitManagementOperations.create`, `BucketReconciler.reconcile`, `LogEntryOperations.append`, `HabitActivityOperations.deactivate/reactivate`, `HabitStreakComputation.compute`, and `HabitDetailComputation.snapshot`.
- Produces: launch arguments `-tend-ui-test-fixture habit-detail`; `HabitDetailUITestFixture.seed(context:at:timeZone:)`; three stable owner-visible habits named `Daily garden`, `Weekly field notes`, and `Dormant reading`.

- [ ] **Step 1: Add failing fixture configuration tests**

Add Swift Testing cases proving fixture arguments fail closed before any store opens:

```swift
@Test("habit-detail fixture requires an enabled reset named store")
func habitDetailFixtureRequiresResetNamedStore() throws {
  let supportDirectory = try makeTemporarySupportDirectory()
  defer { try? FileManager.default.removeItem(at: supportDirectory) }

  for arguments in [
    ["Tend", "-tend-ui-test-fixture", "habit-detail"],
    ["Tend", "-tend-ui-testing", "-tend-ui-test-store", "fixture", "-tend-ui-test-fixture", "habit-detail"],
    ["Tend", "-tend-ui-testing", "-tend-ui-test-store", "fixture", "-tend-ui-test-reset", "-tend-ui-test-fixture", "unknown"],
  ] {
    let factory = try #require(
      TendUITestStore.containerFactory(
        arguments: arguments,
        applicationSupportDirectory: supportDirectory
      )
    )
    #expect(throws: (any Error).self) { _ = try factory() }
  }
}
```

- [ ] **Step 2: Add the failing graph and relaunch test**

Use a fixed `2026-08-03T12:00:00-07:00` launch instant and `America/Los_Angeles`. Open a reset fixture store through `TendUITestStore.containerFactory`, fetch habits ordered by name, and require exactly the three names. Project each habit through `HabitDetailComputation.snapshot` and assert:

```swift
#expect(Set(daily.history.map(\.state)).isSuperset(of: [.met, .missed, .inactive, .open, .grace, .future]))
#expect(daily.editableEntries.contains { $0.bucketKey == currentDailyKey })
#expect(daily.editableEntries.contains { $0.bucketKey == graceDailyKey })
#expect(weekly.cadence == .weekly)
#expect(weekly.history.contains { $0.state == .open })
#expect(inactive.isActive == false)
#expect(inactive.editableEntries.isEmpty)
```

Reopen the same store without `-tend-ui-test-reset` or `-tend-ui-test-fixture` and assert the habit count remains exactly three and every stable name appears once.

- [ ] **Step 3: Run the fixture tests and verify RED**

Run:

```bash
Scripts/tiller-xcode-test TendTests/TendApplicationModelTests
```

Expected: FAIL because `-tend-ui-test-fixture` is not parsed and `HabitDetailUITestFixture` does not exist. A configuration test that passes by silently ignoring the fixture is incorrect; tighten it until the failure names the missing fixture contract.

- [ ] **Step 4: Implement strict fixture parsing**

In `TendUITestStore` add:

```swift
static let fixtureArgument = "-tend-ui-test-fixture"

enum Fixture: String {
  case habitDetail = "habit-detail"
}
```

Extend `TendUITestStoreError` with missing/duplicate/unsupported fixture and fixture-requires-reset cases. Parse exactly zero or one fixture pair. Treat any fixture argument without `-tend-ui-testing` as `.missingEnabledArgument`; require a valid named store and exactly one reset flag before accepting a fixture. Add internal defaulted `now` and `fixtureTimeZone` inputs to `containerFactory` so tests can freeze the DEBUG-only composition while ordinary and release composition retain their existing call site.

Capture `let launchInstant = now()` once before returning the factory. After opening a freshly reset file-backed container, call only:

```swift
try HabitDetailUITestFixture.seed(
  context: container.mainContext,
  at: launchInstant,
  timeZone: fixtureTimeZone
)
```

when `.habitDetail` is selected.

- [ ] **Step 5: Seed the daily fixture through public operations**

In `HabitDetailUITestFixture.seed`, construct one Gregorian Monday-first calendar in the supplied zone and three operation objects from the supplied context. For `Daily garden` (`target: 2`, `unit: "times"`, daily cadence):

1. Create twelve local days before launch at local noon and append two to the creation bucket.
2. Append two eleven days before launch; reconcile without logging ten days before launch to create a final miss; append two nine and eight days before launch.
3. Deactivate seven days before launch at local noon, then reactivate four days before launch at local noon, leaving a true inactive gap.
4. Append two at four, three, and two days before launch.
5. Append one yesterday, append one to the current bucket at launch, then append a second entry to yesterday through `.periodKey(yesterday.key)`.
6. Compute the streak and snapshot once through public APIs to prove the graph is complete before returning.

This yields final met/missed facts, dormant periods, current open progress, a met grace bucket with two individually deletable entries, future facts, and pre-creation facts on the earlier selectable page. Deleting one grace entry later makes the current chain truthfully at risk.

- [ ] **Step 6: Seed weekly and inactive fixtures through public operations**

For `Weekly field notes` (`target: 2`, `unit: "pages"`, weekly cadence), create eight Monday buckets before the current week. Advance monotonically through weekly local-noon instants, append two to selected weeks, deliberately leave at least one final miss, append one to the previous grace week, and append one to the current week. Reconcile, compute streak, and snapshot the current month so boundary strips and final/open facts are guaranteed.

For `Dormant reading` (`target: 1`, `unit: "chapter"`, daily cadence), create eight days before launch, log three consecutive met days, then deactivate five days before launch. Compute the frozen streak and snapshot; require inactive state, dormant history, and zero editable entries. Do not reactivate during seeding.

- [ ] **Step 7: Verify GREEN and regression safety**

Run:

```bash
Scripts/tiller-xcode-test TendTests/TendApplicationModelTests
Scripts/tiller-swift-test Tests/TendCoreTests/History/HabitDetailComputationTests.swift
```

Expected: all named tests pass; reopening the store does not reseed or duplicate any habit.

- [ ] **Step 8: Commit the fixture slice**

```bash
git add App/Tend/Application/TendUITestStore.swift App/Tend/Application/HabitDetailUITestFixture.swift App/TendTests/TendApplicationModelTests.swift
git commit -m "Add deterministic detail fixture T-0i5tqj"
```

---

### Task 2: Stable Roster-to-Detail Presentation

**Files:**
- Create: `App/TendUITests/HabitDetailUITests.swift`
- Modify: `App/Tend/Habits/HabitRosterView.swift`
- Test: `App/TendUITests/HabitManagementUITests.swift`
- Test: `App/TendUITests/AlmanacShellUITests.swift`

**Interfaces:**
- Consumes: `HabitDetailView.init(habit:context:onBack:)`, `HabitRosterRow.id: PersistentIdentifier`, and the Task 1 fixture launch arguments.
- Produces: one `HabitRosterSelection` identified by `PersistentIdentifier`, default accessible row activation, and one `fullScreenCover(item:)` whose Back closure clears exactly that selection.

- [ ] **Step 1: Write the failing owner-visible navigation test**

Create `HabitDetailUITests` with a unique store name per test and a launch helper that sets `TZ=America/Los_Angeles`. Initial launch arguments are:

```swift
[
  "-tend-ui-testing",
  "-tend-ui-test-store", storeName,
  "-tend-ui-test-reset",
  "-tend-ui-test-fixture", "habit-detail",
]
```

The first test selects Habits, finds the `Daily garden` row by identifier prefix plus exact label, taps it, and requires:

```swift
XCTAssertTrue(element("habitDetail.title", in: app).waitForExistence(timeout: 5))
XCTAssertEqual(element("habitDetail.title", in: app).label, "Daily garden")
XCTAssertFalse(app.buttons["shell.tab.today"].exists)
XCTAssertFalse(app.buttons["shell.tab.habits"].exists)
```

Tap `habitDetail.back`, then require `shell.destination.habits`, the same row, and selected Habits shell state.

- [ ] **Step 2: Run the navigation test and verify RED**

Run:

```bash
Scripts/tiller-xcode-test TendUITests/HabitDetailUITests
```

Expected: FAIL waiting for `habitDetail.title`; the fixture row exists but is not selectable. A fixture/store startup failure is the wrong RED and must be fixed before proceeding.

- [ ] **Step 3: Add roster-owned stable selection**

In `HabitRosterView` retain the injected `ModelContext` and add:

```swift
@State private var selectedHabit: HabitRosterSelection?

private struct HabitRosterSelection: Identifiable {
  let id: PersistentIdentifier
  let habit: Habit
}
```

Apply a default tap/accessibility action to each complete row card, outside `HabitRosterActionsModifier`, which assigns the row's `PersistentIdentifier` and live habit only while that row has no mutation in flight. Do not wrap the card in a `Button`, because a streak-retry row can contain its own button and nested controls would corrupt semantics. Add `.accessibilityAddTraits(.isButton)` and an unnamed default `.accessibilityAction` for VoiceOver activation while retaining every established named custom action.

Present:

```swift
.fullScreenCover(
  item: $selectedHabit,
  onDismiss: { refresh(at: .now) }
) { selection in
  HabitDetailView(habit: selection.habit, context: context) {
    selectedHabit = nil
  }
}
```

After each synchronous roster refresh, clear the selection only when neither active nor inactive rows contains its `PersistentIdentifier`. This safely dismisses a detail whose habit was deleted externally and never resolves by row index, order, name, or ordinary UUID. The cover's `onDismiss` refresh makes detail-originated Edit/Archive/Reactivate state visible in the roster without adding cross-model callbacks.

- [ ] **Step 4: Verify navigation GREEN and management regressions**

Run:

```bash
Scripts/tiller-xcode-test TendUITests/HabitDetailUITests
Scripts/tiller-xcode-test TendUITests/HabitManagementUITests
Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests
```

Expected: detail covers the shell, Back returns to the same roster, and existing swipe/context/custom actions still dispatch without also presenting detail. If SwiftUI changes the XCUI element type, update existing `habitRow` helpers to query `app.descendants(matching: .any)` while preserving the `habits.row.` identifier and exact owner-visible label predicate.

- [ ] **Step 5: Add sorting/deletion safety coverage at the observable seam**

Extend the UI test to archive a different row through its established row action while Daily detail selection is not active, then reopen Daily and verify the same title. Add a model-level regression only if implementing external deletion requires production logic outside the view's post-refresh identity check; otherwise the full-screen dismissal and existing detached-habit model tests are the complete observable coverage.

- [ ] **Step 6: Commit the navigation slice**

```bash
git add App/Tend/Habits/HabitRosterView.swift App/TendUITests/HabitDetailUITests.swift App/TendUITests/HabitManagementUITests.swift App/TendUITests/AlmanacShellUITests.swift
git commit -m "Present roster detail journey T-0i5tqj"
```

Only add existing UI-test files to the commit if their helpers actually changed.

---

### Task 3: Complete Persisted Owner Journey UI Contract

**Files:**
- Modify: `App/TendUITests/HabitDetailUITests.swift`
- Modify only when a failing owner contract proves it necessary: `App/Tend/Habits/HabitDetailView.swift`
- Modify only when a failing state contract proves it necessary: `App/Tend/Habits/HabitDetailModel.swift`

**Interfaces:**
- Consumes: existing `habitDetail.*` identifiers and owner-visible accessibility labels from `HabitDetailView`.
- Produces: one end-to-end test covering daily, weekly, inactive, mutation, bounds, relaunch, and shell-return behavior; screenshot attachments for required states.

- [ ] **Step 1: Add reusable owner-visible query helpers**

Keep helpers private to `HabitDetailUITests`: `element(_:in:)` queries descendants by exact identifier; `habitRow(named:in:)` matches `identifier BEGINSWITH "habits.row." AND label == name`; `historyButton(state:in:)` matches `identifier BEGINSWITH "habitDetail.history." AND label CONTAINS state`; `assertMinimumHitRegion`; `replaceText`; `recordScreenshot`. Helpers may locate with identifiers but every test assertion must check labels, values, enabled/selected traits, or persisted state.

- [ ] **Step 2: Prove daily facts and exact callouts**

On `Daily garden`, assert exact title, metadata fragments (`2 times`, `Daily`), current/best labels with day units, current month label, legend label `Legend. Met, Missed, Open`, and at least one recent-entry delete control with a complete owner-visible accessibility label.

On the current month select Open, Grace, and Future facts. Move to the prior month and select Met, Missed, and Inactive. Move to the earliest month and select Before creation. For each state, tap the matching real bucket, require `.isSelected`, and assert `habitDetail.history.callout.label == bucket.label`; tap it again and require the callout to dismiss. Record Daily-current and Daily-historical-callout screenshots.

- [ ] **Step 3: Prove month bounds**

Navigate previous until `habitDetail.month.previous.isEnabled == false`; capture the month label, attempt activation, and assert the label is unchanged. Navigate next until `habitDetail.month.next.isEnabled == false`, then repeat. Require every intermediate month label to differ from the prior label so a disabled or stale navigation action cannot pass silently.

- [ ] **Step 4: Prove one entry deletion and atomic refresh**

Return to the current month. Capture the grace bucket accessibility label and the set of `habitDetail.entry.delete.*` identifiers. Tap exactly one grace-entry delete control, wait for that identifier to disappear, and assert the set shrank by one—not two. Require the grace bucket label to change from requirement met to requirement not met, require `habitDetail.risk` with owner-visible current-streak-at-risk copy, and verify the row/progress/history refresh occurred together. Record Recent-entries evidence.

- [ ] **Step 5: Prove Edit cancel/save return and frozen facts**

Capture one final bucket label. Open Edit, change the unit field, tap Cancel, and require return to the same detail with unchanged metadata. Open Edit again, change target to `3` and unit to `visits`, tap Save once, and require the same detail identity, metadata containing `3 visits`, unchanged captured final-bucket label, and current/grace labels using the new requirement. Record Edit-return evidence.

- [ ] **Step 6: Prove Archive, Reactivate, and roster actions**

Tap `habitDetail.archive`; require `habitDetail.reactivate`, frozen streak units, dormant history, and no fabricated editable entries. Record inactive-after-archive evidence. Tap Reactivate; require `habitDetail.archive` and an owner-visible Open current bucket that is due under the updated requirement. Back to All Habits, long-press the same row, and require established Edit, Archive, and Delete actions without opening detail.

- [ ] **Step 7: Prove weekly and inactive destinations**

Open `Weekly field notes`; assert Weekly metadata, current/best week units, multiple `habitDetail.history.*` strips at least 44 points high and materially wider than 44 points, and a boundary strip whose exact week-range label equals its callout label. Record Weekly-strips evidence. Back and open `Dormant reading`; require Reactivate, frozen day streak, dormant history, and `habitDetail.entries.empty`; record Inactive-detail evidence.

- [ ] **Step 8: Prove persisted relaunch and shell return**

Terminate. Relaunch with `launchArguments(reset: false, fixture: nil)` so the same `storeName` is supplied with only the UI-testing/store flags and the same `TZ`; fixture and reset arguments are absent. Open Daily and require the saved `3 visits` metadata, one fewer entry, the same finalized bucket fact, and active state after Reactivate. Back and assert `shell.destination.habits` exists and `shell.tab.habits.isSelected == true`.

- [ ] **Step 9: Run the complete UI suite and fix only observed contract failures**

Run:

```bash
Scripts/tiller-xcode-test TendUITests/HabitDetailUITests
```

Expected: every owner journey assertion passes. Any defect found follows a new RED/GREEN cycle in this suite or the smallest focused unit suite; do not loosen an owner-visible assertion to hide a product defect.

- [ ] **Step 10: Commit the complete journey**

```bash
git add App/TendUITests/HabitDetailUITests.swift App/Tend/Habits/HabitDetailView.swift App/Tend/Habits/HabitDetailModel.swift
git commit -m "Verify persisted detail journey T-0i5tqj"
```

Only include production files that changed in response to a witnessed failing contract.

---

### Task 4: Adaptive, Accessibility, and Visual Evidence

**Files:**
- Modify: `App/TendUITests/HabitDetailUITests.swift`
- Create: `.tiller/evidence/roster-detail-integration/manifest.json`
- Create: `.tiller/evidence/roster-detail-integration/*.png`

**Interfaces:**
- Consumes: the complete fixture and journey from Tasks 1–3 plus the approved Habit Detail Pencil board.
- Produces: compact-iPhone and centered-iPad screenshots at default and two larger Dynamic Type sizes, factual accessibility/adaptation observations, and a machine-readable evidence manifest.

- [ ] **Step 1: Add an adaptive accessibility test**

Add a second test that starts from its own reset fixture store. At default size, open Daily, assert minimum 44-point Back, Edit, month controls, every visible real bucket, every visible entry deletion control, Archive/Reactivate, and retry control when present. Run XCTest accessibility audits for contrast, hit region, sufficient description, text clipping, and traits; omit only element-detection checks for intentionally offscreen scroll content and record that omission.

Relaunch the same store twice without reset/fixture using `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL` and then `UICTContentSizeCategoryAccessibilityXL`. At each size, reopen Daily and require wrapped title/metadata, accessible month controls, recent entries, lifecycle action, and last scroll content after scrolling. Record one screenshot per size. Relaunch with dark system preference and require the app evidence remains visibly in the forced-light Almanac appearance.

- [ ] **Step 2: Run compact iPhone evidence**

Run the required wrapper command and keep its `.xcresult` path from output:

```bash
Scripts/tiller-xcode-test TendUITests/HabitDetailUITests
```

Export XCTest attachments with Xcode 26 `xcresulttool export attachments` into a temporary directory outside the repository. Copy only the named Daily-current, Daily-historical-callout, Weekly-strips, Recent-entries, Inactive-detail, Edit-return, and two Dynamic-Type PNGs into `.tiller/evidence/roster-detail-integration/` with deterministic lowercase filenames.

- [ ] **Step 3: Run centered iPad evidence**

Resolve the first available iOS 26 iPad UDID from `xcrun simctl list devices available --json`, boot it, then run:

```bash
xcodebuild -project Tend.xcodeproj -scheme Tend -destination "platform=iOS Simulator,id=$IPAD_UDID" -only-testing:TendUITests/HabitDetailUITests test
```

Inspect Daily current/history, Weekly strips, Inactive, Edit return, and larger-text layouts at iPad width. Require centered readable content and full-screen flow with no sidebar or tab pill. Extract the corresponding iPad attachments as deterministic PNGs.

- [ ] **Step 4: Exercise Reduce Motion and record the VoiceOver boundary honestly**

Use the supported `simctl ui` Reduce Motion toggle when available, relaunch the adaptive test without reset, and exercise Back, month selection/callout dismissal, Edit cancel/save, entry deletion, Archive, and Reactivate. If simulator VoiceOver traversal cannot be driven reliably, do not claim it was observed: record the exact limitation and cite XCTest full labels, traits, default actions, named non-swipe actions, and 44-point measurements plus a human physical-device follow-up.

No deterministic operation-failure UI seam exists in the approved production surface. Record the absence in the manifest rather than adding a fixture-controlled production failure or fabricating retry evidence; model retry behavior remains covered by `HabitDetailModelTests`.

- [ ] **Step 5: Compare screenshots to the approved design source**

Open `.tiller/design/comps/tend.pen` through Pencil, inspect the `Habit Detail` board, and compare paper chrome, uniform New York title, metadata, balanced streak pair, quiet risk state, month controls, 44-point garden geometry, state fills/strokes, legend, entries, lifecycle action, no shadow/alarm red/native Form chrome, centered iPad width, and safe-area clearance. Fix only objective deviations, rerun the affected screenshot, and keep the final image only.

- [ ] **Step 6: Write `manifest.json`**

Use schema `tend.evidence.v1` with task `app-experience/habit-detail-history/roster-detail-integration (T-0i5tqj)`, feature `app-experience/habit-detail-history (F-efgzky)`, tested commit, device/runtime, Dynamic Type, Reduce Motion, source screenshot attachment, final PNG path, and a factual `observations` array per artifact. Include `limitations` entries for unobserved physical VoiceOver traversal and unavailable deterministic operation-failure UI capture. Do not call C5 or C6 passed.

- [ ] **Step 7: Commit final evidence after smoke success**

```bash
git add App/TendUITests/HabitDetailUITests.swift .tiller/evidence/roster-detail-integration
git commit -m "Record detail journey evidence T-0i5tqj"
```

---

### Task 5: Full Gates, Review, and Task PR

**Files:**
- Modify through Tiller commands: `.tiller/board.md`, task/feature state, and generated event records.
- No production cleanup beyond findings proven by the gates or independent review.

**Interfaces:**
- Consumes: all prior committed slices and evidence.
- Produces: green task/feature gate records, one task PR, and `in_review` Tiller state.

- [ ] **Step 1: Format changed Swift files and check the diff**

Run `swift format --in-place` only on changed Swift files, then:

```bash
git diff --check
git status --short
```

Commit any formatter-only delta with `T-0i5tqj` in the message before gate execution so Tiller records gates against a clean commit.

- [ ] **Step 2: Run every required task command**

```bash
Scripts/tiller-xcode-test TendUITests/HabitDetailUITests
Scripts/tiller-xcode-test TendUITests/HabitManagementUITests
Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests
Scripts/tiller-xcode-test TendTests/HabitDetailModelTests
Scripts/tiller-xcode-test TendTests/HabitRosterModelTests
Scripts/tiller-xcode-test TendTests/HabitFormModelTests
Scripts/tiller-xcode-test TendTests/TendApplicationModelTests
Scripts/tiller-swift-test
swift build
xcodebuild -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: every suite/build passes. Do not narrow away a failure; reproduce it in the smallest named suite and use systematic debugging plus a regression test before rerunning the full command list.

- [ ] **Step 3: Record task and feature acceptance evidence**

```bash
tiller check task T-0i5tqj
tiller eval feature F-efgzky
tiller check feature F-efgzky
```

Automated C1–C4 must pass. C5/C6 remain pending human attestation with evidence attached; never run `tiller attest` or `tiller approve`. Commit the generated `.tiller` delta immediately with a message containing `T-0i5tqj`.

- [ ] **Step 4: Request independent final review**

Package the complete diff from merge base `main` to HEAD. Review against `task.md`, `feature.md`, `feature.eval.md`, the evidence manifest/screenshots, fixture production isolation, row gesture/action coexistence, stable identity, external deletion safety, one-dispatch mutations, relaunch persistence, accessibility, and no scope drift. Resolve every Critical/Important finding through RED/GREEN tests and rerun affected gates.

- [ ] **Step 5: Push and open the task PR**

Push `tiller/app-experience/habit-detail-history`. Open one PR to `main` titled exactly:

```text
app-experience/habit-detail-history/roster-detail-integration (T-0i5tqj)
```

The body names parent feature `app-experience/habit-detail-history (F-efgzky)`, summarizes fixture/navigation/journey/evidence, lists exact gate commands and results, links evidence paths, states C5/C6 await human attestation, and states VoiceOver/failure-seam limitations without inflation.

- [ ] **Step 6: Submit and publish Tiller review state**

```bash
PR_NUMBER=$(gh pr view --json number --jq .number) && tiller submit task T-0i5tqj --pr "$PR_NUMBER" --owner jc
git add .tiller
git commit -m "Submit roster detail integration T-0i5tqj"
git push origin tiller/app-experience/habit-detail-history
```

Verify the PR head includes the submission commit, the working tree is clean, and the task is `in_review`. Do not merge or cross the human gate.

- [ ] **Step 7: Render the execution readout**

Run:

```bash
tiller readout execute
```

Return the block verbatim, then only factual notes naming task `app-experience/habit-detail-history/roster-detail-integration (T-0i5tqj)` and feature `app-experience/habit-detail-history (F-efgzky)`.
