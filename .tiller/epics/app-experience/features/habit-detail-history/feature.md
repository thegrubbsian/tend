# Habit Detail and History

## Summary

Tell one habit's complete, truthful story. Selecting any row in All Habits opens
an Almanac detail destination with requirement metadata, current and best
streaks, a bucket-grain history garden, editable recent log entries, and direct
Edit plus Archive or Reactivate actions.

This feature owns the detail read model and destination, history navigation and
state presentation, detail-originated entry deletion, and roster-to-detail
navigation. It reuses the approved habit-management forms and operations and
the existing bucket, lifecycle, logging, and streak rules. It does not own Today
cards, logging or back-fill entry creation, reminder scheduling, habit
deletion, schema changes, or release-device evidence.

## Truth boundary

Add a main-actor `HabitDetailComputation` API to TendCore. Views must not derive
bucket finality, streaks, inactive gaps, entry editability, or calendar
boundaries from ad hoc SwiftUI state.

Given a persisted habit, an injected instant and time zone, and a selected
calendar month, the computation must:

- reconcile an active habit before reading it;
- derive current and best streaks through `HabitStreakComputation`;
- validate cadence, requirement, period keys, relationship ownership, and
  duplicate buckets rather than hiding malformed persisted state;
- return immutable, equatable projection values containing stable identifiers,
  dates, numeric facts, and semantic states rather than formatted UI strings or
  live SwiftData models;
- perform calendar arithmetic with `CalendarBucketSchedule` in the injected
  local time zone; and
- fail atomically with a typed error. It never substitutes zero streaks,
  invented buckets, or a partially credible history.

The projection distinguishes these states:

- **met** and **missed** for final buckets, using the frozen target and unit;
- **open** and **grace** for provisional buckets, retaining whether the
  requirement is met so far plus current progress, target, and unit;
- **inactive** for an exempt bucket or a period wholly outside every activity
  interval after creation;
- **before creation** for a period ending before the bucket that contains the
  habit's creation instant begins; and
- **future** for a period that has not opened at the injected instant.

A persisted bucket takes precedence over a synthesized gap. A missing elapsed
bucket that intersects an activity period is invalid data, not an inactive gap.
An activity interval intersects a bucket when the interval and bucket overlap;
the existing exempt flag remains authoritative for a bucket deactivated before
finality.

Expose the earliest and latest selectable month with each projection. The
latest is the month containing the injected instant. The earliest is the
earlier of:

1. the month containing the first bucket that could include the creation
   instant; or
2. two months before the latest month.

This guarantees the current month plus two preceding months for a new habit and
allows an older habit to navigate its full recorded lifetime without offering
pages that can contain only pre-creation history.

Include every log entry whose bucket is currently open or in grace and therefore
passes the existing deletion rules. Return entries newest first, with timestamp,
amount, bucket key, and stable entry identifier; use the identifier as a
deterministic tie-breaker. Final, exempt, malformed, and foreign entries are not
presented as editable. Deletion still goes through `LogEntryOperations.delete`,
then recomputes the entire detail projection.

## Header and habit facts

Present detail full screen over the Habits destination so the floating tab pill
does not compete with the story. A leading clay-deep `Habits` back action
returns to the roster; a trailing clay-deep `Edit` action opens the shared
`HabitFormView` in Edit mode. The habit name uses the same New York title size
as the other app screens and never truncates.

Under the title, show one localized metadata line or wrapped group containing:

- target and unit, with only the built-in `times` label singularized at one;
- Daily or Weekly cadence;
- weekly pinned-day names when any are set; and
- reminder time when set.

Extract or share the approved habit-presentation formatting from the roster;
do not add a second spelling, pluralization, pinned-day order, or reminder-time
convention.

Show CURRENT and BEST as a balanced pair of meaningful numerals, each followed
by `day`/`days` or `week`/`weeks`. The values come from the same detail
projection. When `isAtRisk` is true, insert a quiet ochre raised callout that
states the current chain is at risk; do not soften, celebrate, or animate the
fact. Inactive habits show the frozen current chain and retain readable history.

If projection fails, keep the known habit name and navigation available, replace
all derived facts with one honest inline failure card, and expose `Try again`.
Never show stale history as current or label unavailable values as zero.

## History garden

The first successful page is the month containing the injected instant. A
centered, tracked uppercase month label sits between faint previous and next
chevrons. Disable previous at the earliest month and next at the latest month.
Changing month is deterministic and does not mutate persisted state.

### Daily habits

Render a Monday-first seven-column garden:

- one weekday-letter row;
- one 44-point, radius-7 cell for every date in the selected month;
- leading and trailing geometry needed to complete calendar weeks, rendered as
  noninteractive out-of-month ghosts; and
- edge-to-edge distribution across the readable content width without date
  numerals.

### Weekly habits

Render one 44-point-high, radius-7 full-width strip for every
Monday-through-Sunday bucket that intersects the selected month. Boundary weeks
may therefore appear on adjacent month pages; this is preferable to hiding the
current bucket during a month boundary. Strips remain visually unnumbered and
use the same state grammar as daily cells.

### State grammar

- met: moss fill;
- missed: withered fill;
- open current bucket: raised paper with a 1.5-point clay stroke;
- grace bucket: raised paper with a 1.5-point ochre stroke;
- inactive, pre-creation, and future: sunken ghost at 45 percent opacity; and
- out-of-month daily geometry: the same ghost appearance, without interaction.

Keep the three-item `Met`, `Missed`, `Open` legend from the comp. Dormant,
pre-creation, future, open-versus-grace, and met-so-far distinctions remain
available through cell interaction and accessibility rather than expanding the
legend into a dashboard.

Every real cell or strip is a button with a minimum 44-by-44 hit region. A tap
reveals a lightweight transient callout with the exact localized day or
week range and state. For open and grace buckets, include progress and
requirement. The callout is informational only and dismisses without navigating
or opening the log-entry surface.

VoiceOver labels each button with its exact date or week range, state, and
provisional progress where present. Reading order is month control, weekday
headers where applicable, chronological buckets, then legend. Color is never
the only programmatic state signal.

## Recent entries and owner actions

Below the history garden, render `RECENT ENTRIES`. When editable open or grace
entries exist, each row shows:

- localized bucket scope or date;
- localized entry time;
- locale-aware amount and the bucket's effective unit; and
- a trailing minus-circle `Delete entry` button with the full entry fact in its
  accessibility label.

Rows are chronological newest first and remain readable for owner-written units.
Deletion is immediate and non-destructive only to that contribution; it does not
confirm, undo, or change a final bucket. A successful deletion refreshes
progress, streaks, risk, history state, and the entry list together. A failed
delete keeps the row and owner context, reports the operation error inline, and
offers retry without dispatching twice.

When no editable entries exist, show one subdued sentence instead of a
decorative empty list. Entry creation, quick-add, set-total, and back-fill remain
owned by app-experience/fast-logging.

End the scroll content with one low-emphasis lifecycle action:

- active habit: `Archive habit`;
- inactive habit: `Reactivate habit`.

Call `HabitActivityOperations` at the current injected instant and local time
zone. Archive leaves the owner on detail with the frozen streak and history;
Reactivate immediately makes the current bucket due. Refresh the entire
projection only after a successful save. Keep permanent Delete in All Habits,
where its established consequence confirmation lives.

## Navigation and refresh

Tapping any active or inactive All Habits row opens its detail destination while
preserving the existing swipe, context-menu, and VoiceOver custom actions.
Presentation covers the shell tab pill and has exactly one back path to the
roster. Dismissing Edit returns to the same detail and reflects a successful
save immediately; cancel changes nothing.

Recompute on first presentation, after Edit/Delete entry/Archive/Reactivate,
when the scene becomes active, and when the next local calendar day begins.
Cancel any obsolete boundary task when the destination disappears. A time-zone
change on reactivation uses the new local calendar, matching the domain model.
Do not add a parallel app store, sample data, a detail cache that survives the
model context, or a second shell destination.

The Today dashboard may later present this same destination, but this feature
does not add a placeholder Today card, router abstraction, or hidden navigation
contract for work that does not yet exist.

## Almanac, adaptation, and accessibility

Match the `Habit Detail` board in `.tiller/design/comps/tend.pen`: paper
background, 20-point horizontal wrapper, compact custom navigation row,
uniform New York title, balanced streak stats, garden geometry, hairlines,
ochre risk state, and calm recent-entry rows. Reuse Almanac tokens and raised or
sunken modifiers; add a token only for a repeated semantic measurement.

The body scrolls independently beneath a fixed safe status area. On iPad it
remains centered at the existing readable maximum width rather than becoming a
sidebar. At two larger Dynamic Type steps, metadata and stats may stack, names
and units wrap, cells retain their hit regions, and no action is clipped by a
sheet or safe area.

Force the existing light appearance, honor Reduce Motion, avoid alarm red,
shadows, native `Form` chrome, celebration, haptic changes, and color-only
accessibility. VoiceOver must expose full labels, values, selected month
control state, unavailable/retry state, entry deletion, Edit, Archive or
Reactivate, and Back without requiring swipe gestures.

## Definition of done

The feature is complete when both cadences render truthful navigable history
from persisted state, detail mutations round-trip through existing domain
operations, roster navigation and relaunch preserve the story, automated
contracts pass, and compact iPhone plus centered iPad evidence covers visual,
Dynamic Type, VoiceOver, forced-light, and Reduce Motion behavior.

Evidence for manual criteria records observations and screenshots for the human
gate; it never attests or approves that gate.
