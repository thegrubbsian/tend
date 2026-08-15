# Goal Lifecycle and Standing

## Summary

Provide the persistence-aware TendCore rules that decide where an open goal
stands and let the owner rescope, close, reopen, or permanently delete its arc.
Standing stays derived from current progress, creation time, optional deadline,
and the evaluation instant. Closure stores only the owner's deliberate choice.

This feature builds on goals/goal-records (F-e149jw) for the durable Goal,
accumulate entries, measure readings, and kind-specific progress computation.
It does not duplicate progress math or append/delete-item rules. It owns
deadline expectation, open standing, durable closure disposition, goal-field
updates, reopening, and cascade deletion.

The feature is domain-only. Goals screens and confirmations belong to
goals/goal-experience (F-xowx7x); conditional Today cards belong to
goals/today-goal-surfacing (F-e8yd2r). Notifications, habit linking,
maintenance goals, non-integer quantities, milestones, and trend charts remain
out of scope.

## Durable lifecycle state

Represent closure with one optional persisted disposition on Goal:

- `nil` means open;
- `harvested` means the owner chose to call the arc complete;
- `letGo` means the owner chose to stop pursuing it.

Existing goals introduced by the prerequisite migrate as open. Persist neither
standing, expected progress, completion, nor a failure verdict. Those facts are
derived and can change after a progress item, clock change, deadline edit, or
target edit. Do not add a closed timestamp, success boolean, automatic status
transition, or duplicate open flag without a product rule that needs it.

The schema and model values must round-trip both dispositions, preserve every
goal and progress relationship during migration, and reject unknown stored enum
values through the existing honest store-failure boundary rather than treating
them as open.

## Deadline interpretation

A deadline is an owner-selected calendar date, not a stored time-of-day. Resolve
it with the caller's calendar and time zone. The deadline remains active for
its entire local day and expires at the start of the following local day. That
exclusive instant is the deadline boundary used by both pace and past-due
calculation.

Creation time is the start of the pace interval. A deadline is valid when its
exclusive boundary is later than creation time. This permits a goal created
during its deadline day and permits an edit that makes an existing goal
immediately past due, while refusing a date whose full day ended before the arc
began.

Daylight-saving and time-zone changes use calendar resolution, not a fixed
24-hour day. The stored calendar date does not acquire a historical time-zone
snapshot. Each computation uses the explicit calendar and time zone supplied
for the owner's current view.

## Progress expectation and standing

Consume the normalized progress result from goals/goal-records (F-e149jw).
Accumulate over-achievement may exceed one; measure progress at or beyond its
target is complete. Reject malformed, non-finite, negative, or kind-mismatched
progress input with a typed error instead of repairing it.

For an open goal:

- **On pace:** no deadline exists, or actual normalized progress is greater
  than or equal to linear expected progress.
- **Behind:** a deadline exists, the deadline boundary is still in the future,
  and actual normalized progress is below expectation.
- **Past due:** the evaluation instant is at or after the deadline boundary.

Past due wins regardless of progress. An open goal at or beyond its target is
still past due after the deadline because reaching the number never closes the
goal. A goal without a deadline has no expected-progress value and remains on
pace while open.

For a valid deadlined goal before its boundary, expected progress is linear
elapsed time divided by the complete creation-to-boundary duration, clamped to
zero through one. At creation it is zero. Equality counts as on pace. The
calculation receives an explicit evaluation instant and rejects an instant
before creation rather than projecting backward.

Return one immutable, Sendable standing snapshot containing:

- the standing;
- actual normalized progress from the progress result;
- optional expected normalized progress;
- the resolved deadline boundary when one exists;
- the next instant after which standing can change from time alone.

With no deadline or for a closed goal, no time-only refresh exists. A behind
goal next changes at its deadline boundary. An on-pace deadlined goal next
changes when linear expectation overtakes its unchanged progress, or at the
deadline boundary when progress is already complete. Consumers recompute after
progress or configuration mutations; the snapshot never schedules work itself.

Closed goals have a closure disposition and no standing. Reopening clears the
disposition, after which a fresh computation derives on-pace, behind, or
past-due from the current instant and current configuration.

## Editable goal fields

Expose one value type for owner-editable fields: name, target, unit, optional
deadline, and kind-appropriate baseline. Update accepts that value but no kind
parameter, making conversion between Accumulate and Measure unrepresentable
through the supported API. Created-at remains immutable.

Normalize and validate the complete proposed value before mutation:

- trim leading and trailing whitespace from name and unit;
- reject an empty normalized name or unit;
- require a positive integer target;
- require no baseline for Accumulate;
- require an integer baseline different from target for Measure;
- require any deadline's exclusive boundary to follow creation time.

Update is permitted for open and closed goals. Apply all editable fields
together and save once. Changing target, baseline, or deadline does not snapshot
the old arc and does not rewrite progress history. The next progress and
standing computation evaluates the entire existing history against the new
configuration immediately.

Kind remains immutable. An owner who needs the other kind deletes and creates a
new goal; no conversion, copied history, or compatibility alias belongs here.

## Closing and reopening

Closing always requires an explicit `harvested` or `letGo` disposition. It is
legal from on pace, behind, past due, below target, at target, or beyond target.
Validate that the Goal belongs to the operation's ModelContext and is open,
assign the requested disposition, and save once.

Reopening requires a persisted closed goal. Clear the disposition and save
once. Do not change progress items, configuration, creation time, or deadline.
A repeated close, close with no disposition, or repeated reopen is a typed
error, not a no-op.

While closed, the prerequisite append and delete-item operations must reject
progress mutation before touching relationships or saving. Reopening restores
those operations under their existing Today-or-Yesterday rules. Extend the
existing operations with this lifecycle guard; do not create duplicate progress
APIs.

There is no automatic close path. Progress append, target attainment, target
edit, deadline passage, and standing computation never write lifecycle state.
Likewise, reopening does not manufacture progress or move the deadline.

## Permanent deletion

Delete accepts one persisted Goal from the operation's ModelContext, removes it
and every owned accumulate entry or measure reading through the schema's
cascade relationships, and saves once. The domain operation does not pretend to
implement UI confirmation; goals/goal-experience (F-xowx7x) owns the explicit
owner prompt.

Reject detached, deleted, or foreign-context goals before mutation. Deleting an
open or closed goal follows the same transaction. A failed save restores the
goal, closure state, configuration, progress items, and inverse relationships.

## Persistence and failure boundary

Use main-actor operation services over one caller-supplied `ModelContext`, with
production initializers and internal injectable save seams matching existing
TendCore operations. Validate persistent ownership by SwiftData identity rather
than an ordinary UUID.

Every successful update, close, reopen, or delete performs exactly one save.
Before a save, retain the precise prior values and relationships owned by that
operation. If saving fails, restore only those mutations so unrelated pending
caller work is not rolled back. Propagate typed validation, ownership,
calendar, progress, fetch, and persistence failures without partial state,
speculative repair, or fabricated fallback facts.

Nothing in this feature changes habit buckets, logs, activity periods, streaks,
reminders, or their schema semantics.
