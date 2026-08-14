# Goals Experience

## Summary

Give finite goals a complete Almanac home. The owner can open Goals from the
root shell, scan every goal by standing, create or revise an accumulate or
measure goal, inspect its full progress history, record or remove recent
progress, and deliberately harvest, let go, reopen, or delete the goal.

This feature presents and orchestrates the rules supplied by
goals/goal-lifecycle (F-5aficd). It does not duplicate progress, pace, standing,
closure, or persistence math in the app target. It does not put goals on Today;
that belongs to goals/today-goal-surfacing (F-e8yd2r). Goal notifications,
habit linking, maintenance goals, non-integer quantities, milestones, and trend
charts remain out of scope.

## Shell integration

Add Goals as a functional top-level destination between Today and Habits in the
existing Almanac floating pill. A cold launch still selects Today, scene
backgrounding preserves the current selection, and a process relaunch returns
to Today. Selecting Goals replaces the current destination rather than keeping
a hidden duplicate hierarchy alive. The selected tab uses a flag symbol and the
same label, selected trait, minimum hit area, focus transfer, and stable
accessibility identifier conventions as Today and Habits.

The Goals and Today v2 reference boards show the eventual Journal destination.
This feature must not ship a disabled or empty Journal tab. Journal remains
owned by journal (E-l8goi4); this feature makes the current pill accommodate
Goals without preventing that later fourth destination.

Today and Habits retain their current content, navigation, persistence,
reminders, and accessibility behavior. This feature changes only the shared
destination enumeration, pill presentation, and Goals destination wiring.

## Goals roster

The Goals destination reads every persisted goal from the production
`ModelContext` and builds owner-visible rows from the lifecycle and standing
computations. It never uses sample data, a second store, or view-owned business
math. Refresh after a goal mutation, when the scene becomes active, at a local
calendar boundary, and at any earlier standing transition identified by the
domain computation.

Partition each goal into exactly one roster group:

- **OPEN:** open goals that are not past due. Behind goals appear before on-pace
  goals. Within each standing, earlier deadlines appear first, goals without a
  deadline follow deadlined goals, and localized name, creation time, and
  identifier provide deterministic tie-breakers.
- **PAST DUE:** open goals whose deadline has passed, ordered by deadline and
  then the same deterministic tie-breakers.
- **CLOSED:** harvested and let-go goals together in a disclosure group at the
  bottom. It starts collapsed, shows the combined count, and expands without
  changing the stored goals.

Omit empty groups. With no goals, keep the add control visible and show one
short explanation plus one obvious New goal action. Selecting any open or
closed row opens that goal's detail destination.

Each open row shows the goal name, truthful progress in the goal's own terms,
deadline text or `No deadline`, and standing through the existing Almanac color
grammar:

- moss for on pace or open without a deadline;
- accessible ochre for behind;
- withered for past due.

Closed rows use quiet ink, name their `Harvested` or `Let go` state, and retain
the final owner-visible progress. Color is never the only standing or closure
signal.

The header follows the Goals reference board: New York `Goals` at leading and a
filled moss add control at trailing. The roster uses the board's warm paper,
raised rows, hairlines, typography, spacing, progress grammar, section labels,
and absence of shadows.

## Progress visuals

An accumulate goal uses the standard progress track plus a localized fraction,
for example `2 of 6 books`. A deadlined goal places a pace tick at today's
expected position. Over-achievement keeps the track visually full while the
fraction reports the real total, such as `7 of 6 books`.

A measure goal uses a directed span from baseline to target. It marks the
latest reading on that span, labels both endpoints, and reports the latest
reading plus traveled progress, for example `183 · 12 of 30 lbs`. Increasing
and decreasing spans use the same component. A reading beyond the target clamps
the marker at the completed end while the latest value remains visible. A
deadlined measure goal uses the same pace tick as accumulate goals.

The app receives normalized progress, expected progress, and standing from
TendCore. SwiftUI only formats and draws those facts. Roster and detail visuals
must agree for the same goal and instant.

## New and Edit goal form

Use one scrollable Almanac sheet for New and Edit. New starts from explicit
draft state:

- Name empty.
- Kind `Accumulate`.
- Target `1`.
- Unit `times`.
- Baseline absent and hidden until kind is `Measure`.
- Deadline absent.

New mode lets the owner choose Accumulate or Measure. Measure requires an
integer baseline. Edit copies the persisted values once and displays kind as
locked with an in-place explanation; it never offers conversion between goal
kinds. Baseline remains editable for a measure goal. Name, positive-integer
target, nonempty unit, and optional calendar deadline remain editable for both
kinds.

Draft edits never mutate the persisted goal. Save trims owner text, validates
the whole draft, calls the supported TendCore create or update operation once,
and dismisses only after the save succeeds. Cancel discards the draft. A failed
save keeps every entered value and exposes a retryable error. Editing a target,
baseline, or deadline immediately changes the arc's computed progress and
standing after a successful save; the app does not preserve an obsolete
snapshot.

The form follows the existing habit-form grammar: clay Cancel, centered New
goal or Edit goal title, moss Save, tracked uppercase labels, sunken fields,
clear inline validation, keyboard-aware scrolling, and layout that stacks
rather than truncates at larger Dynamic Type sizes. The baseline field appears
only for a new Measure draft and for an existing measure goal. The locked kind
explanation remains adjacent to the value it explains.

## Goal detail and progress entry

Present Goal Detail as a full-screen destination so the floating shell pill
does not compete with goal actions. Preserve the selected goal across Edit and
progress sheets, and return to the same roster position on Back.

Detail shows:

- name, standing, and the large kind-specific progress visual;
- target, unit, kind, and baseline for a measure goal;
- deadline and localized days remaining when one exists, or the past-due
  wording after it passes;
- every entry or reading in reverse chronological order;
- Edit and permanent Delete;
- Harvest and Let go while open, or Reopen while closed.

An open accumulate goal offers Add progress. The sheet accepts a positive
integer amount and a date scope of Today or Yesterday, then appends one entry.
An open measure goal offers Add reading. Its sheet accepts an integer reading
and the same two date scopes, then appends one reading. There is no in-place
edit: correction means deleting an eligible item and appending another. The
sheet uses calendar-local dates and never permits a future date or a date older
than yesterday.

Show all persisted items, including multiple readings on one day. Make clear
which reading is currently effective without hiding the others. Only items
dated today or yesterday expose Delete; older items remain readable and have no
disabled or misleading edit affordance. After any add or delete, reload the
detail and roster from the saved domain result so progress, pace, and standing
stay consistent.

Harvest and Let go are always deliberate owner actions. Reaching or passing the
target never closes a goal, and being past due never marks it failed. Closing
records exactly the chosen state and disables progress mutation until Reopen
succeeds. A reopened goal returns to the computed open standing for the current
instant. Edit remains available for closed goals because goal configuration is
editable at any time.

Permanent deletion requires a confirmation that names the goal and states that
its full progress history will be removed. Dismiss only after the domain delete
succeeds. No close, reopen, edit, entry, reading, or deletion failure may
optimistically change owner-visible state or strand the detail hierarchy.

## Accessibility, layout, and failure behavior

All controls expose owner-visible labels, values, hints, selected or expanded
state, and stable identifiers for the complete UI journey. Progress visuals
combine into meaningful VoiceOver summaries rather than announcing decorative
track pieces. Standing and closure remain legible without color. Interactive
targets are at least 44 points.

Support compact iPhone width, landscape, and at least two larger Dynamic Type
steps. Preserve fixed geometry only for the progress tracks, markers, and
floating pill; text and row content may grow vertically. Use deep ochre for
small behind text, honor Reduce Motion, and retain the app's forced light
appearance.

Initial fetch failures replace neither goals nor progress with zeros or sample
facts. Keep the destination available with an honest retry. Mutation failures
preserve the last saved presentation and the owner's draft or confirmation
context so retry and cancel remain possible.
