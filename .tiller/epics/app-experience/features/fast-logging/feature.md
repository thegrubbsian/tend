# Fast Logging and Back-fill

## Summary

Turn Today’s established ambient rings into the owner’s fastest write path. The
exact stored unit selects the interaction: `times` logs one count directly,
while every other unit opens the approved quantity sheet. Both paths write
through TendCore, update Today atomically, expose one transient Undo, and make
the still-editable grace bucket a first-class back-fill destination.

This feature owns editable-bucket projection, unit-specific dispatch, quick-add,
custom amount, cadence-aware set total, per-entry delete, transient Undo,
logging motion and haptics, and the `Log Sheet`/`Affordance States` boards. It
does not change cadence, reconciliation, bucket finality, streak arithmetic,
habit lifecycle, reminders, Habit Detail, or the custom two-destination shell.

## Editable logging projection

Add one main-actor TendCore read boundary for an active persisted habit’s
editable logging scopes. It reconciles once at an explicit instant and time zone,
then returns one coherent snapshot containing:

- the habit’s stable persistent identity, exact name, cadence, target, and unit;
- the current open bucket’s period key, progress, target, unit, and entries;
- the immediately preceding bucket only while its evaluated phase is `grace`;
- whether each scope is provisionally met;
- each entry’s stable persisted identity, UUID, timestamp, and positive amount.

Use `BucketReconciler`, `BucketEvaluator`, and `CalendarBucketSchedule`; do not
reimplement period selection, phase transitions, relationship validation,
progress arithmetic, grace duration, or finality in the app target. The current
scope is the local day for daily habits and the containing Monday-through-Sunday
period for weekly habits. Pinned weekdays never limit logging.

Sort entries newest timestamp first, then by stable persisted identity. Return a
typed failure for detached, inactive, invalid-cadence, invalid-requirement,
missing, duplicate, foreign, malformed, overflowed, reconciliation, evaluation,
or save states. Never omit a malformed entry, substitute a zero, or publish a
partially reconciled snapshot.

The app labels the scopes from cadence:

- daily: **Today**, plus **Yesterday** only while the preceding daily bucket is
  in grace;
- weekly: **This Week**, plus **Last Week** only while the preceding weekly
  bucket is in grace. Under the Monday-through-Sunday schedule this is available
  on Monday, but availability is derived from evaluation rather than a hard-coded
  weekday check.

Mark the grace scope with the six-point ochre dot only while its progress is
below target. All sheet facts and writes are scoped to the selected period key.
The current scope starts selected unless the owner entered through the at-risk
line, which selects the grace scope directly.

## Logging presentation model

Add a main-actor observable logging model with an injected operations boundary
and a live adapter to the editable projection plus `LogEntryOperations`. Every
action captures one operation context—fresh production instant, time zone,
calendar, and locale—and uses it for authorization, mutation, re-projection,
Today refresh, formatting, feedback, and Undo metadata. DEBUG fixed-instant
journeys inject their deterministic clock; production taps must not reuse a
TimelineView date sampled minutes earlier.

The exact stored unit string `times` selects count logging. `time`, `times `,
localized words, and every other owner-written unit are quantity units. Do not
infer behavior from target, cadence, singularization, or substrings.

Publish sheet and dashboard changes only after the TendCore write and complete
re-projection succeed. On failure, retain the last complete dashboard and sheet,
show a concise inline error beside the attempted control, send no success
feedback, and leave no Undo. Respect `ModelContext.rollback()` behavior from the
domain operation; never patch presentation progress optimistically.

Re-resolve scopes after every mutation, query change, scene activation, local
boundary, calendar/time-zone change, and sheet presentation. A selected period
that ceases to be editable disappears; select the current scope, announce the
change, and keep any failed stale write nonmutating. Dismissing the sheet clears
input and sheet-only errors, not persisted entries.

## One-tap `times` logging

For any available `times` row, the 52-point unmet ring and 44-point completed
check are real buttons. Activating either appends exactly `1` to the current
bucket. A target-one habit completes in one activation; a multi-count habit
increments once per activation and moves to TENDED only when the target is met.
A completed check may log another real instance, preserving truthful over-target
history; its quiet compact treatment remains visually settled rather than
promotional.

The at-risk line is a separate direct action. For a `times` habit it appends
exactly `1` to the explicit grace period key without opening a sheet. If a
multi-count grace bucket remains unmet, the line remains available for another
activation. Authorization still comes from `LogEntryOperations`; no back-fill is
possible after grace expires.

Each successful append immediately rebuilds the complete Today presentation, so
progress, section membership, fraction, ring state, streak, and risk agree in one
published generation. Repeated taps are distinct entries, never a combined
counter or in-place edit.

## Quantity log sheet

For every available non-`times` row, activating either the unmet ring or
completed check presents the platform sheet over Today. Use the standard sheet
spring, visible drag indicator, medium and large detents, and an internal scroll
surface when content exceeds the detent. Keep the selected period and inputs in
one sheet model; do not create a navigation destination or full-screen form.

Match the approved `Log Sheet` board in
`.tiller/design/comps/tend.pen`, in this order:

1. exact owner-written habit name;
2. cadence-aware segmented scope control;
3. eight-point sunken progress track and truthful `progress of target unit`
   text, followed by the current streak;
4. quick-add chips;
5. collapsed **Custom amount** and **Set day total** or **Set week total** row;
6. cadence-aware **LOGGED TODAY**, **LOGGED YESTERDAY**, **LOGGED THIS WEEK**, or
   **LOGGED LAST WEEK** entry list with per-entry delete.

The collapsed amount row has two direct actions. Either expands one inline
integer editor and focuses the number keyboard. Custom mode accepts a strictly
positive integer and exposes **Add** plus **Cancel**. Set-total mode accepts a
nonnegative integer and exposes **Set total** plus **Cancel**. Keyboard submit
performs the primary action. Invalid, empty, overflowed, or below-progress input
stays in the editor with an inline message and no mutation; a lower total says
`Delete an entry before lowering the total.` This is a focused amount editor,
not a general habit form or a second sheet.

Custom and quick-add actions call `append`. Set total calls `setTotal` against
the selected period key. An equal total is a successful no-op: keep the sheet
stable but create no entry, haptic, animation, or Undo. A greater total appends
only the positive difference. The UI never rewrites or combines prior entries.

### Quick-add derivation

Derive at most two preset amounts from the selected bucket’s target using a pure,
overflow-safe helper:

1. integer-divide the positive target by `6` and by `3`;
2. clamp each sub-one result to `1`;
3. round each result down to the greatest friendly value of the form
   `1`, `2`, or `5` times a power of ten;
4. deduplicate and sort ascending.

For example, target `30` produces `+5` and `+10`; target `8,000` produces
`+1,000` and `+2,000`; target `3` produces `+1`. Preset amounts are based on the
target, not current progress, and may legitimately take an over-target habit
farther over.

When progress is below target, append a filled rightmost
`Finish · N unit` chip for the exact positive remaining amount. Suppress a
preset that equals the remaining amount so two controls never perform the same
write. When progress is met or over target there is no zero-valued Finish chip;
the preset and custom paths remain available for truthful additional logging.

After any successful sheet mutation, keep the sheet open, preserve its selected
scope when still editable, clear accepted input, and refresh progress, quick
adds, entries, Today grouping, and Undo state together.

## Entry history and delete

List only entries belonging to the selected bucket. Daily rows show localized
time plus amount and unit; weekly rows show localized abbreviated weekday and
time plus amount and unit. Preserve exact integer amounts and owner-written unit
text. Each row resolves and deletes by stable persisted identity through
`LogEntryOperations.delete`; never delete by array index, timestamp, UUID alone,
or displayed text.

Delete is immediate and unconfirmed because open/grace log correction is a
routine action. A successful delete refreshes the selected sheet and Today
atomically. It does not create transient Undo. Final, exempt, foreign, or stale
entries remain nonmutating failures with an inline error. If the deleted entry
is the entry currently offered by transient Undo, cancel that Undo window.

When no entries exist, show one subdued `Nothing logged in this period.` line
instead of an empty decorative list. Dismissal and relaunch preserve committed
entries; relaunch never restores transient sheet, input, or Undo state.

## Transient Undo

Keep at most one transient Undo across Today. Every successful append—including
one-tap `times`, grace back-fill, quick-add, custom amount, and a positive
set-total difference—replaces the prior Undo with the newly created entry.
Display `Logged N unit · Undo` in that habit card’s meta area for five seconds.
A card that moved into compact TENDED temporarily gains this second line so the
action never disappears during regrouping.

Activating Undo deletes that exact persisted entry through
`LogEntryOperations.delete` using a fresh operation context. On success, rebuild
Today and any open sheet, issue the Undo feedback, and clear the window. On
failure, keep the entry and show a concise inline error; do not claim it was
undone. Expiry removes only the presentation affordance. A later log supersedes
the earlier affordance without deleting either entry. Undo state is neither
persisted nor recreated on relaunch.

## Almanac interaction, motion, and haptics

Preserve the existing card geometry, paper surfaces, type, section order, risk
treatment, progress text, and centered readable width. Add the plus glyph to
empty and in-progress rings. Ring progress grows clockwise from twelve o’clock
over the sunken track. Completion cross-fades to the solid moss check and uses
the restrained `1 → 1.06 → 1` soft spring over about 450 milliseconds. Other
progress changes animate like a short liquid fill. With Reduce Motion, replace
fills and blooms with cross-fades; no meaning depends on motion.

Use the established Almanac colors: moss for logging controls, paper for check
and filled-chip content, ochre for unfinished grace, and clay-deep for Undo and
set-total text below 20 points. No shadow, confetti, alarm red, score, badge,
confirmation dialog, or celebratory copy is introduced.

Feedback is event-based, never view-appearance-based:

- light impact after a successful log that leaves the selected bucket unmet or
  was already met;
- success notification only when the write crosses from unmet to met;
- lighter selection feedback after successful Undo;
- no feedback for presentation, validation, equal-total no-op, failure, expiry,
  refresh, relaunch, or entry deletion.

## Accessibility and adaptation

Every ring/check is a minimum 44-point button with a deterministic identifier.
Its label names the habit; its value announces exact progress toward target,
current streak, met state, and risk stakes; its hint states either `Logs one
instance` or `Opens log sheet`. Hide decorative arcs, tracks, dots, and glyphs.
The visual card facts must not create a second duplicate reading of the same
content. Unavailable rows retain their existing nonlogging summary and retry.

The at-risk line is a separately reachable button whose label names the explicit
Yesterday or Last Week action. Undo is a separately reachable button named for
habit and amount. Scope controls announce selected state and `unfinished` when
the grace dot is present. Amount fields, Add/Set/Cancel, every quick-add chip,
and each delete button have complete labels and values; delete names the entry’s
localized date/time and amount. Sheet errors are announced when they appear.

Controls meet 44-point targets. Owner names, units, progress, chip labels,
entries, and errors wrap without truncation through two larger Dynamic Type
steps. Chips and scope controls reflow rather than shrink below target size. The
sheet remains keyboard- and VoiceOver-operable at medium and large detents,
clear of the home indicator and floating shell pill. Forced light appearance
remains unchanged.

## Consistency and failure boundaries

All mutations use `LogEntryOperations` and explicit selected period keys. Do not
write SwiftData models directly, cache progress, edit entries in place, weaken
bucket authorization, synthesize a missing bucket, or catch-and-ignore a domain
error. A successful save is the only point that triggers presentation refresh,
Undo, motion, or haptic feedback.

The production habit query remains the source of active rows. If a habit is
archived, deleted, or malformed while a sheet or Undo is active, dismiss or
clear the stale presentation and perform no retargeted write. Identity is always
the SwiftData persistent identifier, never array position, owner name, or UUID
alone. Every refresh constructs a complete replacement before publication.

## Verification

TendCore tests prove editable current/grace projection for daily and weekly
cadence, Monday and midnight boundaries, DST and time-zone changes, entry order
and identity, active/persisted/relationship validation, progress overflow,
reconciliation, typed failures, and no partial publication.

App-unit tests prove exact `times` dispatch, pure friendly quick-add derivation,
daily/weekly labels and scope selection, stable entry mapping, custom/set-total
validation, one sampled operation context, atomic post-write refresh, error
retention, stale-scope handling, single five-second Undo replacement/expiry,
exact-entry Undo, and feedback decisions independently of SwiftUI.

UI tests use DEBUG-only named file stores seeded through public TendCore
operations. They prove target-one and multi-count one-tap logging, completed
count logging, direct grace back-fill, section/fraction/risk transitions,
transient Undo and expiry, daily and weekly sheet scopes, quick-add and Finish,
custom amount, day/week set total including equal and below-progress cases,
entry deletion, completed quantity access, persistence across dismissal and
relaunch, and the exact-unit boundary where `time` opens a sheet but `times`
does not.

Visual evidence compares compact iPhone states with the approved `Today`, `Log
Sheet`, and `Affordance States` boards. Exercise empty, in-progress, completion,
Undo, current/grace, daily/weekly, validation, empty entries, and long-content
states. Repeat representative journeys at two larger Dynamic Type steps with
VoiceOver, Reduce Motion, forced light appearance, and keyboard presentation.
Physical-device review verifies haptic character and manual VoiceOver traversal;
automation and simulator screenshots never attest those observations.

## Out of scope

Do not add fractional or negative amounts, entry editing, bulk logging, arbitrary
historical dates, buckets older than grace, weekly daily sub-buckets, reminders,
notification permission, Habit Detail navigation, habit-management changes,
cloud/network behavior, analytics, a third destination, a third-party
dependency, dark appearance, native iPad support, or release packaging.
