---
node: F-0rn0hs
criteria:
  - id: C1
    statement: Today projects exactly one Journal invitation only while the current local day's entry is absent, removes and restores it after real create and delete mutations, refreshes at local-day and environment boundaries, and isolates Journal query failures without changing Habit, Goal, or All tended truth.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/TodayJournalInvitationModelTests && Scripts/tiller-xcode-test TendTests/TodayJournalRefreshTests" }
    required: true
  - id: C2
    statement: Today renders an omitted-when-complete JOURNAL section after all Habit and Goal sections with one accessible invitation or one truthful retry state, no obligation semantics, and no inline editor or invented Journal controls.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/TodayJournalInvitationUITests" }
    required: true
  - id: C3
    statement: Activating the invitation selects the existing Journal destination and opens today's exact editor once, while saving or deleting through that destination updates Today without duplicate entries, routes, refresh loops, or relaunch.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/TodayJournalMutationJourneyUITests" }
    required: true
  - id: C4
    statement: A human confirms the Journal invitation follows the Journal and Today reference boards and Almanac grammar on compact iPhone, including two larger Dynamic Type steps, VoiceOver order and action naming, contrast, Reduce Motion, and floating-pill clearance.
    polarity: introduce
    binding: { type: manual }
    required: true
  - id: C5
    statement: Adding the conditional Journal invitation preserves existing Today Habit and Goal projection, ordering, logging, retries, first-launch and All tended composition, shell selection, reminders, persistence, and relaunch behavior.
    polarity: preserve
    binding: { type: command, run: "Scripts/tiller-xcode-test TendTests && Scripts/tiller-xcode-test TendUITests" }
    baseline:
      surface: "App/Tend Today, shell, logging, Goals, Habits, reminders, persistence, and relaunch behavior before the Journal invitation"
      captured_at: { kind: git_tree, value: "git:ac3ece4dfda620e906f28d35a6028f133679ec67", path: App/Tend, observed_at: "2026-08-19T22:23:34Z" }
    required: true
---

# Acceptance

C1 binds the invitation to today's durable entry existence and the existing atomic refresh architecture. C2 binds its quiet composition and honest failure state. C3 proves the route crosses into the one Journal editor and returns real mutations to Today. C4 reserves the compact Almanac and accessibility judgment for a human. C5 protects the mature daily surface this feature extends.

All five criteria are satisfiable inside journal/today-journal-invitation (F-0rn0hs) after journal/journal-experience (F-wf19av). The Journal record, editor, destination, and save semantics remain owned by the dependency; this feature owns only Today's projection, card, route request, and regression boundary.