# Habit Detail Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the reusable full-screen Almanac habit-detail model and SwiftUI surface on the merged TendCore history projection without wiring roster navigation.

**Architecture:** Extract one app-internal formatter shared by roster and detail. Add a main-actor observable detail model whose injected operation and local-midnight scheduling closures make every load, navigation, mutation, retry, and cancellation contract deterministic. Render one scrollable view from immutable model presentation values; SwiftUI never re-derives history truth.

**Tech Stack:** Swift 6, SwiftUI, Observation, SwiftData, Swift Testing, TendCore, Xcode synchronized groups.

## Global Constraints

- Preserve `HabitRosterModel` output exactly; only the built-in `times` unit singularizes to `time` when the target is one.
- Locale, calendar, current instant, and time zone are dependencies. No process-global formatter cache, repository protocol, alternate store, singleton, or detail cache.
- `HabitDetailComputation`, `LogEntryOperations`, and `HabitActivityOperations` remain the only live domain boundaries.
- A failed computation clears derived facts but preserves the raw habit name and navigation. A failed mutation preserves the last verified presentation and one retry request.
- Never dispatch a second mutation while one is in flight. Successful mutations refresh the complete presentation before returning control.
- Daily history is Monday-first, chronological, unnumbered, and uses real or filler cells exactly 44 points square with radius 7. Weekly history uses chronological full-width 44-point strips.
- Use only Almanac tokens and raised/sunken modifiers. No raw colors, shadows, alarm red, native `Form`, haptic changes, or state conveyed only by motion/color.
- Callouts dismiss on second selection, outside tap, month change, disappearance, and preserve exact localized state/progress text for VoiceOver.
- Weekly formatter inputs use half-open bucket intervals. Display and accessibility ranges end on the local calendar day immediately before `endExclusive`, including DST and year boundaries.
- Do not wire roster selection, modify shell ownership, add a UI-test fixture, change Today, add logging input, change TendCore behavior/schema, edit the Pencil comp, or edit the Xcode project.
- New source and test files are discovered by existing `PBXFileSystemSynchronizedRootGroup` membership.

---

### Task 1: Shared Habit Presentation Formatter

**Files:**
- Create: `App/Tend/Habits/HabitPresentationFormatter.swift`
- Modify: `App/Tend/Habits/HabitRosterModel.swift`
- Create: `App/TendTests/HabitDetailModelTests.swift`
- Test: `App/TendTests/HabitRosterModelTests.swift`

**Interfaces:**
- Produces: `HabitPresentationFormatter(calendar:locale:timeZone:)` with `requirement(target:unit:)`, `cadence(_:fallback:)`, `pinnedDays(rawValue:)`, `reminder(minuteOfDay:)`, `streak(value:cadence:)`, `streakUnit(value:cadence:)`, `month(_:)`, `day(_:)`, `week(start:endExclusive:)`, `time(_:)`, and `amount(_:unit:)`. `week` converts the projection's exclusive next-Monday end into the preceding local calendar day before formatting.
- Preserves: roster metadata separators (` · ` and `, `), Monday-first pin order, locale-aware numbers, raw cadence fallback, and exact day/week streak units.

- [ ] **Step 1: Write failing formatter contract tests**

Add Swift Testing cases that instantiate UTC Gregorian `en_US` and verify at minimum:

```swift
let formatter = HabitPresentationFormatter(
  calendar: fixedCalendar,
  locale: Locale(identifier: "en_US"),
  timeZone: utc
)
#expect(formatter.requirement(target: 8_000, unit: "steps") == "8,000 steps")
#expect(formatter.requirement(target: 1, unit: "times") == "1 time")
#expect(formatter.requirement(target: 1, unit: "steps") == "1 steps")
#expect(formatter.cadence(.weekly, fallback: "weekly") == "Weekly")
#expect(formatter.pinnedDays(rawValue: mondayAndWednesday.rawValue) == "Mon, Wed")
#expect(formatter.streak(value: 1, cadence: .daily) == "1 day")
#expect(formatter.streak(value: 2, cadence: .weekly) == "2 weeks")
```
Also pin a reminder, full day label, month/year, localized amount, and long owner unit without normalization. Pin `week(start:endExclusive:)` across a month/year boundary and a local DST transition so Monday-through-Sunday never renders as Monday-through-Monday.

- [ ] **Step 2: Verify RED**

Run: `Scripts/tiller-xcode-test TendTests/HabitDetailModelTests`

Expected: compilation fails because `HabitPresentationFormatter` does not exist.

- [ ] **Step 3: Implement the formatter and migrate roster calls**

Use instance-owned `DateFormatter` values configured from the injected calendar, locale, and time zone. Keep the formatter internal. In `HabitRosterFormatter.row`, create one formatter and replace the old requirement/cadence/pin calls. Delete the obsolete private helpers; keep row assembly, ordering, dormant metadata, and tone selection roster-only.

- [ ] **Step 4: Verify GREEN and parity**

Run:

```bash
Scripts/tiller-xcode-test TendTests/HabitDetailModelTests
Scripts/tiller-xcode-test TendTests/HabitRosterModelTests
```

Expected: all formatter contracts pass and every existing roster assertion remains unchanged.

- [ ] **Step 5: Commit**

Commit message: `Share habit presentation formatting`

---

### Task 2: Atomic Detail Projection and Navigation Model

**Files:**
- Create: `App/Tend/Habits/HabitDetailModel.swift`
- Modify: `App/TendTests/HabitDetailModelTests.swift`

**Interfaces:**
- Consumes: `HabitDetailSnapshot`, `HabitPresentationFormatter`, a persisted `Habit`, fixed now/time-zone/calendar/locale providers.
- Produces: `@MainActor @Observable final class HabitDetailModel`; immutable `HabitDetailPresentation`, `HabitDetailHistoryFact`, and `HabitDetailEntryFact`; `start()`, `refresh()`, `retryLoad()`, `selectPreviousMonth()`, `selectNextMonth()`, `selectHistory(_:)`, `dismissHistoryCallout()`, and `stop()`. `HabitDetailHistoryFact` retains `isRequirementMet` and incorporates it into provisional callout and VoiceOver text.
- Produces: app-internal `HabitDetailOperations` whose live initializer creates `HabitDetailComputation`, `LogEntryOperations`, and `HabitActivityOperations` from one `ModelContext`.
- Captures immutable `habitID` and `habitName` at initialization. The live `Habit` reference is used only inside successful computation/mutation paths; detached-habit failures never reread its properties.

- [ ] **Step 1: Write failing atomic-load tests**

Cover first successful load, exact raw name/metadata, current and best streak values/units, risk, daily chronological labels, weekly chronological Monday-through-Sunday range labels, leading/trailing daily fillers, editable-entry formatting/order, and inactive nil progress. For both `.open` and `.grace`, test pending-met and pending-unmet facts so `isRequirementMet`, progress, target, unit, callout text, and VoiceOver labels survive mapping. Assert the snapshot operation receives the habit, current instant, current time zone, and requested selected month.

- [ ] **Step 2: Write failing failure/navigation tests**

Cover:

```swift
model.start()
#expect(model.presentation == nil)
#expect(model.loadFailure?.retryTitle == "Try again")
#expect(model.habitName == longOwnerName)
```

Then retry to success. Verify previous/next clamping, exact month arithmetic in the injected calendar, disabled bounds, callout toggle, and dismissal on month change/stop. A failed page recomputation must clear derived state rather than retain a mismatched page.
Delete the persisted habit before a refresh and verify the model clears derived state, retains its captured immutable name/back path, reports unavailable, does not crash, and does not read the invalidated model again.

- [ ] **Step 3: Verify RED**

Run: `Scripts/tiller-xcode-test TendTests/HabitDetailModelTests`

Expected: compilation fails because model and presentation types do not exist.

- [ ] **Step 4: Implement immutable presentation mapping and atomic replacement**

Build all formatted values in locals. Set `presentation` only after snapshot and formatting succeed. Capture `habitID` and `habitName` before the first load; after a successful computation the attached model may refresh the captured name, but every failure path uses the immutable capture rather than dereferencing a detached SwiftData object. On computation failure, set `presentation = nil`, record one localized unavailable/retry message, and retain the requested month for retry. Preserve projection order and every provisional standing fact; do not synthesize history truth in the model.

Daily fillers derive only calendar geometry: leading count from the selected month weekday in a Monday-first calendar and trailing count to complete the final seven-cell row. Real item identity remains `HabitHistoryPeriod.key`.

- [ ] **Step 5: Implement deterministic month and callout state**

Month navigation requests one injected calendar month before/after the verified selected month, refuses disabled bounds, and dismisses selection before recomputing. Selecting the same key twice clears it; selecting another key replaces it. `stop()` clears selection and later Task 3 cancels scheduling.

- [ ] **Step 6: Verify GREEN**

Run: `Scripts/tiller-xcode-test TendTests/HabitDetailModelTests`

Expected: all load, failure, formatting, navigation, ordering, long-value, and inactive-fact tests pass without warnings.

- [ ] **Step 7: Commit**

Commit message: `Model habit detail presentation`

---

### Task 3: Detail Mutations, Edit Return, and Midnight Refresh

**Files:**
- Modify: `App/Tend/Habits/HabitDetailModel.swift`
- Modify: `App/TendTests/HabitDetailModelTests.swift`

**Interfaces:**
- Extends `HabitDetailOperations` with `deleteEntry`, `deactivate`, and `reactivate` closures. Live deletion resolves a UUID back to exactly one still-persisted entry belonging to the same habit before calling `LogEntryOperations.delete`; a missing or foreign-only match returns `missing` and refreshes.
- Produces: `HabitDetailOperationFailure` with entries/lifecycle placement; `deleteEntry(id:)`, `archive()`, `reactivate()`, `retryOperation()`, `presentEdit()`, `editCancelled()`, `editSaved()`, and `sceneBecameActive()`.
- Produces: injected `HabitDetailBoundaryScheduling` returning a cancellation token for one scheduled local-midnight action.

- [ ] **Step 1: Write failing entry-deletion tests**

Cover one deletion dispatch followed by one full refresh, reentrant duplicate refusal while the closure is active, mutation failure preserving the row/presentation and retry request, successful retry, final/exempt/missing identifier no-op, and vanished selected entry refreshing without deleting a foreign object.

- [ ] **Step 2: Write failing Edit and lifecycle tests**

Cover Edit presentation, cancel with zero recomputations, successful-save refresh, Archive/Reactivate exactly-once dispatch with current now/time zone, success refresh and lifecycle-title flip, failure preservation, and retry. If a mutation succeeds but refresh fails, clear stale derived facts and surface load failure.

- [ ] **Step 3: Write failing refresh/scheduling tests**

Inject a scheduler that records fire date, cancellation, and callback. Verify `start()` replaces any prior schedule, the date is the next local calendar-day boundary (including a DST fixture), firing refreshes and installs exactly one replacement, `sceneBecameActive()` refreshes and replaces the schedule, and `stop()` cancels it. Verify month rollover keeps an older valid selected page and clamps only when computation says necessary.

- [ ] **Step 4: Verify RED**

Run: `Scripts/tiller-xcode-test TendTests/HabitDetailModelTests`

Expected: new mutation and scheduling APIs are missing.

- [ ] **Step 5: Implement guarded mutation requests**

Set the in-flight request before calling the injected closure and clear it with `defer`. Keep one retry request only when the domain mutation throws. On success, clear operation failure and recompute the full selected page. No projected entry outside `presentation.entries` may dispatch.

- [ ] **Step 6: Implement live UUID resolution**

Fetch matching `LogEntry` records by UUID, select only entries whose `habit.persistentModelID` equals the selected habit, and call `LogEntryOperations.delete` only for exactly one such record. Missing, vanished, foreign-only, or ambiguous matches return `missing`; the model refreshes and never substitutes another entry.

- [ ] **Step 7: Implement replaceable local-midnight scheduling**

Compute tomorrow with `calendar.startOfDay(for:)` plus one calendar day after assigning the current time zone. Cancel the existing token before every replacement and on `stop()`. The live scheduler owns one cancellable `Task`; the test scheduler remains synchronous and deterministic.

- [ ] **Step 8: Verify GREEN and regressions**

Run:

```bash
Scripts/tiller-xcode-test TendTests/HabitDetailModelTests
Scripts/tiller-xcode-test TendTests/HabitRosterModelTests
Scripts/tiller-xcode-test TendTests/HabitFormModelTests
Scripts/tiller-swift-test Tests/TendCoreTests/History/HabitDetailComputationTests.swift
```

Expected: all suites pass without warnings.

- [ ] **Step 9: Commit**

Commit message: `Handle detail mutations and refresh`

---

### Task 4: Almanac Habit Detail View

**Files:**
- Create: `App/Tend/Habits/HabitDetailView.swift`
- Modify: `App/Tend/Habits/HabitFormView.swift`
- Modify: `App/Tend/Habits/HabitDetailModel.swift` only if a view-consumption gap is proven by compilation or smoke exercise.
- Modify: `App/Tend/Almanac/AlmanacMetrics.swift` only if one repeated semantic measurement cannot use `minimumTarget` or `gardenCellRadius`.

**Interfaces:**
- Consumes only `HabitDetailModel` presentation/action APIs. Production `init(habit:context:onBack:)` creates the live model; an internal model initializer supports previews.
- Extends `HabitFormView.init(mode:onSaved:)` with a default no-op callback; invoke it only after `HabitFormModel.save` succeeds and before dismissal.
- Produces explicit lifecycle wiring: appearance calls `start()` once per visible presentation, active-scene transition calls `sceneBecameActive()`, time-zone change refreshes/reschedules through the model, and disappearance calls `stop()` to cancel the boundary token and callout.
- Produces an explicit unavailable branch: the captured habit title and Back navigation remain; `loadFailure` renders one Almanac inline card with `Try again` wired to `retryLoad`; stats, risk, month controls, garden, legend, entries, and lifecycle facts are absent while `presentation == nil`.
- Produces DEBUG previews backed by isolated in-memory contexts for daily, weekly, and initial-failure states, with no app routing or UI-test launch argument.

- [ ] **Step 1: Add the compact full-screen shell**

Use a fixed custom Back/Edit row above a `ScrollView`, paper background, 20-point wrapper, readable maximum width 600, nontruncating serif title, wrapped metadata, and accessible 44-point controls. `onBack` is caller-supplied; do not add a `NavigationStack` or shell route.
Wire `.onAppear` to `model.start()`, `.onChange(of: scenePhase)` to `model.sceneBecameActive()` only for `.active`, `.onChange(of: timeZone.identifier)` to the model's refresh/reschedule entry point, and `.onDisappear` to `model.stop()`. Do not add a second `TimelineView`; the model owns the single replaceable local-midnight schedule.
Conditionally render verified detail sections only when `presentation` exists. When it does not, show loading or the single inline unavailable card below the captured title; `Try again` calls `model.retryLoad()`. Never substitute zero values or retain stale derived sections.

- [ ] **Step 2: Add adaptive streak and risk facts**

Render balanced CURRENT/BEST meaningful numerals with localized day/week units. Stack at accessibility Dynamic Type. Show the ochre quiet risk callout only when `isAtRisk`; no animation when Reduce Motion is enabled and no meaning depends on motion.

- [ ] **Step 3: Add month controls and cadence-specific garden**

Center the tracked uppercase localized month label between faint chevrons. Daily uses Monday-first weekday labels and rows of seven fixed 44-point cells distributed with flexible inter-cell space. Weekly uses full-width 44-point strips. Filler geometry is hidden from accessibility and hit testing. Real periods are plain buttons with exact labels, selected traits, semantic fill/stroke/opacity, and no numerals or shadows.

- [ ] **Step 4: Add transient callout and legend**

Render one lightweight callout within the readable wrapper from the model-selected fact. Ensure second selection, non-subview outside tap, month changes, and disappearance dismiss it. Add the exact three-item `Met`, `Missed`, `Open` legend after chronological history.

- [ ] **Step 5: Add recent entries and lifecycle action**

Rows show localized scope, time, amount/effective unit, and a 44-point minus-circle `Delete entry` button with the complete accessibility label. Empty state is one subdued sentence. Place entry failures beside entries and Archive/Reactivate failures beside the low-emphasis bottom action; retry calls the model once. Never render final/exempt deletion controls or permanent habit deletion.

- [ ] **Step 6: Present Edit with success-only refresh**

When `model.habitForEditing` is available after a verified load, present `HabitFormView(mode: .edit(habit), onSaved: model.editSaved)`. Cancel only dismisses and calls `editCancelled`; save calls the callback once, dismisses, and refreshes. Disable Edit and all mutating actions when the habit is unavailable or another mutation is in flight.

- [ ] **Step 7: Add isolated previews**

Under `#if DEBUG`, create daily and weekly in-memory persisted graphs with long owner data and enough history to exercise six daily rows/weekly strips, provisional/final/inactive facts, editable entries, and lifecycle state. Add a failure-state preview using an isolated context plus an injected throwing computation so the known title, Back, one retry card, and absence of derived sections are inspectable. Keep preview support private to `HabitDetailView.swift`.

- [ ] **Step 8: Compile and run focused contracts**

Run:

```bash
Scripts/tiller-xcode-test TendTests/HabitDetailModelTests
Scripts/tiller-xcode-test TendTests/HabitRosterModelTests
Scripts/tiller-xcode-test TendTests/HabitFormModelTests
xcodebuild -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: all tests and device build pass without warnings.

- [ ] **Step 9: Smoke-exercise both cadence layouts**

Launch the isolated preview/temporary developer harness on a compact iPhone simulator and an iPad simulator. Exercise initial failure and `Try again` recovery, month controls, period callout/open-close/outside dismissal, Edit cancel/save return, entry deletion, Archive/Reactivate lifecycle flip, Dynamic Type, VoiceOver labels, forced light, and Reduce Motion. Confirm the failure state keeps only title/navigation/retry and omits every derived section. Capture screenshots as evidence; remove any temporary harness before commit.

- [ ] **Step 10: Commit**

Commit message: `Build Almanac habit detail surface`

---

### Final Verification

- [ ] Format changed Swift sources with `swift format --in-place`.
- [ ] Run every command listed in the Tiller task, then `tiller check task app-experience/habit-detail-history/habit-detail-surface --owner jc`.
- [ ] Run independent code review over the complete branch diff and resolve all Critical/Important findings.
- [ ] Commit Tiller gate state, push the feature branch, open one task PR, run `tiller submit`, commit/push its state delta, and stop at `in_review`.
