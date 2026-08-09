# Local Reminders

## Summary

Tend delivers private, on-device reminders through Apple's UserNotifications
framework. Reminders mirror the habit configuration already stored by Habit
Management: a daily habit can remind once each day, and a weekly habit can
remind once on each pinned weekday. Tend never contacts a server and does not
add push, analytics, or a second reminder data model.

The feature uses bounded, nonrepeating notification requests rather than
repeating triggers. A repeating trigger cannot omit only the current occasion
after its bucket becomes met without also losing later occasions. A
deterministic rolling plan lets Tend cancel the exact current-bucket requests
while retaining future reminders.

## Permission

Notification authorization is requested in context, when a New or Edit habit
draft first changes from no reminder to a reminder time and the system status is
not determined. Tend never requests authorization at first launch, on ordinary
foreground entry, or merely because persisted reminder data exists.

The request asks only for alerts and sounds. Editing an existing reminder,
changing its time, or toggling pinned days does not prompt again. A declined or
previously denied request leaves the reminder time in the saved habit, schedules
nothing, and does not loop the prompt. If the owner later enables notifications
in Settings, the next foreground reconciliation schedules the saved reminders.

Authorization and scheduling are side effects of the reminder setting, not part
of the habit transaction. A successful habit or log write remains successful if
the system prompt is declined or UserNotifications returns an error.

## Reminder occasions

An occasion is eligible only when the habit is active and has a valid reminder
time:

- A daily habit has one occasion at that local time on each calendar day.
- A weekly habit has one occasion at that local time on each pinned local
  weekday.
- A weekly habit with no pinned weekdays has no occasions, even when it retains
  a reminder time.
- Target size does not multiply reminders. A target of three still produces one
  request for the occasion.
- An occasion whose local time has passed is never scheduled retroactively.

The current bucket controls suppression. Once its requirement is met, every
remaining occasion in that same daily or Monday-through-Sunday weekly bucket is
absent from the plan. Future buckets remain scheduled. If deleting a still
editable entry makes the current bucket unmet again before an eligible
occasion, reconciliation restores that request. Archiving, deleting, or
clearing a reminder removes all future requests for the habit; reactivation or
an eligible edit rebuilds them from current facts.

Each request has a stable Tend-owned identifier derived from the habit identity
and local occasion. Its title is the habit name. Its body states the remaining
requirement and whether it is due today or this week, using the same localized
amount formatting as the app. Future buckets use the configured target; the
current bucket uses its reconciled progress. Requests use the default
notification sound and have no actions.

## Rolling schedule

The planner is a pure, deterministic transformation of persisted habit facts,
current-bucket projections, an injected instant, calendar, time zone, and a
request limit. It produces at most 64 future one-shot requests, the platform
pending-notification limit. It first reserves the next eligible occasion for
each habit, then fills remaining capacity in chronological order with stable
tie-breaking. Under the product's expected dozen-habit scale, every eligible
habit therefore retains a next reminder while frequent app use keeps the
rolling window full.

Reconciliation reads only Tend-owned pending requests, removes obsolete or
changed identifiers, and adds missing requests. It never cancels a request it
does not own. Concurrent refresh requests are coalesced and serialized so an
older asynchronous pass cannot overwrite a newer plan.

Tend requests reconciliation:

- after the model container becomes ready and whenever the app becomes active;
- after successful habit creation, edit, archive, reactivation, or deletion;
- after successful current- or grace-bucket append, set-total, entry deletion,
  or Undo; and
- after notification authorization resolves.

Foreground reconciliation is the recovery path for app termination, device
time-zone or calendar changes, a prior UserNotifications failure, and settings
changes. It rebuilds local occasions from the current calendar instead of
persisting schedule state. No background refresh task is required.

## Notification response

An app-owned notification-center delegate is installed for the lifetime of the
process. Tapping a Tend reminder selects Today whether Tend is launching, in the
background, or currently showing Habits. The response does not open a logging
surface or mutate a habit. Non-Tend notification responses are ignored.

The shell receives its selection from an app-owned routing model rather than
maintaining an unreachable private selection. Ordinary tab taps continue to
change the same selection and retain the existing accessibility focus behavior.

## Failure handling

One malformed or temporarily unreadable habit does not prevent reminders for
other habits. Its stale Tend-owned requests are removed because the app cannot
prove they are truthful. Planner and notification-center failures do not alter
Habit, Bucket, or LogEntry data; a later foreground or mutation refresh retries
from persisted facts.

The scheduler treats denied authorization as a stable empty schedule, not an
error. It adds no telemetry, network recovery, retry timer, settings screen, or
notification-specific persistence.

## Architecture

The implementation has three boundaries:

1. A value-based reminder planner owns eligibility, local occurrence
   enumeration, current-bucket suppression, content facts, stable identifiers,
   ordering, and the 64-request cap. It imports no UserNotifications types.
2. A reminder coordinator adapts the planner to HabitTodayComputation and
   UNUserNotificationCenter behind injected authorization and pending-request
   operations. It owns reconciliation, coalescing, and retry-safe failure
   isolation.
3. The application integration owns the in-context permission gesture, refresh
   signals from existing successful mutation paths and scene activation, the
   long-lived notification delegate, and the shared shell route.

No SwiftData schema change is needed. Reminder time and pinned weekdays remain
owned by Habit, while bucket progress remains owned by the existing TendCore
computations.

## Boundaries

- Local notifications only. No remote push, server, network call, account,
  analytics, or third-party runtime dependency.
- No actionable notification, notification logging, snooze, badge count,
  custom sound, reminder history, settings screen, widget, or background task.
- No duplicate reminder configuration outside Habit.
- No change to cadence, bucket, grace, streak, requirement-snapshot, logging, or
  habit-lifecycle semantics.
- No guarantee of indefinite reminders while Tend is never opened; the bounded
  rolling plan is replenished by normal foreground and mutation activity.

## Verification

Automated app tests prove deterministic daily and weekly occurrence planning,
current-bucket suppression, no-pin and inactive exclusion, past-time behavior,
DST and time-zone boundaries, fair 64-request capacity, stable reconciliation,
authorization state handling, mutation refresh signals, and notification-tap
routing.

Physical-iPhone acceptance uses short temporary reminder times to observe one
daily and one weekly pinned notification, verifies that another current-bucket
occasion is silent after completion, and verifies that tapping a delivered
notification opens Today. The device run also confirms that declining the
in-context authorization request leaves habit editing usable without a repeated
prompt.
