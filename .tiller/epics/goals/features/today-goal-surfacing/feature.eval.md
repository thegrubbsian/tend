---
node: F-e8yd2r
criteria:
  - id: C1
    statement: Today projects every open Goal from one explicit refresh context, includes exactly unavailable, behind, past-due, or owner-calendar seven-day-window rows, excludes closed and distant on-pace rows, preserves persistent identity, orders urgency deterministically, and isolates computation failures without inventing facts or suppressing valid siblings.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/TodayGoalModelTests" }
    required: true
  - id: C2
    statement: The existing single Today refresh path atomically updates habits, conditional Goals, and the All tended claim after Goal query changes, scene and environment changes, local-day rollover, the earliest domain-reported standing transition, and retry, without adding a timer, notification, write, or second scheduler.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/TodayGoalRefreshTests" }
    required: true
  - id: C3
    statement: Today renders an omitted-when-empty GOALS section below all habit sections with truthful Accumulate and Measure progress, deadline and standing text, unavailable retry, accessible adaptive layout, and no card action, while first-launch, inactive-only, mixed-habit, and all-tended states compose honestly.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/TodayGoalSurfacingUITests" }
    required: true
  - id: C4
    statement: A human confirms the GOALS section matches the Today v2 reference board and Almanac grammar on compact iPhone and centered iPad, including two larger Dynamic Type steps, VoiceOver reading, contrast, forced light appearance, Reduce Motion, and floating-pill clearance.
    polarity: introduce
    binding: { type: manual }
    required: true
  - id: C5
    statement: Adding conditional Goals to Today preserves existing habit Today projection, dashboard, fast logging, shell selection, Goals roster and detail, habit management and detail, reminders, first launch, persistence, and relaunch behavior.
    polarity: preserve
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests && Scripts/tiller-xcode-test TendUITests" }
    baseline:
      surface: "App/Tend existing Today, Goals, Habits, shell, logging, and reminder behavior"
      captured_at: { kind: git_tree, value: "git:9c2834f2fb000735b50b3fd2ae330714258cf135", path: App/Tend, observed_at: "2026-08-15T02:30:55Z" }
    required: true
---

# Acceptance

C1 binds the eligibility, identity, ordering, and honest failure boundary. C2 binds time-sensitive entry and exit to the one established Today refresh architecture. C3 proves owner-visible composition and the absence of invented actions or notifications. C4 keeps the small but distinctive Today v2 visual addition under human review. C5 protects every existing surface touched by extending the shared Today model and destination.

All five criteria are satisfiable inside goals/today-goal-surfacing (F-e8yd2r) after its recorded prerequisites. Goal data, progress arithmetic, standing, closure, and mutations stay with the goal domain features. The complete Goals roster and detail remain with goals/goal-experience (F-xowx7x). Habit cards and their logging affordances remain with the existing app-experience features.
