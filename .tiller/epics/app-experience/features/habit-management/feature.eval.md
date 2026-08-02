---
node: F-tih743
criteria:
  - id: C1
    statement: Validated habit-management operations create a complete immediately usable active-habit graph, reconcile before mutable requirement edits without exposing cadence mutation, normalize daily and weekly configuration correctly, roll back failed writes, and permanently cascade deletion only when invoked.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/Management/HabitManagementOperationsTests.swift" }
    required: true
  - id: C2
    statement: The shared New/Edit draft has deterministic defaults, keeps persisted models untouched until successful Save, rejects empty names and units plus nonpositive targets, conditionally owns weekly pinned days and warnings, locks cadence in Edit, and preserves retryable owner input after an operation failure.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/HabitFormModelTests" }
    required: true
  - id: C3
    statement: The production-context roster partitions every habit into exactly one localized deterministic section, formats truthful current or frozen streak facts, refreshes across local-calendar boundaries, dispatches lifecycle and deletion operations exactly once, and returns to the zero-habit state without fabricated fallback values.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/HabitRosterModelTests" }
    required: true
  - id: C4
    statement: From an isolated empty store, the owner can create valid daily and weekly habits from Today or Habits, edit every mutable field while cadence remains locked, Archive and Reactivate, cancel deletion without data loss, confirm permanent deletion with its full consequence named, and see first-launch Today return after the final habit is removed.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/HabitManagementUITests" }
    required: true
  - id: C5
    statement: On compact iPhone and iPad, the All Habits roster, New/Edit form, first-launch body, and deletion surface match the Almanac boards and prose for layout, paper surfaces, typography, state colors, spacing, day controls, and centered readable width without shadows, alarm red, or native Form chrome.
    polarity: introduce
    binding: { type: manual }
    required: true
  - id: C6
    statement: Habit management remains complete through two larger Dynamic Type steps, never truncates an owner-written name, keeps every target at least 44 points, exposes full VoiceOver labels and non-swipe alternatives for every action, avoids keyboard and tab-pill obstruction, forces light appearance, and honors Reduce Motion.
    polarity: introduce
    binding: { type: manual }
    required: true
---

# Acceptance

C1 owns the mutation boundary that turns permissive SwiftData records into valid,
immediately usable habits without changing the schema or cadence semantics. C2
owns draft and form behavior independently of SwiftUI hierarchy. C3 binds the
roster to truthful domain computation and the existing activity lifecycle. C4
proves the complete owner journey against persisted state. C5 binds visual
fidelity to `.tiller/design/comps/tend.pen`; C6 binds accessibility and adaptive
behavior that a screenshot cannot establish.

All six criteria are satisfiable inside app-experience/habit-management
(F-tih743). Habit detail and history, Today progress cards, logging and back-fill,
notification permission and scheduling, haptics, distribution, and release-device
evidence stay with their dependent features.
