# Connect permission, mutations, and notification routing

## Approach

Compose the app around
device-readiness/local-reminders/notification-reconciliation (T-oeg8ua). Begin
with failing integration tests that drive the existing public model actions and
a fake reminder runtime. Keep the app's habit and logging transactions
authoritative; refresh is a post-success side effect.

Own one reminder runtime for the ready model container. It retains the
coordinator, a small authorization controller, a process-lifetime
UNUserNotificationCenter delegate, and an app routing model. Start one refresh
when the container becomes ready and request another whenever the scene becomes
active. Retry after store recovery by building the runtime for the replacement
container; never create it while the store is failed.

Request `.alert` and `.sound` authorization from the user's reminder gesture.
When `HabitFormView` changes a draft from no reminder to a time, ask only if
authorization is not determined. Do not prompt for a draft that already had a
reminder, time or pin edits, app launch, foreground entry, or persisted reminder
facts. Permission denial leaves the draft and saved value intact, schedules
nothing, and does not produce a repeated request. After the authorization call
resolves, request reconciliation.

Add one injected, default-no-op post-success reminder-refresh closure at the
existing mutation boundaries rather than duplicating scheduling logic inside
them. Exercise it after successful:

- HabitForm creation and update;
- HabitRoster and HabitDetail archive and reactivation;
- HabitRoster deletion;
- Today current/grace append, set-total, entry deletion, and Undo; and
- HabitDetail editable-entry deletion.

Do not request refresh after validation refusal, Cancel, a persistence throw, an
ineligible or duplicate interaction, or a read-only refresh. Preserve each
model's existing failure, retry, animation, haptic, Undo, and dismissal timing.
The reminder runtime coalesces the valid signals.

Install the notification delegate before responses can arrive and keep it alive
for the process. A Tend response changes the shared shell selection to Today on
the main actor. Move `AlmanacShellView`'s private selection behind an injected
binding or routing model so notification responses and ordinary tab buttons
write the same state. Preserve Today as cold-launch default and the existing
accessibility-focus handoff. Ignore non-Tend responses. Do not open a log sheet,
choose a habit row, or mutate data from a response.

## Surfaces

- Add app composition, authorization, delegate, refresh-signal, and routing
  types under `App/Tend/Application/` or `App/Tend/Reminders/`, whichever keeps
  UserNotifications ownership together without a second coordinator.
- Update `TendApp.swift`, `TendApplicationModel.swift`,
  `TendRootView.swift`, `AlmanacShellView.swift`, and only the shell support
  needed for shared selection.
- Update `HabitFormView` or its model boundary, `HabitRosterModel`,
  `HabitDetailModel`, and `TodayLoggingModel` at their existing successful
  mutation seams.
- Add `App/TendTests/ReminderAppIntegrationTests.swift`; extend existing model
  tests where that is the clearest behavioral proof.
- Do not change SwiftData models, TendCore operations, visual tokens, habit-form
  layout, Today copy, logging semantics, notification content/planning, or
  project device support.

## Tests

Use the real app models with in-memory persistence, injected operation failures,
a refresh spy, fake authorization, and a direct notification-response adapter.
Cover:

- no permission request at app construction, ready-store entry, foreground
  entry, or loading a persisted reminder;
- exactly one request on the first no-reminder-to-time gesture, alert-and-sound
  options, denial preserving state, no second prompt, and reconciliation after
  resolution;
- every listed successful mutation requesting refresh once, including weekly
  grace writes and Undo;
- validation failure, Cancel, mutation failure, retry before success, duplicate
  tap, and read-only refresh producing no premature signal;
- ready, failed, retry-to-ready, and repeated scene-active lifecycle behavior;
- Tend notification responses selecting Today from Habits and preserving Today
  on cold launch, with non-Tend responses ignored;
- ordinary tab selection and accessibility focus after selection becomes
  externally owned; and
- coordinator failure leaving habit/log success and existing user-facing
  failure behavior unchanged.

Run:

- `Scripts/tiller-xcode-test TendTests/ReminderAppIntegrationTests`
- `Scripts/tiller-xcode-test TendTests/HabitFormModelTests`
- `Scripts/tiller-xcode-test TendTests/HabitRosterModelTests`
- `Scripts/tiller-xcode-test TendTests/HabitDetailModelTests`
- `Scripts/tiller-xcode-test TendTests/TodayLoggingModelTests`
- `Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination
  'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

The smoke test installs a development build on the owner's iPhone, creates one
daily and one weekly pinned reminder a few minutes ahead, backgrounds Tend, and
observes delivery. It then completes another scheduled current bucket before
its time and observes silence, opens Habits, taps a delivered reminder, and
observes Today. A fresh permission reset verifies denial does not disable Save
or prompt again.

## Edge cases

- The authorization callback and notification response may arrive off the main
  actor; all observable app and shell state changes hop to the main actor.
- A notification can be tapped before the SwiftData container is ready; retain
  the Today route and apply it when the shell appears.
- Store retry replaces, rather than duplicates, the coordinator and its
  container-bound context.
- Deleting the last entry can make a current bucket unmet and must restore a
  still-future reminder.
- Deleting, archiving, or clearing a reminder must not leave a stale request
  until the next foreground.
- Notification refresh must not extend a five-second Undo window, duplicate
  haptics, delay Save dismissal, or convert a successful write into a visible
  failure.
