---
node: F-z8e13q
criteria:
  - id: C1
    statement: The editable-logging TendCore projection returns one coherent active-habit snapshot with the current open daily or Monday-through-Sunday bucket and only the still-editable preceding grace bucket, preserving exact progress, target, unit, provisionally met state, stable entry identity and deterministic order while reusing reconciliation, evaluation, calendar, relationship, overflow, and transaction semantics without partial results.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Logging/HabitLoggingComputationTests.swift" }
    required: true
  - id: C2
    statement: The app logging model dispatches only the exact stored unit `times` to one-count append, derives deterministic friendly quick adds and cadence-aware scopes, validates custom and set-total input, maps stable entries, samples one fresh operation context, refreshes atomically after successful writes, retains complete state on failure, and owns exactly one five-second exact-entry Undo plus event-correct feedback decisions independently of SwiftUI.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/TodayLoggingModelTests" }
    required: true
  - id: C3
    statement: Production Today rings perform persisted target-one, multi-count, completed-count, and explicit grace-bucket `times` logging with truthful progress, grouping, fraction, streak-risk, haptic decision, transient Undo, expiry, failure, dismissal, and relaunch behavior; exact non-`times` units never take this direct-write path.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/FastLoggingUITests/testTimesLoggingJourneys" }
    required: true
  - id: C4
    statement: Production quantity rings present the approved scoped Log Sheet and persist daily and weekly current/grace quick-add, exact Finish, custom amount, cadence-aware set total, equal/lower-total behavior, stable per-entry delete, completed-habit access, transient Undo, inline failure, dismissal, and relaunch behavior without presenting a sheet for exact `times` habits.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/FastLoggingUITests/testQuantityLoggingJourneys" }
    required: true
  - id: C5
    statement: The existing Today projection, first-launch and inactive states, unavailable-row isolation and retry, truthful over-target facts, habit-management lifecycle refresh, two-destination shell, and LogEntryOperations append/set-total/delete authorization and rollback contracts remain intact around interactive logging.
    polarity: preserve
    baseline:
      surface: Today dashboard, habit lifecycle refresh, shell, and TendCore log mutation behavior before Fast Logging
      captured_at:
        kind: git_tree
        value: git:7a3fd678e2abb2df414bada027e01796e829b9c7
        path: App/Tend/Today
        observed_at: 2026-08-05T00:33:37Z
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/TodayDashboardUITests && Scripts/tiller-xcode-test TendUITests/HabitManagementUITests && Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests && Scripts/tiller-swift-test Tests/TendCoreTests/Logging/LogEntryOperationsTests.swift" }
    required: true
  - id: C6
    statement: On compact iPhone, empty, in-progress, complete, Undo, current/grace, daily/weekly, validation, empty-entry, and long-content states match the approved Pencil Today, Log Sheet, and Affordance States boards and Almanac tokens for hierarchy, sheet detents, ring/chip geometry, color roles, readable width, safe areas, scrolling, and forced-light appearance without clipping, broken reflow, or unintended navigation.
    polarity: introduce
    binding: { type: manual }
    required: true
  - id: C7
    statement: "Fast logging remains fully operable through two larger Dynamic Type steps, VoiceOver, keyboard input, and Reduce Motion: every ring, risk line, Undo, scope, amount action, chip, and delete has one complete announcement and at least a 44-point target; decorative facts do not duplicate; errors announce; motion cross-fades when reduced; and physical-device feedback is light for ordinary logs, success only on an unmet-to-met crossing, and lighter for Undo."
    polarity: introduce
    binding: { type: manual }
    required: true
---

# Acceptance

C1 owns the read side of editable logging. It must exercise daily and weekly
current/grace selection at ordinary, midnight, Monday, DST, and time-zone
boundaries; current-only behavior after grace; stable persisted entry identity;
newest-first ordering with deterministic ties; relationship corruption;
overflow; inactive/detached state; reconciliation/save failure; and complete
replacement semantics. The app must not duplicate these domain decisions.

C2 owns pure and injected behavior outside SwiftUI. Test targets `3`, `30`, `64`,
and `8,000`, targets near integer boundaries, progress below/equal/above target,
and preset/Finish deduplication. Use a controllable clock and sleeper to prove
that a new append replaces the prior Undo, expiry removes no data, stale expiry
cannot clear a newer Undo, relaunch starts without Undo, and failed exact-entry
delete retains the affordance and error. Test feedback as emitted decisions;
unit tests must not depend on a physical haptic engine.

C3 and C4 use deterministic DEBUG-only named stores and the production Today
destination. The focused test methods may contain multiple independently seeded
subjourneys so the bindings remain exact and stable. They must assert
owner-visible values before and after each action, persistent facts after sheet
dismissal and same-store relaunch, exact scope period keys through observed
behavior, absence of direct write for quantity taps, absence of a sheet for
`times`, and no success claim after a rejected mutation. Tests target controls by
stable accessibility identifier, never coordinate-only ring positions, row
index, `firstMatch`, UUID alone, or ambiguous display text.

C5 is a preservation gate against git tree
`7a3fd678e2abb2df414bada027e01796e829b9c7`. The prior
`TodayDashboardUITests` assertions that rings expose no actions are intentionally
superseded by this feature and must be replaced with the new unit-specific
contract; all unrelated dashboard, lifecycle, shell, and TendCore mutation
behavior remains baseline. This is not permission to rewrite fixtures or weaken
truthful projection checks merely to make the interactive suites pass.

For C6, compare complete compact-iPhone surfaces with nodes `Zl4uG` (**Today**),
`KUuoB` (**Log Sheet**), and `afx4Y` (**Affordance States**) in
`.tiller/design/comps/tend.pen`. Record top, middle, and bottom of any scrollable
sheet or dashboard. The comp’s fictional names and numbers are illustrative;
layout, spacing, color roles, and state grammar are normative. The sheet’s
Almanac content hierarchy must remain recognizable within the compact iPhone
viewport.

For C7, record exact accessibility labels, values, hints, traits, selected state,
reading order, focus after scope changes and errors, keyboard submit/cancel,
hit-region geometry, contrast, clipping, Reduce Motion behavior, and safe-area
clearance. A simulator accessibility audit and screenshots may support the
criterion but do not replace a manual VoiceOver traversal. Haptic character and
completion distinction require a physical device; never mark them passed from a
mock, emitted enum, simulator log, or source inspection.

All seven criteria are satisfiable inside app-experience/fast-logging
(F-z8e13q). Habit Detail entry display, reminder suppression after completion,
notification scheduling, device distribution, and release evidence remain with
their dependent features.
