---
node: F-zbcv8j
criteria:
  - id: C1
    statement: The deterministic reminder planner produces one future local occasion per daily habit day and weekly pinned weekday, never multiplies by target, excludes inactive, no-time, no-pin, past, and met-current-bucket occasions, restores an eligible current occasion when that bucket becomes unmet, handles DST and time-zone boundaries, gives every eligible habit its next occasion, and caps the stable chronological plan at 64 requests.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/ReminderPlanTests" }
    required: true
  - id: C2
    statement: The reminder coordinator derives current facts through TendCore, maps the plan to stable Tend-owned one-shot notification requests, serializes and coalesces refreshes, removes only obsolete or changed Tend requests, adds only missing requests, isolates malformed habits, retries transient failures on a later refresh, and leaves no pending Tend requests while authorization is denied.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/ReminderCoordinatorTests" }
    required: true
  - id: C3
    statement: The app requests alert-and-sound authorization only when a user first enables a reminder from the habit form, never at launch or for persisted data, preserves the habit setting after denial without re-prompting, refreshes reminders after every specified successful habit or editable-log mutation and foreground activation, and routes a Tend notification tap to Today without performing a log action.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/ReminderAppIntegrationTests" }
    required: true
  - id: C4
    statement: On the owner's physical iPhone, one daily notification and two pinned occasions for one weekly habit visibly fire at temporary scheduled times with the habit name and truthful due text, the later pinned occasion remains silent after the weekly bucket is completed, tapping a delivered Tend reminder opens Today from Habits and from a cold launch, and declining the in-context prompt leaves habit editing usable without a repeated prompt.
    polarity: introduce
    binding: { type: manual }
    required: true
  - id: C5
    statement: Existing habit creation and editing, archive, reactivation, deletion, current and grace logging, Undo, Habit Detail entry deletion, Today presentation, and ordinary two-tab shell navigation remain unchanged around reminder refresh side effects, including persistence-failure and notification-failure isolation.
    polarity: preserve
    baseline:
      surface: Habit management, editable logging, Today presentation, and shell behavior before Local Reminders
      captured_at:
        kind: git_tree
        value: git:ed6128d833ec69a05ccabf70f548a090d5e17835
        path: App/Tend
        observed_at: 2026-08-09T02:43:44Z
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests && Scripts/tiller-xcode-test TendUITests/HabitManagementUITests && Scripts/tiller-xcode-test TendUITests/FastLoggingUITests && Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests" }
    required: true
  - id: C6
    statement: The native iPhone-only application compiles with the local-reminder integration under the existing Swift 6 and iOS 26 generic-device build contract without code signing.
    polarity: introduce
    binding: { type: command, run: "xcodebuild -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build" }
    required: true
---

# Acceptance

Local Reminders is accepted only when the pure plan, system reconciliation,
application wiring, preserve suite, generic build, and physical-device behavior
all agree. Simulator delivery alone does not replace the physical-iPhone check
because the product contract explicitly requires reminder firing and suppression
on the owner's device.
