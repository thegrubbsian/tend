---
node: F-wf19av
criteria:
  - id: C1
    statement: The root shell exposes exactly Today, Goals, Habits, and Journal in that order, routes Journal overview, entry, and dated compose requests through one local identity-safe model, preserves the active destination across backgrounding, and restores Today after relaunch.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/JournalRoutingModelTests && Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests" }
    required: true
  - id: C2
    statement: The Journal overview truthfully projects today's page, reverse-chronological first-line rows, and a deterministic binary month garden from durable entries, refreshes at query and local-context boundaries, and reports invalid data without inventing empty history, missed days, counts, or streaks.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/JournalOverviewModelTests" }
    required: true
  - id: C3
    statement: The Journal editor creates nothing on open, automatically creates after debounced non-whitespace prose, automatically edits every later body including empty content, flushes before navigation and backgrounding, retains unsaved text with Retry after failure, and permits deletion only for today or yesterday while keeping old prose editable forever.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/JournalEditorModelTests && Scripts/tiller-xcode-test TendUITests/JournalEditingUITests" }
    required: true
  - id: C4
    statement: Every written entry renders that LocalDate's live Habit garden from current Habit history without storing or mutating a snapshot, updates after real Habit changes, and isolates malformed Habit rows without suppressing valid siblings.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-swift-test Tests/TendCoreTests/History/JournalDayGardenQueryTests.swift && Scripts/tiller-xcode-test TendTests/JournalDayGardenModelTests && Scripts/tiller-xcode-test TendUITests/JournalDayGardenUITests" }
    required: true
  - id: C5
    statement: The complete Journal journey covers empty, today-written, yesterday-back-fill, old-entry edit, legal delete, forbidden delete, month navigation, relaunch, and truthful load and save failures without search, reminders, habit logging, streaks, targets, prompts, or verdicts.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/JournalExperienceUITests" }
    required: true
  - id: C6
    statement: A human confirms the Journal overview, editor, entry page, binary month garden, live Habit garden, fourth tab, keyboard avoidance, and error states match the Journal reference board and Almanac grammar on iPhone, including landscape, two larger Dynamic Type steps, VoiceOver, contrast, forced light appearance, Reduce Motion, and floating-pill clearance.
    polarity: introduce
    binding: { type: manual }
    required: true
  - id: C7
    statement: Adding the Journal destination and experience preserves existing Today, Goals, Habits, logging, history, shell focus and selection, reminders, first launch, persistence, accessibility, and relaunch behavior.
    polarity: preserve
    binding: { type: command, run: "Scripts/tiller-xcode-test TendTests && Scripts/tiller-xcode-test TendUITests && Scripts/tiller-swift-test" }
    baseline:
      surface: "App/Tend and Sources/TendCore owner journeys before the Journal destination"
      captured_at: { kind: git_tree, value: "git:ac3ece4dfda620e906f28d35a6028f133679ec67", path: App/Tend, observed_at: "2026-08-19T22:23:34Z" }
    required: true
---

# Acceptance

C1 binds the fourth destination and route identity. C2 binds today's lead, history, and the non-judgmental month garden. C3 makes the answered automatic-save decision executable and failure-safe. C4 protects the live, non-denormalized relationship to Habit history. C5 proves the owner journey and explicit v1 omissions. C6 reserves visual and accessibility judgment for a human. C7 protects the mature app shell and every existing owner path.

All seven criteria are satisfiable inside journal/journal-experience (F-wf19av) after journal/journal-entry-records (F-rsayqb). The later Today invitation is not required for this feature to pass; it consumes the destination and editor route established here.