# Build Scoped Quantity Log Sheet

## Approach

Wire every available non-`times` Today ring/check to present one standard iOS
sheet backed by `TodayLoggingModel`. The at-risk line opens the same sheet with
the grace period selected. A `times` control must never reach this sheet.

Build a focused `QuantityLogSheet` matching the approved Pencil `Log Sheet`
board: paper surface, visible grabber, exact habit name, daily or weekly scope
control, progress track/meta and streak, quick chips, collapsed amount actions,
then selected-period entries. Use medium and large platform detents with an
internal scroll surface. Keep the sheet presented after successful writes and
when the bucket becomes met; dismiss only by the owner or when the habit becomes
ineligible/disappears.

Scope labels are Today/Yesterday for daily and This Week/Last Week for weekly.
Render grace only when supplied by the domain projection and draw the six-point
ochre unfinished marker only below target. Selection changes every progress,
quick-add, amount, entry, and delete operation to that explicit period key.

Render pure model quick adds in ascending order as stroked moss pills, followed
by the filled moss `Finish · N unit` when remaining is positive. Every chip has a
44-point hit region, exact amount label, and one append action. Reflow chips at
larger text sizes rather than compressing or horizontally clipping them.

The collapsed sunken amount row contains separate **Custom amount** and clay-deep
**Set day total**/**Set week total** buttons. Tapping either expands one inline
number-pad editor with matching title, Add/Set total, and Cancel. Focus the field
on expansion; keyboard submit performs the primary action. Keep invalid input
and model errors inline. Accepted input clears/collapses only after a completed
write; equal-total no-op may collapse without feedback or Undo. Lower total uses
exact copy `Delete an entry before lowering the total.`

List entries under the cadence/scope-aware tracked heading. Daily entries show
localized time and amount; weekly entries add localized abbreviated weekday.
Each trailing minus-circle is a real delete button keyed by persistent identity
and named with date/time plus amount. Delete immediately without confirmation,
refresh the sheet and Today on success, and keep the row plus inline error on
failure. Use the subdued empty-period sentence when needed.

Consume the same logging-model Undo in the underlying Today card and, when its
habit matches the open sheet, reflect Undo success in the selected scope without
dismissing. Do not add a second sheet-local undo stack. Completed quantity checks
remain buttons so owners can add or correct real entries after meeting target.

Accessibility exposes the sheet title, selected scope and unfinished state,
truthful progress/streak, each chip, both editor modes, validation, entries, and
delete controls in visual order. Decorative dot/track/fill/minus glyph geometry
is silent. Maintain keyboard dismissal, VoiceOver focus after scope changes,
44-point targets, two larger Dynamic Type steps, Reduce Motion, forced light,
safe-area clearance, and centered iPad adaptation.

## Surfaces

- Create `App/Tend/Today/QuantityLogSheet.swift` for the sheet and small private
  reusable controls.
- Modify `App/Tend/Today/TodayView.swift` only to route non-`times` ring/risk
  activation and present the model-backed sheet.
- Modify `App/Tend/Shell/TodayDestinationChrome.swift` only if the shared
  logging-model/fresh-context seam from the predecessor task needs quantity
  wiring.
- Extend `App/TendUITests/FastLoggingUITests.swift` with the exact
  `testQuantityLoggingJourneys` method and shared deterministic helpers.
- Modify `App/TendUITests/TodayDashboardUITests.swift` only where quantity rings
  now intentionally open a sheet.
- Reuse existing Almanac tokens and `TodayLoggingModel`; do not add another
  amount model, custom overlay, navigation destination, persistence operation,
  or haptic coordinator.
- Do not edit TendCore semantics/schema, habit forms, Habit Detail, reminders,
  or shell destinations.

## Tests

Run:

```bash
Scripts/tiller-xcode-test TendUITests/FastLoggingUITests/testQuantityLoggingJourneys
Scripts/tiller-xcode-test TendUITests/TodayDashboardUITests
Scripts/tiller-xcode-test TendTests/TodayLoggingModelTests
Scripts/tiller-xcode-test TendTests/TodayModelTests
swift build
```

Use independent named stores to prove:

- exact `time` and other quantity rings open the sheet without changing progress,
  while exact `times` writes directly and never presents it;
- partial daily progress renders Today plus real Yesterday grace, default and
  at-risk preselection, unfinished dot, exact progress/streak, and entries;
- weekly Monday state renders This Week plus real Last Week and cadence-aware
  labels/entry timestamps without daily sub-buckets;
- targets from fixtures expose exact friendly presets and Finish; presets append
  their amount, Finish appends only remaining, and complete/over-target state
  removes zero Finish but remains loggable;
- custom positive entry persists, while empty, zero, negative, nondecimal, and
  overflow input remain inline and nonmutating;
- Set day/week total appends only a positive difference, equal total creates no
  entry/Undo/feedback, and lower total shows exact guidance;
- selecting each scope constrains progress, writes, entries, delete, and Undo to
  its explicit period key;
- newest-first entry rows retain deterministic order, exact visible amounts, and
  stable delete identity; delete updates Today/sheet, rejected delete does not;
- completed quantity checks reopen the sheet, dismissal preserves data, and
  same-store relaunch preserves entries with no sheet/editor/Undo restoration;
- every sheet control has stable identifier, exact label/value/trait and
  44-point geometry, keyboard submit/cancel work, long content scrolls at both
  detents, and representative larger-type/Reduce-Motion states remain operable.

## Edge cases

- A met grace bucket remains selectable without the unfinished dot.
- Scope expiry while open falls back to current and announces the change; a
  simultaneous stale-key write remains nonmutating and visible as an error.
- Quick-add values can legitimately exceed remaining; only Finish promises exact
  closure.
- Duplicate entry UUIDs/timestamps/display text never cause the wrong delete.
- A very long habit name, unit, localized number, or validation message wraps and
  does not cover the drag indicator or home indicator.
