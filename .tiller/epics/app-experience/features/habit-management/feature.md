# Habit Management

## Summary

Let the owner create and maintain the commitments Tend evaluates. The feature
replaces the empty Habits destination with the Almanac roster, provides one
validated New/Edit habit form, persists complete active-habit state, and exposes
reversible activity controls plus deliberate permanent deletion.

This feature owns habit configuration and lifecycle management. It does not own
Today progress cards, logging, bucket-history presentation, the eventual habit
detail destination, notification permission or scheduling, haptics, or release
evidence.

## Habit management boundary

Add a main-actor `HabitManagementOperations` API to TendCore rather than writing
SwiftData models directly from views. Keep persistence models permissive for
migration and imported-data compatibility; enforce owner-entered values at the
operation boundary.

Represent editable values with a small value type that contains name, target,
unit, pinned weekdays, and optional reminder time. Creation accepts that value
plus cadence. Update deliberately has no cadence parameter, making cadence
mutation unrepresentable through the supported API.

The operation boundary must:

- trim leading and trailing whitespace from name and unit;
- reject an empty normalized name, an empty normalized unit, or a target below
  one;
- preserve internal text and arbitrary unit labels without conversion
  semantics;
- force pinned weekdays to none for a daily habit and preserve zero or more
  pinned weekdays for a weekly habit;
- permit a reminder on a weekly habit with no pinned days—the form warns about
  the consequence, but this is a valid stored configuration;
- surface typed validation and persistence failures instead of partially
  applying a mutation.

Creating a habit at an injected instant and time zone writes one transaction
containing the active `Habit`, an open `HabitActivityPeriod` beginning at that
instant, and the daily or Monday-through-Sunday `HabitBucket` containing the
instant. The habit is immediately due and can be consumed by lifecycle, streak,
and logging operations without repair or a second launch.

Before updating target or unit on an active habit, reconcile it at the injected
instant and time zone. Buckets that became final therefore freeze the old
requirement before the new requirement is applied to the open bucket, any grace
bucket, and the future. Inactive habits have no mutable buckets and are not
reconciled or reactivated by an edit. Save all editable fields together; a
failed save leaves the prior configuration intact.

Permanent deletion accepts a persisted habit, deletes it through its owning
model context, and saves once. Existing cascade relationships remove activity
periods, buckets, and log entries. UI confirmation is mandatory, but the domain
operation does not pretend that confirmation can make deletion reversible.

No schema version, model property, relationship, bucket rule, streak rule, or
logging operation changes in this feature.

## All Habits roster

Install an `AllHabitsView` inside the existing `HabitsDestinationChrome`. Query
the production model context; never use sample data, an in-memory fallback, or a
duplicate view-owned store.

Partition every persisted habit into exactly one section:

- **ACTIVE:** raised rows showing name, localized requirement, cadence, optional
  pinned-day summary, and the current streak.
- **INACTIVE:** sunken dormant rows showing the muted name and requirement plus
  the frozen streak phrased as “held at N days” or “held at N weeks.”

Sort each section by the owner-visible name using localized comparison, with
creation time and identifier as deterministic tie-breakers. Omit an empty
section rather than rendering decorative empty chrome. With no habits, omit both
sections; the filled moss add button remains the obvious action, while Today
owns the first-launch explanation.

Requirement values use locale-aware integer formatting and the stored unit
label. The built-in `times` label renders as `time` only when the target is one;
other owner-written labels are not guessed or inflected. Streaks always include
their cadence unit with correct singular/plural spelling.

Derive streak text from `HabitStreakComputation` at the owner's current local
instant and time zone. Recompute after every management mutation and at each
calendar-local day boundary so an open grace bucket, an at-risk chain, and a
frozen inactive streak never go stale while the app remains open. Normal active
streaks use moss, at-risk streaks use accessible ochre-deep, and inactive
streaks use faint ink. Never substitute `bestStreak` or zero when current-streak
computation fails; keep the row, label the streak unavailable, and expose a
retry.

The roster header matches the All Habits comp: New York “Habits” at leading and
a filled 40-point moss add control at trailing with a minimum 44-point hit area,
the VoiceOver label “New habit,” and a stable identifier.

The static row layout remains identical to the comp. Less-frequent management
actions use native trailing swipe actions, with the same actions available from
the row context menu and as VoiceOver custom actions:

- active habit: Edit, Archive, Delete;
- inactive habit: Edit, Reactivate, Delete.

Archive calls `HabitActivityOperations.deactivate` at the current local instant,
without confirmation, and moves the row to INACTIVE only after the save
succeeds. Reactivate calls `HabitActivityOperations.reactivate`, immediately
makes the containing bucket due, and moves the row to ACTIVE only after success.
Do not reproduce lifecycle logic in the app target.

Row selection and the full detail destination belong to
app-experience/habit-detail-history. This feature leaves rows ready to become
navigation links later but does not ship a placeholder detail screen, a router,
or an interim destination with competing ownership.

## New and Edit habit form

Use one reusable, scrollable Almanac form presented as a sheet from the roster
add control, the Today first-launch action, or a row's Edit action. New mode
starts from explicit draft state; Edit mode copies the persisted configuration
and does not mutate the habit until Save succeeds. Cancel dismisses without a
write.

The form follows the Edit Habit board:

- a navigation row with clay-deep Cancel, centered “New habit” or “Edit habit,”
  and moss Save;
- tracked uppercase field labels;
- paper-sunken fields with 10-point radius and 12/14-point padding;
- target and unit sharing one row when space permits and stacking without
  truncation at larger Dynamic Type sizes;
- 40-point fully rounded pinned-day controls with selected days filled clay and
  a minimum 44-point hit area;
- no shadows and no native Form/list background.

New mode contains:

- Name, initially empty.
- Cadence, initially Daily, as a Daily/Weekly choice.
- Target, initially `1`, using positive-integer input.
- Unit, initially `times`.
- Pinned Days only while cadence is Weekly.
- Reminder, initially None, with an explicit way to choose or clear a local time
  of day.

Changing a New draft from Weekly to Daily clears pinned days immediately.
Changing back to Weekly does not restore the cleared selection. Reminder time
may remain set because daily habits also support reminders.

Edit mode exposes the same values but renders cadence as a locked, muted field
with a lock glyph and the exact explainer: “Set at creation. To change cadence,
archive this habit and plant a new one.” It never offers a hidden cadence
mutation path.

Save is disabled until the normalized name and unit are nonempty and target is a
parseable positive integer. Invalid fields expose concise inline guidance after
interaction and through VoiceOver. A weekly draft with a reminder and no pinned
days remains saveable but shows an in-place ochre-deep warning that no reminder
will fire until a day is pinned. Beneath weekly day chips, retain the comp note:
“Reminders fire on pinned days. Logging any day still counts.”

Save calls `HabitManagementOperations` once. Success dismisses the sheet and
lets SwiftData update the roster. Failure keeps the owner's draft on screen,
announces an honest inline error, and offers retry; it never dismisses, clears
fields, or shows a spinner. Storing reminder configuration does not request
notification permission or schedule a notification.

## Permanent deletion

Delete always opens an Almanac confirmation surface before any write. Name the
habit and the loss explicitly: the habit and its entire history will be removed
permanently. An active habit offers Archive as the prominent reversible
alternative alongside Cancel and a withered Delete action. An inactive habit
states that it is already archived and offers Cancel plus Delete. Do not use an
alarm-red destructive control; withered is Tend's destructive state color.

Only the final Delete action calls `HabitManagementOperations.delete`. While the
confirmation is open, no model changes. A failed deletion leaves the habit and
history visible, keeps the confirmation recoverable, and reports the failure
without a fake success or spinner.

## First launch

When the shared model context contains no habits, Today renders one body
sentence—“Tend is a quiet place to grow the habits you want to keep.”—and one
filled moss primary action, “Plant a habit.” The action opens the same New habit
form. After the first successful save, the introduction disappears immediately;
app-experience/today-dashboard owns the nonempty Today body.

Deleting the last habit returns Today to this state. This is a zero-habit state,
not a one-time onboarding flag: do not persist dismissal state or add
`AppStorage`.

## Accessibility, adaptation, and appearance

Reuse the Almanac foundations and existing custom shell. On compact iPhone,
match the 402-point All Habits and Edit Habit boards through flexible safe-area
layout rather than fixed screen coordinates. On iPad, keep the full paper
background and center roster/form content at the shell's readable maximum
width; do not introduce a sidebar or stretch rows edge to edge.

Habit names wrap and never ellipsize through two larger Dynamic Type steps.
Scrollable content remains reachable above the keyboard and floating tab pill.
Every add, field, day, row action, confirmation, and retry target is at least 44
points. VoiceOver announces:

- each section and habit name;
- requirement, cadence, active/dormant state, and full streak phrase;
- selected state and unambiguous weekday name for every pinned-day control;
- locked cadence plus its explanation;
- inline validation, warning, persistence error, and deletion consequences.

Swipe-only discovery is prohibited; context-menu and accessibility actions
mirror every row action. No management transition conveys meaning through
animation, and incidental sheet/row changes honor Reduce Motion. Habit
management adds no haptic.

## Verification

TendCore tests prove creation graph completeness, validation and normalization,
cadence immutability, pre-edit reconciliation and requirement snapshots,
daily/weekly pinned-day handling, save rollback, and cascading deletion.

App-unit tests prove form draft/default/validation behavior, weekly visibility
and warning rules, edit cadence locking, roster partition/sort/formatting,
calendar-boundary refresh, exact operation dispatch, retryable failures, and
zero-habit state transitions without depending on SwiftUI hierarchy text.

UI tests start from an isolated empty on-device store and exercise the owner
contract end to end: launch into first-habit creation; reject invalid drafts;
create daily and weekly habits; verify active/inactive roster facts; edit all
mutable fields while cadence stays locked; Archive and Reactivate; cancel and
confirm deletion; delete the final habit; and observe Today return to its
zero-habit state. Tests assert labels, values, traits, confirmation copy, and
persisted results rather than source names or incidental view depth.

Manual acceptance compares All Habits, New/Edit Habit, deletion, and first-launch
surfaces on a compact iPhone and iPad against
`.tiller/design/comps/tend.pen`. A second pass covers two larger Dynamic Type
steps, VoiceOver reading and custom actions, 44-point targets, keyboard
avoidance, accessible deep color variants, forced light appearance, and Reduce
Motion.

## Ownership and non-goals

This feature may add TendCore habit-management operations and tests, app-target
roster/form/empty-state sources, app-unit and UI tests, and debug-only launch
support for deterministic test data. Debug support must still exercise a real
isolated SwiftData store and production operations; no sample rows or runtime
fallback may enter release behavior.

Do not change the persistence schema, Almanac tokens, root destination model,
Pencil comp, bucket/streak/logging semantics, or shell selection persistence.
Do not add a habit detail/history screen, Today habit card, log control, reminder
permission prompt or scheduler, notification behavior, haptic, dark appearance,
network call, analytics path, third-party dependency, app-store packaging, or
release-device evidence.
