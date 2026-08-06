# iPhone-Only Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Tend a native iPhone-only application and remove every live iPad-specific production branch, project setting, UI-test branch, and pending acceptance requirement without weakening retained iPhone behavior.

**Architecture:** The Xcode application and both test targets become device-family `1` targets. Shared SwiftUI layout remains responsive, but explicit iPad detection, iPad-only sheet controls, tablet geometry checks, tablet screenshots, and tablet audit inventories are deleted rather than hidden behind flags. A forward Owner Device Release contract records the product cutover; completed plans, task specifications, events, and evidence remain historical records.

**Tech Stack:** Xcode 26 project settings, Swift 6, SwiftUI, XCTest UI testing, Swift Testing, Tiller.

## Global Constraints

- Tend supports native iPhone on iOS 26 only; `Tend`, `TendTests`, and `TendUITests` all use `TARGETED_DEVICE_FAMILY = 1`.
- Keep the current iPhone orientations: portrait, landscape left, and landscape right. Remove only the iPad-specific orientation override.
- Delete iPad branches cleanly. Do not leave `.pad` conditions, tablet aliases, dormant Close-button parameters, compatibility shims, skipped iPad tests, or iPad audit allowlists.
- Preserve general safe-area, flexible-width, `AlmanacMetrics.readableContentWidth`, Dynamic Type, keyboard, VoiceOver, Reduce Motion, and landscape behavior. Those are iPhone quality constraints, not iPad code.
- Preserve TendCore domain behavior, SwiftData schema, fixtures, logging semantics, visual tokens, bundle identifier, minimum OS, and dependency policy.
- Preserve completed Tiller task specifications, old implementation plans, events, and `.tiller/evidence/**` artifacts. They are historical evidence of the formerly universal build, not live code or tests.
- Re-scope pending fast-logging acceptance to iPhone before submission. Do not rewrite the in-review Today Dashboard task or any done node to erase what it actually verified.
- The forward `device-readiness/owner-device-release` feature supersedes historical iPad promises from done or in-review features.
- Do not use the platform cutover to suppress an iPhone defect. In particular, the existing `SET WEEK TOTAL` contrast failure must be fixed under its own accepted work before the final iPhone suite can be called green.
- Execute in an isolated worktree from a clean, agreed commit. The current fast-logging worktree contains uncommitted `QuantityLogSheet.swift` and `FastLoggingUITests.swift` corrections plus staged generated Tiller orientation; do not overwrite or absorb them accidentally.
- This is a support-scope reduction. Characterize retained iPhone behavior before each edit and verify it afterward; do not add source-text unit tests merely to prove code was deleted.

---

### Task 1: Record the iPhone-only product and Tiller contract

**Files:**
- Create: `.tiller/decisions/2026-08-06-iphone-only.md`
- Modify: `.tiller/design/01-overview.md:37-45`
- Modify: `.tiller/design/04-platform-and-constraints.md:3-11`
- Modify: `.tiller/epics/device-readiness/features/owner-device-release/feature.md`
- Create through `tiller-specify`: `.tiller/epics/device-readiness/features/owner-device-release/feature.eval.md`
- Create through `tiller-specify`: `.tiller/epics/device-readiness/features/owner-device-release/tasks/iphone-only-cutover/task.md`
- Modify: `.tiller/epics/app-experience/features/fast-logging/feature.md:236-296`
- Modify: `.tiller/epics/app-experience/features/fast-logging/feature.eval.md:24-40,83-90`
- Create: `.tiller/epics/app-experience/features/fast-logging/tasks/iphone-only-acceptance/task.md`
- Do not modify: `.tiller/orientation.md`, `app-experience/fast-logging/fast-logging-acceptance` (T-p7kknm), completed task specs, other completed plans, `.tiller/events/**` except generated new events, or `.tiller/evidence/**`

**Interfaces:**
- Consumes: the owner's decision that v1 is native iPhone-only and iPad may return as a separately designed future feature.
- Produces: an approved forward feature and task whose acceptance contract owns the target-family, live-code inventory, and complete iPhone verification requirements.

- [ ] **Step 1: Record the decision, then update the durable platform inputs**

Before any other repository edit, create
`.tiller/decisions/2026-08-06-iphone-only.md`. Record the native iPhone-only v1
decision, its rationale, the two amended design docs, the superseded and
replacement Fast Logging tasks by full reference, the forward Owner Device
Release feature, and the done/in-review work deliberately left untouched.

Then change the v1 exclusion in `01-overview.md` to:

```markdown
- Native iPad support and iPad-specific layouts
```

Replace the platform selection in `04-platform-and-constraints.md` with:

```markdown
- **Platform**: iOS 26, native, iPhone only. The application, unit-test target, and UI-test target build for device family 1. Native iPad support is excluded from v1; adding it later requires a new product contract, adaptive design pass, and device-specific evidence.
```

- [ ] **Step 2: Specify Owner Device Release as the forward owner**

Invoke `tiller-specify` for `device-readiness/owner-device-release` (F-3vz7ho). The feature must contain exactly these platform contracts:

1. The built app declares device family `1`, not `1,2`.
2. Live production and test code contain no explicit iPad detection, iPad-only control, tablet geometry branch, tablet screenshot branch, or iPad-only skip.
3. Existing general responsive layout remains; no fixed-width rewrite replaces it.
4. The complete package, app-unit, and iPhone UI suites pass.
5. A direct iPhone launch exercises Today, All Habits, Habit Detail, and the quantity log sheet.

Create one proposed task with canonical key `device-readiness/owner-device-release/iphone-only-cutover`; do not split configuration, production cleanup, and test cleanup into independently shippable states because the target must never claim iPhone-only while live tablet contracts remain.

- [ ] **Step 3: Re-scope Fast Logging and mint replacement acceptance**

Update only the active Fast Logging feature and evaluation:

- Replace “compact iPhone and centered iPad” with “compact iPhone.”
- Delete the iPad sheet-chrome allowance.
- Keep all daily/weekly, current/grace, Undo, validation, long-content, Dynamic Type, keyboard, accessibility, Reduce Motion, and forced-light requirements.
- Keep C6 required and manual; narrow only its device scope.
- Delete C5’s semicolon-joined `baseline.artifact` line. The optional field names one repo-relative file, and C5’s command binding already names every required test.

Create `app-experience/fast-logging/iphone-only-acceptance` (T-aocwl9). Its
`task.md` must name
`app-experience/fast-logging/fast-logging-acceptance` (T-p7kknm) as superseded,
point to `.tiller/decisions/2026-08-06-iphone-only.md`, and require only iPhone
journeys and `iphone-*` evidence. Do not edit the superseded checked task.

Do not edit the in-review Today Dashboard acceptance task or any done
feature/task. Their historical claims remain true for the commits they verified
and are superseded forward by Owner Device Release.

- [ ] **Step 4: Run the Tiller drift oracle and inspect every affected node**

Run:

```bash
tiller drift
tiller status feature app-experience/fast-logging
tiller status task app-experience/fast-logging/fast-logging-acceptance
tiller status task app-experience/fast-logging/iphone-only-acceptance
tiller status feature device-readiness/owner-device-release
```

Expected: Fast Logging reports `active_basis`; the superseded task remains
unchanged at `check`; the replacement is `proposed`; Owner Device Release is
`specced`; C5 no longer produces the semicolon-list `ref_unreadable` report.

- [ ] **Step 5: Show both diffs, then record only the named approvals**

Show the Fast Logging feature/eval diff before running:

```bash
tiller approve feature app-experience/fast-logging --refresh-basis
```

Show `app-experience/fast-logging/iphone-only-acceptance` (T-aocwl9)’s complete
task diff before running:

```bash
tiller approve task app-experience/fast-logging/iphone-only-acceptance
```

The owner has explicitly authorized those two gates. Do not refresh, approve,
submit, or cancel the superseded task.

- [ ] **Step 6: Commit the durable Tiller reshape**

Commit the decision record, design inputs, active Fast Logging contract,
replacement task, specced Owner Device Release plan, generated board/state/event
files, and this corrected plan together:

```bash
git commit -m "define durable iPhone-only release scope"
```

Do not include production code, tests, generated `.tiller/orientation.md`,
historical evidence, or any done/in-review node.

- [ ] **Step 7: Hand the superseded-task cancellation to the human**

From the reshape worktree, the human runs:

```bash
tiller cancel task T-p7kknm --reason "superseded by app-experience/fast-logging/iphone-only-acceptance (T-aocwl9) under the iPhone-only decision (.tiller/decisions/2026-08-06-iphone-only.md)"
```

Also present, but do not run without a separate explicit approval naming the
node:

```bash
tiller approve feature device-readiness/owner-device-release
```

Continue to implementation only after the human records the cancellation and
approves `device-readiness/owner-device-release` (F-3vz7ho).

---

### Task 2: Restrict every Xcode target to iPhone

**Files:**
- Modify: `Tend.xcodeproj/project.pbxproj:332-379,388-460`

**Interfaces:**
- Consumes: the approved Owner Device Release platform contract.
- Produces: app, unit-test, and UI-test targets whose Debug and Release configurations declare device family `1`.

- [ ] **Step 1: Prove the current project is still universal**

Run each query and confirm it exits nonzero because the current value is `1,2`:

```bash
xcodebuild -project Tend.xcodeproj -target Tend -showBuildSettings -json | jq -e '.[0].buildSettings.TARGETED_DEVICE_FAMILY == "1"'
xcodebuild -project Tend.xcodeproj -target TendTests -showBuildSettings -json | jq -e '.[0].buildSettings.TARGETED_DEVICE_FAMILY == "1"'
xcodebuild -project Tend.xcodeproj -target TendUITests -showBuildSettings -json | jq -e '.[0].buildSettings.TARGETED_DEVICE_FAMILY == "1"'
```

- [ ] **Step 2: Make the project configuration iPhone-only**

For Debug and Release configurations of all three targets, replace:

```text
TARGETED_DEVICE_FAMILY = "1,2";
```

with:

```text
TARGETED_DEVICE_FAMILY = 1;
```

Delete both app configuration entries named:

```text
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad
```

Keep `INFOPLIST_KEY_UISupportedInterfaceOrientations`, `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`, `SUPPORTS_MACCATALYST = NO`, iOS 26, and every signing/bundle setting unchanged.

- [ ] **Step 3: Verify all target build settings**

Re-run the three `xcodebuild -showBuildSettings -json | jq -e` commands from Step 1.

Expected: all three exit zero and report `TARGETED_DEVICE_FAMILY == "1"`.

- [ ] **Step 4: Build the iPhone application**

Run:

```bash
xcodebuild -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`; no project warning mentions an unavailable iPad orientation or device family.

- [ ] **Step 5: Commit the project cutover**

```bash
git add Tend.xcodeproj/project.pbxproj
git commit -m "target Tend at iPhone only"
```

---

### Task 3: Delete the iPad-only quantity-sheet production path

**Files:**
- Modify: `App/Tend/Today/TodayView.swift:7-13,52-60`
- Modify: `App/Tend/Today/QuantityLogSheet.swift:10-25,81-112`
- Test: `App/TendUITests/FastLoggingUITests.swift`

**Interfaces:**
- Consumes: the existing compact-iPhone SwiftUI sheet presentation and drag-to-dismiss behavior.
- Produces: `QuantityLogSheet(model:habits:makeContext:)` with one title path and no device-width control input.

- [ ] **Step 1: Characterize the retained iPhone sheet before editing**

After the known iPhone contrast defect is separately green, run:

```bash
Scripts/tiller-xcode-test TendUITests/FastLoggingUITests
```

Expected: the suite passes on the configured iPhone simulator; `log-sheet.close` is absent and sheet dismissal uses standard swipe-down chrome.

- [ ] **Step 2: Remove the regular-width input at the caller**

Delete `@Environment(\.horizontalSizeClass)` from `TodayView`. Construct the sheet as:

```swift
QuantityLogSheet(
  model: loggingModel,
  habits: habits,
  makeContext: operationContext
)
```

Do not change detents, drag indicator, content interaction, background, or color scheme.

- [ ] **Step 3: Collapse `QuantityLogSheet` to the iPhone title path**

Delete:

- `@Environment(\.dismiss)`
- `let showsCloseButton: Bool`
- `sheetHeader(_:)`
- the `Close` button and `log-sheet.close` identifier

Call the existing title directly:

```swift
VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
  sheetTitle(sheet)
  scopeControl(sheet)
  progressSection(sheet)
  quickAddSection(sheet)
  amountSection(sheet)
  // Existing error and entry content remains unchanged.
}
```

Keep `sheetTitle(_:)` itself unchanged. The compact-iPhone rendered hierarchy must remain identical.

- [ ] **Step 4: Compile and rerun the focused iPhone journey**

Run:

```bash
Scripts/tiller-xcode-test TendTests
Scripts/tiller-xcode-test TendUITests/FastLoggingUITests
```

Expected: both pass; the UI suite still proves title visibility, standard sheet geometry, keyboard interaction, Undo, and swipe dismissal.

- [ ] **Step 5: Commit the production cleanup**

```bash
git add App/Tend/Today/TodayView.swift App/Tend/Today/QuantityLogSheet.swift
git commit -m "remove iPad quantity sheet adaptation"
```

---

### Task 4: Remove tablet branches from habit UI tests

**Files:**
- Modify: `App/TendUITests/HabitManagementUITests.swift:137-159`
- Modify: `App/TendUITests/HabitDetailUITests.swift:320-346,430-457,540-551,577-612`

**Interfaces:**
- Consumes: existing iPhone owner journeys and accessibility assertions.
- Produces: deterministic iPhone-only tests with no width threshold, iPad readable-column helper, or split-view assertion.

- [ ] **Step 1: Run the retained suites before editing**

Run:

```bash
Scripts/tiller-xcode-test TendUITests/HabitManagementUITests
Scripts/tiller-xcode-test TendUITests/HabitDetailUITests
```

Expected: both pass on the configured portrait iPhone simulator.

- [ ] **Step 2: Make the habit-form keyboard action unconditional**

Replace the width branch in `HabitManagementUITests` with the behavior the iPhone journey always requires:

```swift
app.swipeDown()
XCTAssertFalse(app.keyboards.firstMatch.exists)
```

Keep the weekday mutation and save assertions unchanged.

- [ ] **Step 3: Delete the Habit Detail iPad column contract**

Delete both calls to `assertReadableDetailColumnOnIPad(...)` and delete the helper. Since this target now runs only on the named compact iPhone, replace:

```swift
if app.windows.firstMatch.frame.width < 700 {
  XCTAssertGreaterThan(adaptiveMetadata.frame.height, 40)
}
```

with:

```swift
XCTAssertGreaterThan(adaptiveMetadata.frame.height, 40)
```

The assertion still protects iPhone Dynamic Type wrapping.

- [ ] **Step 4: Keep the iPhone shell assertion and remove split-view residue**

Rename `assertDetailUsesFullScreenShell` to `assertDetailHidesTabPill`. Retain the two assertions that Today and Habits tab buttons are not hittable while detail is presented. Delete `XCTAssertEqual(app.splitGroups.count, 0)`, which existed solely to reject iPad split navigation.

- [ ] **Step 5: Re-run both suites**

Run:

```bash
Scripts/tiller-xcode-test TendUITests/HabitManagementUITests
Scripts/tiller-xcode-test TendUITests/HabitDetailUITests
```

Expected: both pass with no skip and no device-width conditional.

- [ ] **Step 6: Commit the habit-test cleanup**

```bash
git add App/TendUITests/HabitManagementUITests.swift App/TendUITests/HabitDetailUITests.swift
git commit -m "remove iPad habit UI contracts"
```

---

### Task 5: Make Today Dashboard acceptance iPhone-only

**Files:**
- Modify: `App/TendUITests/TodayDashboardUITests.swift:285-414,479-482,558-573`

**Interfaces:**
- Consumes: the existing 402×874 portrait-iPhone evidence journey, accessibility audits, scrolling checks, and Dynamic Type journeys.
- Produces: an iPhone-only dashboard suite with fixed `iphone-*` artifact names and no iPad-only skipped test.

- [ ] **Step 1: Run the dashboard suite before editing**

Run:

```bash
Scripts/tiller-xcode-test TendUITests/TodayDashboardUITests
```

Expected baseline: all iPhone tests pass and `testCenteredIPadEvidenceState` is the sole expected skip.

- [ ] **Step 2: Remove device-name branching from screenshots**

Delete `evidenceDeviceName`. In `testAcceptanceEvidenceStates`, always execute the current iPhone scroll/hittability branch and use these names directly:

```text
iphone-mixed-top
iphone-mixed-bottom
iphone-all-tended
iphone-inactive
iphone-failure-full
```

In both Dynamic Type loops, use the existing `iphone-` prefix directly. Do not change the captured states or accessibility audit types.

- [ ] **Step 3: Delete the iPad-only test**

Delete `testCenteredIPadEvidenceState()` in full. Do not replace it with a skip or a disabled test.

- [ ] **Step 4: Make evidence geometry an exact iPhone contract**

Change `assertEvidenceDeviceGeometry` to return `Void`, remove the idiom ternary, and assert only:

```swift
let expectedSize = CGSize(width: 402, height: 874)
XCTAssertEqual(
  window.frame.size,
  expectedSize,
  "Expected portrait 402×874, got \(window.frame.size)"
)
```

Remove the `guard ... else` blocks at callers and invoke the assertion directly. Keep `assertCenteredReadableSurface`; its safe-area/readable-width assertions remain useful on iPhone and are not tablet-specific.

- [ ] **Step 5: Re-run the dashboard suite**

Run:

```bash
Scripts/tiller-xcode-test TendUITests/TodayDashboardUITests
```

Expected: the suite passes with one fewer test and zero iPad-only skips; all existing iPhone screenshots and audits are still emitted.

- [ ] **Step 6: Commit the dashboard-test cleanup**

```bash
git add App/TendUITests/TodayDashboardUITests.swift
git commit -m "remove iPad dashboard acceptance"
```

---

### Task 6: Make Fast Logging acceptance iPhone-only

**Files:**
- Modify: `App/TendUITests/FastLoggingUITests.swift:430-470,575-610,829-853,1017-1192,1228-1276,1497-1517`

**Interfaces:**
- Consumes: all existing iPhone daily, weekly, current, grace, validation, Undo, keyboard, Dynamic Type, audit, persistence, and relaunch assertions.
- Produces: one iPhone audit policy and one standard iPhone sheet-dismissal path, with no tablet helper or expected issue inventory.

- [ ] **Step 1: Establish a green iPhone baseline**

Run:

```bash
Scripts/tiller-xcode-test TendUITests/FastLoggingUITests
```

Expected: pass after the separately accepted iPhone contrast correction. If `SET WEEK TOTAL` or any other iPhone finding remains, stop; this platform task may not waive it.

- [ ] **Step 2: Delete iPad-only sheet expansion**

Delete both `UIDevice.current.userInterfaceIdiom == .pad` blocks that call `expandSheet`. Delete `expandSheet(_:in:)`, which then has no callers. Keep the following `makeHittable` calls; they are the iPhone interaction contract.

- [ ] **Step 3: Fix fixture names to the only supported device**

Delete `evidenceDeviceName` and return the existing stable iPhone name directly:

```swift
private func evidenceStoreName(
  journey: String,
  sizeSlug: String = "standard"
) -> String {
  "fast-logging-iphone-\(journey)-\(sizeSlug)"
}
```

- [ ] **Step 4: Collapse the audit inventory to `AuditContext`**

Change:

```swift
switch (evidenceDeviceName, context)
```

to:

```swift
switch context
```

Rewrite the retained tuple cases as direct contexts:

```swift
case .dailyGrace:
case .weeklyGrace, .weeklyPostUndo:
case .adaptiveMediumTop("accessibility-large"):
case .adaptiveMediumTop("accessibility-extra-extra-large"):
```

Delete every `("ipad", ...)` case and its expected issue values. Keep the existing iPhone issue signatures unchanged until a separately observed iPhone audit proves they are obsolete.

- [ ] **Step 5: Collapse sheet geometry to compact iPhone**

Delete the entire `.pad` branch from `assertSheetGeometry`. Retain the current common frame containment checks, compact-iPhone symmetric chrome checks, and optional title visibility checks:

```swift
let leadingChrome = sheetFrame.minX - windowFrame.minX
let trailingChrome = windowFrame.maxX - sheetFrame.maxX
XCTAssertEqual(leadingChrome, trailingChrome, accuracy: 1, file: file, line: line)
XCTAssertLessThanOrEqual(leadingChrome, 8.5, file: file, line: line)
XCTAssertLessThanOrEqual(trailingChrome, 8.5, file: file, line: line)
```

- [ ] **Step 6: Collapse dismissal to standard iPhone sheet chrome**

Replace `dismissSheet(_:in:)` with the existing iPhone path:

```swift
private func dismissSheet(_ sheet: XCUIElement, in app: XCUIApplication) {
  let closeQuery = app.buttons.matching(identifier: "log-sheet.close")
  XCTAssertEqual(closeQuery.count, 0)
  XCTAssertFalse(app.buttons["log-sheet.close"].exists)
  for _ in 0..<3 where sheet.exists {
    sheet.swipeDown()
  }
  XCTAssertTrue(waitForDisappearance(sheet))
}
```

Do not retain fallback support for a Close button.

- [ ] **Step 7: Run the complete focused suite**

Run:

```bash
Scripts/tiller-xcode-test TendUITests/FastLoggingUITests
```

Expected: pass with all iPhone journeys, accessibility audits, screenshot names, relaunch state, and dismissal behavior intact.

- [ ] **Step 8: Commit the fast-logging test cleanup**

```bash
git add App/TendUITests/FastLoggingUITests.swift
git commit -m "remove iPad fast logging acceptance"
```

---

### Task 7: Prove the clean cutover and record review evidence

**Files:**
- Modify only if generated by Tiller: `.tiller/board.md`, applicable `task.yml`/`feature.yml`, and new `.tiller/events/**`
- Do not create iPad screenshots, replacement tablet fixtures, or compatibility documentation.

**Interfaces:**
- Consumes: Tasks 1–6 at one source/test commit.
- Produces: a green iPhone-only build/test record with no live iPad support residue and a reviewable Tiller task.

- [ ] **Step 1: Search live configuration, production, and tests for residue**

Use the repository search tool case-insensitively over `Tend.xcodeproj/project.pbxproj`, `App/Tend`, and `App/TendUITests` for:

```regex
ipad|userInterfaceIdiom|\.pad\b|showsCloseButton|horizontalSizeClass|UISupportedInterfaceOrientations_iPad|TARGETED_DEVICE_FAMILY = "1,2"|CGSize\(width: 1024, height: 1366\)|600\.5|width < 700|width >= 700|splitGroups|expandSheet|log-sheet\.close|evidenceDeviceName
```

Expected: no matches. Do not include historical `.tiller/evidence`, completed task specs, old plans, or events in this zero-match assertion.

- [ ] **Step 2: Reconfirm all three target families**

Run:

```bash
xcodebuild -project Tend.xcodeproj -target Tend -showBuildSettings -json | jq -e '.[0].buildSettings.TARGETED_DEVICE_FAMILY == "1"'
xcodebuild -project Tend.xcodeproj -target TendTests -showBuildSettings -json | jq -e '.[0].buildSettings.TARGETED_DEVICE_FAMILY == "1"'
xcodebuild -project Tend.xcodeproj -target TendUITests -showBuildSettings -json | jq -e '.[0].buildSettings.TARGETED_DEVICE_FAMILY == "1"'
```

Expected: three zero exits.

- [ ] **Step 3: Run package verification once**

Run:

```bash
swift build
Scripts/tiller-swift-test
```

Expected: build succeeds and all TendCore tests pass.

- [ ] **Step 4: Run app verification once**

Run:

```bash
Scripts/tiller-xcode-test TendTests
Scripts/tiller-xcode-test TendUITests
xcodebuild -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: TendTests and the complete iPhone-only TendUITests suite pass with no iPad skip; the generic application build succeeds. Do not rerun deterministic failures. Investigate and correct the root cause under the owning task.

- [ ] **Step 5: Run strict formatting once**

Run:

```bash
swift format lint --recursive --strict Sources Tests App
```

Expected: zero exit. The execution branch must begin from a formatting-clean accepted baseline; do not broaden this scope into unrelated repository formatting cleanup.

- [ ] **Step 6: Smoke-test the actual app on iPhone**

Launch the configured iPhone simulator with the deterministic store fixture and directly exercise:

1. Today mixed state and scrolling above the floating pill.
2. All Habits roster and an Edit return.
3. Habit Detail with the tab pill hidden.
4. Quantity logging, custom amount keyboard submit/cancel, Undo, and swipe dismissal.

Expected: the four surfaces are reachable, retain forced-light Almanac styling, and have no `log-sheet.close` control. This is the behavioral proof; build settings alone are insufficient.

- [ ] **Step 7: Run Tiller gates and feature evaluation**

Run once:

```bash
tiller check task device-readiness/owner-device-release/iphone-only-cutover
tiller eval feature device-readiness/owner-device-release
tiller drift
```

Expected: task build/tests gates pass; every required Owner Device Release criterion has evidence; no new `active_basis`, `missing_surface`, or `orphan_eval` candidate is attributable to the cutover. Existing unrelated drift must be reported separately, not silently folded into this task.

- [ ] **Step 8: Request code review before submission**

Review specifically for:

- any remaining live iPad identifier or branch;
- accidental removal of general responsive-width or accessibility behavior;
- target-family mismatch between app and test targets;
- an iPhone assertion weakened merely because it once shared an iPad branch;
- edits to historical Tiller records that should have remained immutable.

Resolve every Blocker or Important finding and rerun only affected commands once.

- [ ] **Step 9: Commit generated Tiller verification state**

Commit only the generated board/task/feature/event changes from the completed checks:

```bash
git commit -m "verify iPhone-only application support"
```

Then follow `tiller-execute` to submit `device-readiness/owner-device-release/iphone-only-cutover` for review. Stop at `in_review`; the human owns merge and every attestation gate.
