# Goal Records and Progress

## Summary

Add the durable TendCore aggregate and operations for finite quantitative goals.
The feature creates valid Accumulate and Measure goals, records or removes only
recent progress, and derives truthful kind-specific progress from the complete
saved history.

Goals sit beside habits. They have no cadence, buckets, verdicts, streaks,
activity periods, reminders, or requirement snapshots. This feature does not
alter habit behavior and does not force both domains through one model.

This feature owns Goal, Accumulate entry, Measure reading, and date-only
persistence; validated goal creation; recent append/delete operations; and
kind-specific progress computation. Durable closure, deadline pace, field
editing, reopening, and goal deletion belong to goals/goal-lifecycle
(F-5aficd). Forms and history presentation belong to goals/goal-experience
(F-xowx7x).

## Date-only values

Introduce one public `GoalDate` value for owner-selected calendar dates. It
contains a validated Gregorian year, month, and day and has one stable
`YYYY-MM-DD` persisted representation. It contains no time, locale, or time
zone. Lexicographic key order is calendar order.

Resolve a GoalDate to local day boundaries only with an explicit TimeZone. Use
the same fixed POSIX Gregorian calendar discipline as bucket keys, including
calendar day addition across daylight-saving transitions. A malformed,
impossible, or unsupported date is a typed error, never normalized into a
different day.

Goal deadlines and progress-item dates store GoalDate keys. A deadline therefore
remains the same owner-selected date after a time-zone change. Later lifecycle
computation resolves the start of the following local day as its exclusive
deadline boundary.

## Goal aggregate

Persist a Goal with:

- stable ordinary UUID;
- normalized nonempty name;
- immutable kind, `accumulate` or `measure`;
- positive integer target;
- normalized nonempty unit, defaulting to `times`;
- optional integer baseline, required only for Measure;
- optional GoalDate deadline;
- immutable creation timestamp;
- optional inverse collections of Accumulate entries and Measure readings.

Accumulate requires no baseline. Measure requires a baseline different from its
target so the arc has a direction and nonzero span. Direction is derived:
target above baseline means increase; target below baseline means decrease.
There is no persisted direction flag.

Store kind and date values through stable scalar representations. Reject unknown
kind or invalid date values through checked domain access. Do not persist
progress totals, normalized progress, current reading, direction, standing,
closure, success, failure, or display strings.

Goal owns its progress children with cascade deletion. Every child relationship
is optional with an explicit inverse for SwiftData and CloudKit schema
compatibility, but supported operations require exact aggregate ownership.
Stable UUIDs are not uniqueness constraints; persistence identity and validated
relationships establish ownership.

## Kind-specific progress records

Use distinct SwiftData child models rather than a nullable union:

- **GoalEntry** belongs only to an Accumulate goal and stores a stable UUID,
  positive integer amount, GoalDate key, append timestamp, append sequence, and
  optional inverse Goal.
- **GoalReading** belongs only to a Measure goal and stores a stable UUID,
  integer value, GoalDate key, append timestamp, append sequence, and optional
  inverse Goal.

Append timestamp records when Tend saved the fact. GoalDate records which local
day the owner assigned it to. Back-filling Yesterday therefore keeps both
truths. Sequence is a checked, strictly increasing integer within the goal's
kind-specific child collection and breaks equal-timestamp ties by actual append
order. Duplicate, negative, or overflowing sequences are invalid persisted
state.

An Accumulate goal must have no readings. A Measure goal must have no entries.
Operations and computation reject cross-kind or foreign relationships rather
than ignoring them.

## Schema evolution

Add a new versioned schema containing all existing habit models plus Goal,
GoalEntry, and GoalReading. Migrate the current habit-only store without
changing any habit, activity period, bucket, or log entry identity, attribute,
or relationship. The migration adds no sample goals.

The production container remains local-only with CloudKit disabled and never
falls back to memory. In-memory and injected file-backed factories use the same
latest schema and migration plan. New goal attributes have schema-visible
defaults where SwiftData requires them, no unique constraints, and no deny
relationships.

## Validated creation

Expose a `GoalCreationFields` value containing name, kind, target, unit,
kind-appropriate baseline, and optional deadline. `GoalCreationOperations`
runs on the main actor over one caller-supplied ModelContext and receives an
explicit creation instant and TimeZone.

Normalize and validate before inserting:

- trim name and unit and reject either when empty;
- require target greater than zero;
- require nil baseline for Accumulate;
- require an integer baseline different from target for Measure;
- require any deadline's exclusive following-day boundary to be later than the
  creation instant.

Creation writes one Goal with no progress children and saves exactly once.
Kind and created-at are fixed by that successful operation. On save failure,
detach the inserted aggregate and restore inverse relationships without
rolling back unrelated caller work. There is no untrackable goal, maintenance
mode, non-integer target, imported history, automatic seed entry, or implicit
baseline reading.

## Progress destinations and eligibility

Expose only two append destinations: Today and Yesterday. Resolve them from the
explicit operation instant and TimeZone through GoalDate calendar arithmetic.
There is no arbitrary date parameter, making older back-fill and future dates
unrepresentable through the supported append API.

Yesterday is valid only when it is not earlier than the goal's creation
calendar date in the same supplied TimeZone. The creation date itself is valid
even when the progress happened earlier that day because progress is stored at
day grain. A time-zone change may alter which GoalDate contains the absolute
creation instant; every operation uses the caller's current explicit zone.

Deletion accepts a persisted child and re-evaluates its stored GoalDate against
Today and Yesterday at the deletion instant. A child that has aged beyond
Yesterday is immutable. Append timestamp does not extend delete eligibility.

## Append and delete operations

`GoalProgressOperations` runs on the main actor over one caller-supplied
ModelContext, explicit operation instant, and TimeZone.

For an Accumulate goal:

- append accepts a positive integer amount and creates exactly one GoalEntry;
- Measure readings are rejected;
- progress may exceed the target without a cap.

For a Measure goal:

- append accepts any representable integer reading and creates exactly one
  GoalReading;
- Accumulate entries are rejected;
- multiple readings on the same GoalDate are valid.

Before append, validate the persisted Goal by SwiftData identity, checked kind,
complete configuration, destination eligibility, existing child relationships,
and unique nonnegative sequence history. Assign the next checked sequence,
attach exactly one child to the Goal, and save once.

Delete validates the Goal and child by persistence identity, exact inverse
relationship, correct kind, valid stored date and sequence, and current
Today-or-Yesterday eligibility. Remove exactly that child and save once.
Deleting the last child is valid. There is no in-place edit of amount, value,
date, append timestamp, sequence, Goal, or kind; correction is delete then
append.

Validation failures perform no mutation save. On append or delete save failure,
restore only the child and inverse relationship changes owned by the operation.
Repeated successful append requests are distinct facts; the API does not
deduplicate them.

goals/goal-lifecycle (F-5aficd) later adds the open-goal guard. Until that
dependent feature lands, the progress operation surface contains no duplicated
closure placeholder.

## Accumulate progress

Compute Accumulate progress from every validated GoalEntry related to the Goal,
regardless of date. Sum positive amounts with checked integer arithmetic and
fail on overflow or malformed relationships.

Return an immutable, Equatable, Sendable Accumulate snapshot containing kind,
checked total, target, unit, and normalized progress. Normalized progress is
`total / target` and is not capped at one, so `7 of 6` remains truthful.

The computation performs no save, cached-total write, verdict, standing, or
automatic closure.

## Measure progress

Compute Measure progress from baseline and the effective GoalReading:

- the latest GoalDate wins across days;
- within that date, the highest valid append sequence wins;
- every other reading remains history;
- with no readings, baseline is the current value and progress is zero.

Return an immutable, Equatable, Sendable Measure snapshot containing kind,
baseline, target, current value, optional effective-reading identity, checked
completed distance, checked total distance, unit, and normalized progress.

For an increasing goal, completed distance is current minus baseline. For a
decreasing goal, it is baseline minus current. Clamp movement in the wrong
direction to zero and movement at or beyond target to total distance. Keep the
unclamped current value visible in the snapshot. Normalized progress is clamped
from zero through one.

Use checked integer arithmetic for sums, sequence advancement, total span, and
completed distance. Extreme representable values whose difference or sum
cannot be represented fail with a typed overflow instead of trapping,
wrapping, or switching silently to approximate stored facts.

## Failure boundary and scope

Creation, mutation, and persistence-aware computation reject unknown kind,
invalid date, invalid scalar, detached/deleted model, foreign context, missing
or contradictory inverse, cross-kind child, duplicate sequence, and arithmetic
overflow with typed errors. No operation repairs corrupt persisted state,
returns fabricated zero progress, or silently drops a child.

This feature adds no UI, notification, haptic, network request, analytics,
trend chart, milestone, habit bridge, bucket, verdict, streak, closure, pace,
or Today behavior.
