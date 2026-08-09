# Reconcile reminder plans with UserNotifications

## Approach

Build the system adapter on
device-readiness/local-reminders/reminder-planning (T-ir12jz). Start with a fake
notification center and failing tests; production UserNotifications calls arrive
only after the reconciliation contract is green.

Define a narrow async notification-center client for authorization status,
authorization request, Tend-owned pending request snapshots, removal by
identifier, and add-or-replace. Keep UNUserNotificationCenter,
UNNotificationRequest, UNMutableNotificationContent, and
UNCalendarNotificationTrigger mapping behind the live client. Use documented
calendar triggers with one-shot local components, default sound, no badge, and a
Tend reminder category/user-info marker.

On the main actor, fetch persisted habits and derive current facts with
`HabitTodayComputation` at one sampled instant and time zone. Invalid or
unreadable habits contribute no desired requests while valid habits continue.
Pass the complete fact set to the planner from T-ir12jz.

Reconcile only when authorization permits delivery. Denied, not-determined, and
otherwise unavailable states produce an empty desired Tend schedule; this task
never raises a prompt. For deliverable authorization, compare projected pending
values with the desired plan. Remove obsolete requests, replace same-identifier
requests whose fire components or content changed, and add missing requests.
Never remove a non-Tend request.

Make refresh idempotent and serialize it. A request arriving during an active
pass marks another pass necessary; after the current pass finishes, resample
persisted facts and run once more. Do not queue one task per mutation or allow an
older async response to reapply stale requests after a newer refresh.

Treat truthful suppression as more important than retaining stale delivery:
remove obsolete Tend requests even when another add fails. Preserve domain data,
finish processing independent habits and requests where safe, retain a
diagnostic error for tests and development, and let the next refresh retry from
persisted facts. Do not add a timer, persistent retry queue, telemetry, or
network recovery.

## Surfaces

- Add the notification-center client, production adapter, pending-request value
  projection, and reminder coordinator under `App/Tend/Reminders/`.
- Add `App/TendTests/ReminderCoordinatorTests.swift`.
- Reuse `HabitTodayComputation` and the planner from T-ir12jz.
- Import UserNotifications only in the app target's live adapter and
  notification-response boundary.
- Do not request permission from foreground reconciliation, modify any habit or
  log mutation path, install the process delegate, change shell selection, add a
  SwiftData model, or introduce background execution in this task.

## Tests

Use an in-memory TendCore container, real Habit and bucket computations, the real
planner, and a fake notification-center client. Cover:

- one sampled instant/time zone per pass and exact daily/weekly request mapping;
- authorized, provisional/otherwise deliverable, not-determined, denied, and
  settings-disabled states;
- empty, unchanged, missing, obsolete, changed-content, changed-time, met,
  archived, deleted, and no-pin plans;
- stable one-shot calendar components, title/body/default-sound facts, Tend
  ownership markers, and exact identifier replacement;
- preserving non-Tend pending requests;
- malformed-habit isolation with stale request removal and valid-habit
  scheduling in the same pass;
- remove and add failures without domain rollback, followed by a successful
  retry;
- overlapping refresh requests coalescing into one resampled follow-up pass,
  never concurrent center writes; and
- the real 64-request plan entering the adapter without truncation or duplicate
  identifiers.

Run `Scripts/tiller-xcode-test TendTests/ReminderCoordinatorTests`,
`Scripts/tiller-xcode-test TendTests/ReminderPlanTests`, and
`xcodebuild -project Tend.xcodeproj -scheme Tend -destination
'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`.

The smoke test uses the fake center to seed one stale Tend request and one
foreign request, reconciles two active habits, meets one current bucket,
reconciles again, and observes the stale and met requests removed, the other
habit retained, and the foreign request untouched.

## Edge cases

- Authorization can change while a pass is running; a queued refresh must
  resample it.
- UserNotifications may return pending requests in any order.
- A request with Tend's prefix but malformed identity is still Tend-owned and is
  removed rather than trusted.
- Replacing a request keeps its stable identifier while changing content or
  trigger facts.
- A failed add never causes the coordinator to resurrect an obsolete request.
- Model-container failure remains owned by TendApplicationModel; the coordinator
  starts only after a container exists.
