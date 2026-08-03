# Build the Almanac habit detail surface

## Approach

Build the reusable full-screen Habit Detail destination on top of
app-experience/habit-detail-history/history-projection (T-dr7wdw). Start with
`HabitDetailModelTests`: bind the TendCore snapshot to owner-visible state,
exercise every mutation path, and observe those contracts fail before writing
the SwiftUI surface.

Add a main-actor observable `HabitDetailModel` that owns:

- the persisted habit identity and current snapshot;
- injected current-instant and time-zone providers;
- selected-month state;
- loading, inline operation failure, and retry state;
- Edit presentation;
- one selected history fact for the transient callout; and
- exactly-once dispatch for delete entry, Archive, and Reactivate.

Use small closure seams for time and operation injection in tests. Do not add a
repository protocol, alternate store, global singleton, or cache. Production
initialization receives the shared `ModelContext` and creates
`HabitDetailComputation`, `LogEntryOperations`, and
`HabitActivityOperations` from that context.

Load atomically on first presentation. Replace the snapshot only after a full
successful recomputation. Recompute after successful Edit, entry deletion,
Archive, or Reactivate; on scene activation; and at the next local calendar-day
boundary while visible. Cancel the prior boundary task before scheduling a new
one and when the view disappears. On failure, preserve the raw habit name and
navigation, remove derived facts that can no longer be claimed current, retain
retryable owner input/action context, and never emit a second mutation while one
is in flight.

Move the roster's approved requirement, cadence, weekday, reminder, and streak
unit formatting into one focused app-internal formatter used by both roster and
detail. Preserve the roster's exact output and tests. Locale and calendar are
dependencies; do not use process-global formatter state or guess inflection for
owner-written units.

Create `HabitDetailView` as a scrollable Almanac surface with:

1. a compact custom navigation row with caller-supplied Back and trailing Edit;
2. the nontruncating habit title and wrapped requirement/cadence/pins/reminder
   metadata;
3. balanced CURRENT and BEST stats and a conditional quiet at-risk callout;
4. centered month controls;
5. a cadence-specific daily garden or weekly strip garden;
6. the `Met`, `Missed`, `Open` legend;
7. a recent-entry section with delete controls or a subdued empty sentence;
8. inline operation failure/retry near the affected section; and
9. the low-emphasis Archive habit or Reactivate habit action.

For daily history, use a Monday-first seven-column layout. Keep real and filler
cells exactly 44 points with radius 7 and distribute spacing across the readable
width. Filler geometry is noninteractive and accessibility-hidden. For weekly
history, use full-width 44-point strips for all projected periods. Both variants
are unnumbered and map semantic state to the Almanac fill/stroke/opacity grammar
without introducing raw colors or shadows.

Each real cell or strip is a plain button with an exact localized accessibility
label. Selection reveals an informational transient callout containing the
localized date or week range, semantic state, and provisional progress where
present. Keep it inside the readable wrapper on compact iPhone and dismiss it
on a second selection, outside tap, month change, or view dismissal. It must not
open the not-yet-owned logging surface.

Recent-entry rows format the projected effective unit and timestamp, expose a
minus-circle `Delete entry` button with a complete accessibility label, and
resolve the selected entry identifier back to the same habit before calling
`LogEntryOperations.delete`. If the entry disappeared, refresh instead of
deleting a different object. Never make final or exempt entries actionable.

Present the existing `HabitFormView` in Edit mode. Cancel leaves the current
snapshot unchanged; successful save dismisses and recomputes. Archive and
Reactivate call only `HabitActivityOperations`, stay on detail, and flip the
available lifecycle action after successful refresh. Permanent habit deletion
does not appear here.

When initial computation fails, render one Almanac inline failure card below the
known title with `Try again`; omit stats, garden, legend, and recent facts rather
than mixing stale and current truth. Operation failures keep the last verified
snapshot and identify the failed action.

## Surfaces

- Create `App/Tend/Habits/HabitDetailModel.swift`.
- Create `App/Tend/Habits/HabitDetailView.swift`; focused private supporting
  views may remain in this file unless independently reused.
- Create `App/Tend/Habits/HabitPresentationFormatter.swift` and refactor
  `HabitRosterModel.swift` to use it without output changes.
- Create `App/TendTests/HabitDetailModelTests.swift`.
- Modify `App/Tend/Almanac/AlmanacMetrics.swift` only for a repeated semantic
  measurement not expressible with existing tokens.
- Modify the Xcode project only if synchronized groups do not discover new
  sources and tests.
- Do not wire roster row selection, change shell/tab ownership, add UI-test
  fixtures, modify Today, create log-entry input, change TendCore behavior, or
  edit the Pencil comp in this task.

## Tests

Model tests cover:

- initial success and atomic initial failure;
- shared localized metadata/streak formatting with roster parity;
- previous/next month clamping and selected callout dismissal;
- exact daily and weekly accessibility labels and chronological order;
- no editable-entry fallback for final, exempt, or missing entries;
- exactly-once entry deletion followed by full refresh;
- a vanished selected entry refreshing without a foreign deletion;
- Edit cancel versus successful-save refresh;
- Archive and Reactivate dispatch, success refresh, and failure preservation;
- retry after computation and mutation errors;
- scene-active refresh and one replaceable local-midnight schedule;
- month rollover clamping an old selected page only when necessary;
- owner-written long name/unit values without lossy normalization; and
- inactive frozen facts without fabricated current progress.

Add focused SwiftUI inspection assertions only where existing project
conventions support behavior unavailable through the model. Do not test source
text, private view type names, exact hierarchy depth, or incidental formatter
internals.

Run:

- `Scripts/tiller-xcode-test TendTests/HabitDetailModelTests`
- `Scripts/tiller-xcode-test TendTests/HabitRosterModelTests`
- `Scripts/tiller-xcode-test TendTests/HabitFormModelTests`
- `Scripts/tiller-swift-test Tests/TendCoreTests/History/HabitDetailComputationTests.swift`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Launch a fixture or preview backed by an isolated persisted model context and
smoke-exercise both cadence layouts, month controls, callout, Edit return,
entry deletion, and lifecycle flip before handing the task off. This is
developer verification, not manual gate attestation.

## Edge cases

- The selected habit may be inactive before the view first loads.
- The habit or selected entry may be removed from the context by another
  surface; detail returns safely or reports unavailable rather than crashing.
- Month rollover may move the latest bound while the owner views an older page.
- A month can require six daily rows and a weekly page can contain six
  intersecting strips.
- Long localized month, weekday, cadence, unit, and accessibility strings wrap
  without changing bucket identity or hit-region size.
- An Edit can change current target/unit while finalized cells retain frozen
  requirement facts from the projection.
- Archive can turn an unsettled cell dormant; Reactivate can make the current
  bucket open immediately.
- Reduce Motion replaces semantic animation with no animation; no state meaning
  depends on movement.
