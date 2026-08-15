# Today Goal Surfacing

## Summary

Extend the established Today dashboard with one conditional GOALS section below
all habit sections. An open goal appears only when it needs the owner's
attention: it is behind pace, past due, or its deadline is no more than seven
owner-calendar days away. It disappears as soon as none of those conditions
holds or the owner closes it.

This feature consumes the durable goal records and standing from
goals/goal-lifecycle (F-5aficd), the Today presentation and refresh architecture
from app-experience/today-dashboard (F-skoqxt), and the kind-specific progress
component and shell destination from goals/goal-experience (F-xowx7x). It does
not reproduce goal arithmetic, create a second Today model, or make Today a
complete Goals roster.

Today surfacing is the whole goal nudge apparatus in v1. This feature schedules
no goal reminders or notifications.

## Eligibility

Evaluate every persisted Goal against one captured Today refresh context:
instant, owner calendar, TimeZone, and Locale. Use the existing goal progress
and standing computations; SwiftUI and the app model do not derive pace.

A valid Goal is eligible when it is open and at least one condition is true:

- standing is behind;
- standing is past due;
- its GoalDate deadline is Today, or one of the next seven local calendar
  dates, including the date exactly seven days away.

The upcoming window uses GoalDate calendar addition, not a fixed 168-hour
interval. Daylight-saving and time-zone changes therefore change the resolved
window without rewriting the stored deadline. A deadline remains active
through its full local date; at the following local-day boundary an unclosed
goal becomes past due and remains eligible until closed or rescheduled.

An on-pace open goal whose deadline is eight or more local dates away is absent.
An open goal without a deadline is on pace and absent. Equality between actual
and expected progress counts as on pace, but an on-pace goal still appears
inside the seven-day window. An over-target goal does not auto-close: it remains
eligible when near or past its deadline until the owner closes or edits it.

Harvested and let-go goals are always absent. Reopening immediately subjects the
goal to the same eligibility calculation. A successful progress, configuration,
closure, reopening, or deletion mutation refreshes the query-backed projection;
the app never keeps a stale eligibility flag.

## Today goal projection

Extend the existing main-actor `TodayModel` rather than adding a sibling model.
It receives persisted goals beside persisted habits and projects goal rows
through a small injected operation signature. The live adapter composes the
existing goal progress and standing APIs over the production ModelContext. Tests
inject deterministic facts without another store.

Each `TodayGoalRow` retains the live Goal and its SwiftData
`PersistentIdentifier`. It never uses array position, owner name, or ordinary
UUID as presentation identity. A successful row carries:

- exact owner-written name;
- kind-specific progress snapshot;
- exact localized progress text;
- normalized visual progress and optional expected pace position;
- deadline text;
- explicit on-pace, behind, or past-due text and visual treatment;
- one combined accessibility description;
- the next time-only standing transition reported by TendCore, when present.

Evaluate every open goal exactly once before filtering. This is required because
an on-pace goal currently absent from Today may become behind at its next
domain-reported transition. Build a complete replacement set before publishing
it; a refresh never mixes old eligibility with new progress or standing.

Closed goals are filtered after checked lifecycle access and need no progress or
standing computation. Unknown closure, malformed configuration, failed progress
or standing computation, and inconsistent persistence cannot be treated as
closed or safely omitted. Keep such a Goal visible in GOALS as an unavailable
row with its exact recoverable name, concise error, and one retry action. One
bad Goal never suppresses valid siblings or corrupts the habit presentation.

Retry addresses the exact persistent identity with a fresh refresh context. If
the Goal disappeared, closed, or changed eligibility, perform a complete
refresh rather than retargeting a row by index or name. A repeated failure keeps
the unavailable row and error visible.

## Ordering

Partition eligible Goal rows by urgency and render one flat deterministic list:

1. unavailable rows, because Today cannot prove they are safe to omit;
2. past-due rows;
3. behind rows;
4. on-pace rows inside the seven-day window.

Within each urgency, earlier deadlines come first. Localized,
case-insensitive name order follows, with creation timestamp and persistent
identifier as tie-breakers. A retry or refresh may move a row only after its
complete replacement facts are ready.

Do not merge Goals into TO TEND or TENDED. Goal target attainment is not a habit
bucket verdict, and closing remains an explicit owner decision. Goal rows do not
enter the habit `N of M` header fraction.

## GOALS section

Render GOALS below both habit sections and above the floating tab pill. Omit the
heading and all goal layout when no goal is eligible or unavailable.

Use the approved `Today v2` board in
`/Users/jcgrubbs/dev/tend-design/comps/tend.pen`:

- uppercase tracked **GOALS** heading aligned with **TO TEND** and **TENDED**;
- one raised, hairline-bordered Almanac card per Goal, without shadow;
- owner name and exact kind-specific progress text in the leading row;
- the shared `GoalProgressView` track or directed Measure span, including the
  expected pace tick when applicable;
- a compact metadata line such as `Due Dec 31 · behind pace`;
- moss for on-pace deadline proximity, accessible ochre for behind, and
  withered treatment for past due;
- neutral sunken progress and explicit unavailable copy for a failed row.

Accumulate over-achievement keeps truthful text such as `7 of 6 books` while the
track remains visually full. Measure keeps the truthful current reading and
traveled distance while its marker remains clamped to the baseline-target span.
Color is never the only standing signal. Reuse the progress component and
formatting grammar established by the Goals roster; the same Goal at the same
instant must not display different facts on Goals and Today.

Goal cards are informational nudges. They do not append progress, open Goal
Detail, present a sheet, close the Goal, trigger a haptic, or expose a fake
control affordance. The functional Goals tab remains the route to owner action.
The unavailable-row retry is the only control in GOALS and is at least 44 by 44
points.

## Dashboard state integration

Keep Today as the cold-launch destination and preserve all existing habit
states, grouping, order, progress, streak, logging affordances, and header
fraction.

The Goal section composes beneath whatever habit body is valid:

- no persisted habits keeps the existing first-launch explanation and Plant a
  habit action, then adds GOALS only when a Goal is eligible;
- persisted but inactive habits keep `No active habits.`, followed by any
  eligible Goals;
- active habits keep TO TEND and TENDED exactly, followed by GOALS.

`All tended.` is a page-level claim and appears only when every active habit is
successfully met and GOALS has no eligible or unavailable row. Eligible Goals
therefore suppress that line without changing the habit fraction or moving a
Goal into a habit group. When the final Goal leaves Today, the existing
all-tended presentation returns if its habit conditions still hold.

Do not add a goal count to the Today title. Do not show a GOALS empty state,
closed count, New goal action, history, arbitrary roster rows, or Journal card.
Those belong to their owning destinations.

## Refresh and consistency

Use the Today destination's existing single refresh architecture. Capture one
instant, calendar, TimeZone, and Locale for habits, Goals, the header, ordering,
eligibility, formatting, and accessibility.

Refresh:

- on initial presentation;
- whenever the habit or Goal query changes;
- when the scene becomes active;
- when calendar, TimeZone, or Locale changes;
- at the next owner-local day boundary;
- at the earliest next time-only standing transition across every open Goal;
- after a row retry.

Extend the one Today `TimelineView` schedule to wake at the earlier of its local
day boundary and the next Goal transition. Do not add a second TimelineView,
manual timer, notification, background task, or retained scheduler after Today
disappears. Rebuild the schedule when a refresh changes the earliest transition.

A goal progressing back on pace leaves immediately unless its deadline is still
inside the seven-day window. A closure leaves immediately. A distant on-pace
goal enters when the owner-local date reaches its seven-day window. An on-pace
goal becoming behind from elapsed time enters at the domain-reported transition,
without requiring relaunch or a progress write.

Refresh remains synchronous main-actor projection with no spinner. Publish the
habit and Goal presentation atomically so `All tended.`, section visibility,
and row facts always describe the same sampled generation.

## Accessibility and adaptation

GOALS is a navigable heading. Each successful card is one combined
accessibility element announcing name, kind-specific progress, deadline, and
standing. Decorative tracks, spans, pace ticks, and markers are hidden from
VoiceOver as duplicate facts. An unavailable row announces the recoverable
name, unavailable facts, error, and retry.

Owner-written names and units, localized large integers, and metadata wrap
without ellipsis through two larger Dynamic Type steps. Stack the name/progress
and metadata layouts before text clips. Preserve compact-phone scrolling, iPad
readable width, forced-light appearance, contrast, Reduce Motion, safe-area
clearance, and floating-pill clearance supplied by Today.

## Scope

This feature changes no goal persistence, arithmetic, standing, lifecycle,
creation, editing, progress mutation, or Goals roster behavior. It changes no
habit domain behavior, notification scheduling, logging operation, reminder
routing, Journal behavior, Pencil comp, network request, analytics, milestone,
trend chart, or habit-goal link.
