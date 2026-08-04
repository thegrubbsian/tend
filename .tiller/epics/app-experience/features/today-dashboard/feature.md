# Today Dashboard

## Summary

Replace the nonempty Today placeholder with the owner’s current commitments:
every active daily and weekly habit, truthful current-bucket progress, current
streak, and any still-actionable streak risk. The screen follows the Almanac
Today board: unresolved work first, completed work below, and quiet confirmation
when everything is tended.

This feature owns the read projection, presentation model, static card states,
refresh behavior, and adaptive Today surface. It preserves the zero-habit
first-launch experience already owned by app-experience/habit-management and
leaves logging, undo, back-fill, the quantity log sheet, and logging haptics to
app-experience/fast-logging.

## Current-bucket projection

Add a main-actor `HabitTodayComputation` API to TendCore with one public
`snapshot(for:at:timeZone:)` operation. It accepts a persisted active `Habit`
plus an explicit instant and time zone, and returns one immutable
`HabitTodaySnapshot` containing:

- the current bucket’s stable period key;
- aggregate progress, target, and stored unit;
- cadence;
- current streak;
- whether that streak is at risk because an unmet grace bucket is still open;
- whether the current bucket is provisionally met.

Build the snapshot from the existing `BucketReconciler`, `BucketEvaluator`, and
`HabitStreakComputation` boundaries. Do not reproduce bucket phases, weekly
boundaries, grace rules, progress arithmetic, or streak semantics in the app
target.

For an active habit, reconcile at the supplied instant before reading the
current bucket. The selected bucket must be the cadence period containing that
instant: one local calendar day for daily habits and the containing
Monday-through-Sunday period for weekly habits. Weekly pinning never filters the
projection; pinned days aim reminders only.

Return one coherent snapshot or a typed failure. Reject detached, deleted,
foreign-context, inactive, invalid-cadence, invalid-requirement, missing-current,
duplicate-current, malformed-relationship, evaluation, reconciliation, and save
failures without inventing a zero, using a different bucket, or returning
partially updated facts. Persisted best-streak improvements and reconciliation
effects retain their existing transaction and rollback behavior.

The computation must remain correct at local midnight, Monday rollover,
spring-forward and fall-back transitions, and a time-zone change. All operations
in one snapshot use the same supplied instant and time zone.

## Today presentation model

Add a main-actor observable `TodayModel` with an injected operations boundary
and a live adapter to `HabitTodayComputation`. The existing production
`ModelContext` remains the only store. The model receives the production query’s
persisted habits and one captured refresh context—instant, time zone, calendar,
and locale—and projects each active habit exactly once. Inactive habits never
appear on Today.

Each `TodayHabitRow` carries the live habit and its SwiftData
`PersistentIdentifier`, never its array index, owner-visible name, or ordinary
UUID as presentation identity. A successful row contains:

- the exact owner-written name;
- localized progress such as `5,200 of 8,000 steps` or `1 of 1 time`;
- localized current streak with `day` or `week` singular/plural;
- a cadence-aware risk line when applicable:
  `Yesterday open · N day streak at risk` for daily habits or
  `Last week open · N week streak at risk` for weekly habits;
- a clamped visual progress fraction while preserving the truthful unbounded
  aggregate in text;
- complete accessibility label and value text.

Only the built-in `times` unit receives singular `time` at a target of one.
Every other stored unit remains verbatim. Locale-aware integer formatting must
not introduce grouping into stable accessibility identifiers or persisted keys.

Project rows into two deterministic groups:

1. **TO TEND:** unmet rows and rows whose current facts are unavailable.
2. **TENDED:** provisionally met rows.

Sort alphabetically within each group using localized, case-insensitive
comparison, with creation time and stable identifier as tie-breakers. The header
fraction is `met count of active count`; failed rows remain in the denominator
and never count as met.

A failed row stays visible with its name, requirement, `Progress unavailable`,
`Streak unavailable`, a concise inline error, and one retry action. One corrupt
habit must not suppress valid siblings. A successful retry replaces that row’s
facts atomically. Do not show a spinner, erase the prior complete dashboard, or
silently drop a failed habit.

## Dashboard states

Today remains the landing destination on every cold launch.

When there are no persisted habits, preserve the existing first-launch body and
single `Plant a habit` action exactly. The action continues to open the shared
New habit form. This is based on total persisted habit count, not active count or
one-time onboarding state.

When persisted habits exist but none are active, show the plain body line
`No active habits.` Do not render a vacuous `0 of 0`, an `All tended.` success
claim, inactive cards, or another habit-management control; the existing Habits
destination owns reactivation.

When active habits exist:

- show the localized uppercase date eyebrow and New York `Today` title;
- show the trailing New York fraction `N of M`;
- render **TO TEND** before **TENDED** whenever unresolved rows exist;
- when every active row is successfully met, replace the empty **TO TEND**
  section with the quiet serif line `All tended.` and keep the **TENDED** rows
  below;
- never use confetti, alarm language, motivational scoring, or gamified copy.

An unavailable row prevents `All tended.` even when every computed row is met.

## Almanac Today surface

Install the dashboard body inside the existing `TodayDestinationChrome`. Keep
the custom two-destination shell, floating tab pill, first-launch sheet
ownership, date header, shared model context, and forced-light Almanac
appearance. Do not add a router, a navigation stack, a third destination, or a
second Today screen.

Match the approved `Today` board in `.tiller/design/comps/tend.pen`:

- paper background with 20-point horizontal screen padding and the existing
  centered readable width;
- raised unmet cards with 14-point corners, one-point hairline stroke,
  16-point padding, and no shadow;
- owner name at leading and truthful streak at trailing;
- optional ochre-deep risk line;
- eight-point fully rounded sunken progress track with moss fill;
- exact progress text on the meta line;
- a 52-point ambient log ring aligned to the name row, with a hairline empty
  state, clockwise moss progress arc, and solid moss check at completion;
- compact met rows with owner name and smaller streak at leading plus a
  44-point filled moss check at trailing;
- uppercase tracked **TO TEND** and **TENDED** section labels.

Progress exceeding the target keeps the textual aggregate and renders a complete
ring rather than overflowing its track. Zero progress renders an empty ring.
Unavailable progress renders a neutral sunken ring and no fabricated arc.

The ring in this feature is an ambient progress visualization, not an
interactive control. It has no tap gesture, button trait, haptic, hidden write,
or accessibility action, and is hidden from VoiceOver as a duplicate of the
card’s complete facts. app-experience/fast-logging will turn that established
visual seam into the unit-specific logging affordance.

Cards themselves do not open Habit Detail; roster-owned navigation remains in
app-experience/habit-detail-history.

## Refresh and consistency

Drive owner-local boundary refresh with the existing
`LocalDayTimelineSchedule` in exactly one `TimelineView` at the Today
destination. Rebuild that schedule when calendar or time zone changes and let
the view lifecycle end it when Today disappears; do not add a manual timer or a
second competing schedule.

Capture one instant, time zone, calendar, and locale per refresh and use that
sample for every row, the date eyebrow, grouping, fraction, and accessibility
text. Refresh:

- on first presentation;
- whenever the production habit query changes after create, edit, archive,
  reactivate, or delete;
- at the next owner-local calendar day boundary;
- when the app becomes active;
- when calendar, locale, or time zone changes;
- after a successful row retry.

Construct a complete replacement presentation before publishing it. A refresh
must not momentarily pair one row’s new progress with its old streak, move a row
between sections before its facts agree, or expose an incorrect fraction. Query
changes and local-boundary refreshes remain synchronous main-actor work with no
spinner.

## Accessibility, adaptation, and appearance

Each card is one combined accessibility element that announces the owner-written
name, exact progress and requirement, cadence-unit streak, met or unmet state,
and full risk stakes when present. Failed cards announce unavailable facts,
their error, and the retry action. Section labels remain navigable headings.
Decorative tracks, arcs, and checks do not duplicate those facts.

Every actual control—the first-launch action, row retry, and shell controls—is
at least 44 by 44 points. Do not expose the ambient ring as a button until
app-experience/fast-logging supplies a real action.

Owner-written names and progress units wrap without ellipsis through two larger
Dynamic Type steps. At accessibility sizes, the name/streak row and progress
metadata may stack rather than compressing or clipping. Scroll content remains
reachable above the floating tab pill.

On iPad, retain the full paper field and center the dashboard at the shell’s
readable maximum width. Do not introduce a sidebar, stretch cards edge to edge,
or move the tab pill. Continue forcing light appearance. Static progress has no
semantic animation; regrouping and refresh changes honor Reduce Motion and
convey no state by motion alone.

## Verification

TendCore tests prove daily and weekly current-period selection, all-week weekly
presence, progress and over-target aggregation, provisional met state,
grace-derived risk, active-only enforcement, reconciliation, transaction
failures, malformed graphs, midnight, Monday, DST, and time-zone boundaries.

App-unit tests prove active-only projection, stable identity, one sampled refresh
context, localized formatting, deterministic grouping and ordering, met
fractions, all-tended and inactive-only states, per-row failure isolation,
atomic replacement, retry, query-driven refresh, and single local-boundary
scheduling.

UI tests use DEBUG-only named file stores seeded through public TendCore
operations. They launch into mixed daily/weekly Today data, prove exact
owner-visible card facts and ordering, weekly presence independent of pins,
at-risk treatment, met compaction, the all-tended state, the inactive-only
state, first-launch preservation, relaunch persistence, shell selection, and
the absence of logging writes or fake ring actions.

Manual acceptance compares mixed, all-tended, inactive-only, and failure states
on compact iPhone and centered iPad against the approved Today board. A second
pass covers two larger Dynamic Type steps, full VoiceOver reading, headings and
retry, 44-point controls, forced light appearance, safe-area and tab-pill
clearance, contrast, and Reduce Motion.

## Ownership and non-goals

This feature may add TendCore Today computation and tests, an app-target Today
model and views, app-unit and UI tests, and DEBUG-only deterministic fixture
support. Fixture seeding must require an explicitly named reset store, use one
captured launch instant and explicit time zone, build every valid graph through
public operations, and remain unreachable from release behavior or ordinary
launches. The explicitly named failure fixture may corrupt one already-seeded
raw cadence value to prove imported-data failure handling; no other direct
model mutation is allowed.

Do not change the persistence schema, bucket lifecycle, streak arithmetic,
logging operations, Almanac tokens, root shell model, shell persistence, Habit
Detail, All Habits, or the shared New/Edit form. Do not add log mutation,
quick-add chips, custom amount entry, set-total behavior, entry deletion, undo,
grace back-fill dispatch, a quantity sheet, reminder scheduling, notification
permission, haptics, dark appearance, network access, analytics, a third-party
dependency, app-store packaging, or release-device evidence.
