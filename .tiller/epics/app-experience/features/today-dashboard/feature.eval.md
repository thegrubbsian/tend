---
node: F-skoqxt
criteria:
  - id: C1
    statement: HabitTodayComputation returns one coherent active-habit snapshot from the owner-local current daily or Monday-through-Sunday bucket, using existing reconciliation, evaluation, and streak rules for progress, provisional completion, and grace-derived risk without weakening transaction failures or malformed-graph errors.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Today/HabitTodayComputationTests.swift" }
    required: true
  - id: C2
    statement: TodayModel projects every active habit exactly once from one sampled refresh context, exposes stable persisted identity and truthful localized row facts, groups and orders unresolved and tended rows deterministically, computes the met fraction and quiet empty states correctly, isolates per-row failures, and replaces successful retries atomically without publishing mixed-generation facts.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/TodayModelTests" }
    required: true
  - id: C3
    statement: The production Today destination persists and renders mixed daily and weekly current-bucket cards, exact owner-visible progress and streak facts, grace risk, compact met rows, all-tended and inactive-only states, and the established shell across relaunch while the ambient ring performs no logging write and exposes no fake action.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/TodayDashboardUITests" }
    required: true
  - id: C4
    statement: The existing zero-habit first-launch introduction, shared New habit form handoff, Today landing destination, two-destination shell, shell-selection persistence, and habit-management journeys remain unchanged around the new nonempty dashboard.
    polarity: preserve
    baseline:
      surface: Today first-launch creation and two-destination shell behavior
      captured_at:
        kind: git_tree
        value: git:2cc4c733c7d69ab828106bbf8dd445e0f1bcf4ae
        path: App/Tend/Shell
        observed_at: 2026-08-04T04:54:57Z
      artifact: App/TendUITests/HabitManagementUITests.swift; App/TendUITests/AlmanacShellUITests.swift
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/HabitManagementUITests && Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests" }
    required: true
  - id: C5
    statement: On compact iPhone and centered iPad, mixed, all-tended, inactive-only, and unavailable-row Today states match the approved Pencil Today board and Almanac tokens for hierarchy, paper field, readable width, card geometry, progress tracks and rings, risk treatment, met compaction, wrapping, safe areas, and floating-tab clearance without clipping or unintended scroll loss.
    polarity: introduce
    binding: { type: manual }
    required: true
  - id: C6
    statement: Today remains fully legible and operable with two larger Dynamic Type steps, VoiceOver, Reduce Motion, and forced light appearance; each card announces exact owner facts and risk stakes once, headings are navigable, failed rows expose one clear retry, decorative progress is silent, the ambient ring has no button trait, and every real control is at least 44 points with sufficient contrast.
    polarity: introduce
    binding: { type: manual }
    required: true
---

# Acceptance

C1 owns the TendCore current-bucket read boundary, local-calendar selection,
reconciliation, streak risk, and malformed-state behavior. C2 owns the complete
Today presentation, stable identity, formatting, grouping, refresh, failure
isolation, and retry independently of SwiftUI. C3 proves the persisted owner
journey through the production Today destination, deterministic fixtures,
relaunch, and noninteractive ring seam.

C4 preserves the existing shell and first-launch behavior captured from
`App/Tend/Shell` at git tree
`2cc4c733c7d69ab828106bbf8dd445e0f1bcf4ae`, with
`HabitManagementUITests` and `AlmanacShellUITests` as the recorded executable
artifacts. It is a preservation gate, not permission to rewrite those journeys.

For C5, compare complete mixed, all-tended, inactive-only, and unavailable-row
screens on compact iPhone and centered iPad with the `Today` board in
`.tiller/design/comps/tend.pen`. Record top, middle, and bottom where scrolling
is required, and fail any clipped, unreachable, token-divergent, or semantically
misleading state. The persisted mixed fixture truth is `2 of 5`; the board’s
illustrative `3 of 5` does not override domain facts.

For C6, exercise the same deterministic states at two larger Dynamic Type steps
with VoiceOver, Reduce Motion, and forced light appearance. Record exact reading
order, labels and values, headings, retry behavior, ring traits, hit regions,
contrast, motion, safe-area clearance, and clipping as pass or fail. Simulator
screenshots and XCTest audits may support this criterion but do not replace an
unobserved manual VoiceOver traversal.

All six criteria are satisfiable inside app-experience/today-dashboard
(F-skoqxt). Log mutation, quick add, quantity entry, set total, undo, grace
back-fill dispatch, haptics, and logging sheets remain with
app-experience/fast-logging. Habit Detail navigation, reminder scheduling,
distribution, and release-device evidence remain with their owning dependent
features.
