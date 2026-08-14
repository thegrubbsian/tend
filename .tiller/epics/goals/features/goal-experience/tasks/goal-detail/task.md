# Build Goal Detail and progress actions

## Approach

Build Goal Detail on goals/goal-experience/goal-form (T-ozqgzt) and the public
query, progress, entry, lifecycle, and deletion operations supplied by
goals/goal-lifecycle (F-5aficd). Begin with `GoalDetailModelTests`; prove the
presentation and mutation state machine before writing SwiftUI.

Add a main-actor observable `GoalDetailModel` that owns the selected persisted
goal identity, injected current instant and calendar, current presentation,
sheet and confirmation state, loading failure, and inline operation failure.
The model loads one domain snapshot and formats owner-visible facts without
recomputing progress, expected progress, standing, effective readings, or
closure semantics.

The presentation must include:

- goal metadata, standing, closure state, deadline, and localized days
  remaining or past-due wording;
- normalized accumulate or measure progress facts for one shared progress
  component;
- every entry or reading in reverse chronological order, including all
  same-day measure readings and which one is effective;
- add and delete eligibility supplied by the domain boundary;
- Edit, Harvest, Let go, Reopen, and Delete availability.

Create a reusable kind-specific progress view. Accumulate shows the truthful
fraction, clamped track fill, and optional pace tick. Measure shows the directed
baseline-to-target span, latest marker, endpoint labels, truthful current value,
traveled fraction, and optional pace tick. It accepts presentation facts only;
it performs no goal arithmetic and is reusable by the roster task.

Build separate compact progress-entry sheet content for accumulate and measure
goals. Both choose Today or Yesterday in the owner's calendar. Accumulate
accepts a positive integer amount; Measure accepts a signed integer reading.
Save appends through the domain operation and reloads the saved snapshot.
Deleting an eligible recent item uses the domain delete operation and reloads.
Older items remain visible without an action. Never simulate editing an item.

Present the existing `GoalFormView` from Edit. Open goals expose Harvest and Let
go as distinct deliberate actions. Closed goals expose Reopen and no progress
mutation. Permanent Delete requires a confirmation naming the goal and its
history. Every mutation keeps the last saved presentation until success and
retains enough context to retry or cancel after failure.

Build `GoalDetailView` as a full-screen destination with Almanac progress,
metadata, history, and action sections. The view owns layout and accessibility;
the model owns state transitions. Back dismisses to its caller. This task does
not add roster selection or alter the root shell.

## Surfaces

- Create `App/Tend/Goals/GoalProgressView.swift`.
- Create `App/Tend/Goals/GoalDetailModel.swift`.
- Create `App/Tend/Goals/GoalDetailView.swift`.
- Create `App/Tend/Goals/GoalProgressEntrySheet.swift`.
- Create `App/TendTests/GoalDetailModelTests.swift`.
- Reuse `App/Tend/Goals/GoalFormView.swift` without moving goal behavior into
  shared habit UI.
- Modify the Xcode project only if required for new file discovery.
- Do not modify TendCore arithmetic, shell destinations, Today, reminders, or
  the Pencil comp.

## Tests

Write `GoalDetailModelTests` with an injected clock, calendar, snapshots, and
throwing operations. Cover increasing and decreasing measure facts;
over-achieved accumulate facts; no-deadline, behind, past-due, harvested, and
let-go presentations; multiple same-day readings and effective marking;
reverse chronology; Today and Yesterday append payloads; rejected old or future
dates; positive accumulate validation; signed measure validation; eligible and
ineligible deletes; Edit refresh; Harvest, Let go, Reopen, and Delete success;
and no optimistic drift plus context retention for every thrown operation.

Run:

- `Scripts/tiller-xcode-test TendTests/GoalDetailModelTests`
- `Scripts/tiller-xcode-test TendTests/GoalFormModelTests`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination
  'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Manually inspect open accumulate, open increasing and decreasing measure,
past-due, harvested, and let-go details at compact width and two larger Dynamic
Type steps. Verify progress is understandable with VoiceOver and without color,
history actions name their effects, and every control meets the 44-point floor.

## Edge cases

- A goal at or beyond target remains open until Harvest or Let go succeeds.
- A past-due goal can be harvested, let go, edited, or deleted; it is never
  called failed.
- Over-target readings clamp only the marker. Owner-visible values remain
  truthful.
- Multiple measure readings on one day remain listed; only the latest is marked
  effective.
- Midnight, time-zone, and daylight-saving changes use local calendar-day
  eligibility rather than elapsed 24-hour arithmetic.
- Closed goals remain editable but cannot append or delete progress until
  reopened.
- Failed close, reopen, append, delete-item, edit, or delete-goal operations
  leave navigation and the last saved facts intact.
- An initially malformed or incomplete persisted snapshot produces an honest
  retryable load failure, never zero progress or fabricated history.
