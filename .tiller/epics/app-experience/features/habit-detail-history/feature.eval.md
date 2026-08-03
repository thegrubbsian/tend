---
node: F-efgzky
criteria:
  - id: C1
    statement: A deterministic TendCore detail computation reconciles active state, reports truthful current and best streaks, projects daily and weekly month pages across final, provisional, inactive, pre-creation, and future periods, returns only editable open or grace entries, and rejects malformed or incomplete persisted history without fabricated fallback facts.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/History/HabitDetailComputationTests.swift" }
    required: true
  - id: C2
    statement: The detail presentation model localizes shared habit facts, clamps month navigation to the full supported lifetime, refreshes atomically across local-calendar boundaries and successful Edit, entry-delete, Archive, or Reactivate mutations, preserves owner context on cancellation or failure, and never displays unavailable derived values as zero.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/HabitDetailModelTests" }
    required: true
  - id: C3
    statement: Daily habits render a Monday-first unnumbered garden and weekly habits render intersecting week strips; every bucket exposes exact date, state, and provisional progress through a lightweight callout and VoiceOver while the visible fill and stroke grammar remains consistent with the Almanac legend.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/HabitDetailUITests" }
    required: true
  - id: C4
    statement: From active and inactive All Habits rows, the owner can open full-screen detail without the tab pill, navigate history, Edit and return, Archive or Reactivate, delete an editable current or grace contribution exactly once, return to the same roster, and relaunch the persisted store without changing final history or established roster-management behavior.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/HabitDetailUITests" }
    required: true
  - id: C5
    statement: On compact iPhone and centered iPad, the Habit Detail destination matches the Almanac board and prose for paper chrome, uniform title typography, metadata, balanced streak statistics, quiet risk state, month controls, 44-point garden geometry, state colors, legend, recent-entry rows, and lifecycle action without shadows, alarm red, native Form chrome, or a competing tab pill.
    polarity: introduce
    binding: { type: manual }
    required: true
  - id: C6
    statement: Habit Detail remains complete through two larger Dynamic Type steps, wraps owner-written names and units, keeps every action and history cell at least 44 points, exposes full VoiceOver labels and non-swipe actions, preserves keyboard and safe-area clearance, forces light appearance, and honors Reduce Motion across detail, Edit, entry deletion, and lifecycle transitions.
    polarity: introduce
    binding: { type: manual }
    required: true
---

# Acceptance

C1 owns the domain read boundary and calendar/history invariants. C2 owns
presentation state, formatting, refresh, and mutation dispatch independently of
the SwiftUI hierarchy. C3 binds both cadence-specific history surfaces to exact
owner-visible and assistive state. C4 proves the complete persisted journey from
and back to the existing roster. C5 binds visual fidelity to
`.tiller/design/comps/tend.pen`; C6 binds accessibility and adaptive behavior
that screenshots alone cannot establish.

All six criteria are satisfiable inside app-experience/habit-detail-history
(F-efgzky). Today progress cards, log-entry creation and back-fill, reminder
scheduling, habit deletion confirmation, haptics, distribution, and
release-device evidence stay with their dependent features.
