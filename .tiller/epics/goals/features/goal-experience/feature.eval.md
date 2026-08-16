---
node: F-xowx7x
criteria:
  - id: C1
    statement: The Goals presentation model reads the production goal graph, partitions each goal exactly once into ordered open, past-due, or collapsible closed groups, refreshes time-sensitive facts, and formats accumulate and measure progress without reimplementing TendCore progress or standing rules.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/GoalRosterModelTests" }
    required: true
  - id: C2
    statement: The shared New and Edit goal draft provides deterministic defaults, validates every kind-specific field, keeps persisted goals untouched until a successful save, makes kind immutable after creation, preserves failed drafts, and re-presents saved progress and standing after edits.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/GoalFormModelTests" }
    required: true
  - id: C3
    statement: Goal Detail presents consistent kind-specific progress and complete history, permits only valid Today or Yesterday appends and deletes, keeps closure manual, supports harvested, let-go, and reopened states, and performs confirmed cascade deletion without optimistic state drift on failure.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/GoalDetailModelTests" }
    required: true
  - id: C4
    statement: From a cold launch the owner can select the Goals destination; create both goal kinds; inspect grouped progress; add and remove eligible progress; edit; harvest, let go, and reopen; and permanently delete through one persistent, accessible UI journey.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/GoalExperienceUITests" }
    required: true
  - id: C5
    statement: Adding Goals to the root shell preserves the existing cold-launch, background-selection, Today dashboard, habit-management, habit-detail, fast-logging, and reminder behavior without a placeholder Journal destination.
    polarity: preserve
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests" }
    baseline:
      surface: "App/Tend existing shell, Today, and Habits behavior"
      captured_at: { kind: git_tree, value: "git:d4ea77a0b00d770f8f0841ff52d9b1200c7f9ebd", path: App/Tend, observed_at: "2026-08-14T22:43:29Z" }
    required: true
  - id: C6
    statement: On compact iPhone and landscape, the Goals roster and selected Goals tab match the Goals reference board in the external tend.pen comp, while forms and detail extend the existing Almanac field, surface, progress, color, typography, spacing, and no-shadow grammar.
    polarity: introduce
    binding: { type: manual }
    required: true
  - id: C7
    statement: The complete Goals journey remains legible through two larger Dynamic Type steps, exposes meaningful VoiceOver labels, progress values, standing, disclosure, and selected states, keeps controls at least 44 points, distinguishes state without color, and honors Reduce Motion.
    polarity: introduce
    binding: { type: manual }
    required: true
---

# Acceptance

C1 through C3 bind the roster, form, and detail behavior to deterministic app-model tests while leaving goal arithmetic and persistence semantics with goals/goal-lifecycle (F-5aficd). C4 proves the owner can complete the whole Goals journey against one persistent store. C5 is the required brownfield guard: the shared shell changes, so the existing Today and Habits journeys must remain green from the recorded pre-change tree. C6 binds visual fidelity to the Goals board and the already approved Almanac grammar; C7 covers accessibility and adaptive presentation that screenshots cannot establish.

All seven criteria are satisfiable inside goals/goal-experience (F-xowx7x). Goal domain records, progress math, standing, and lifecycle operations belong to its prerequisite. Conditional goal cards on Today belong to goals/today-goal-surfacing (F-e8yd2r). The Journal destination belongs to journal (E-l8goi4), so neither is required for this feature to pass its own gate.
