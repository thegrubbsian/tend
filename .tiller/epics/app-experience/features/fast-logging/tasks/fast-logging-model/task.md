# Model Fast Logging Interactions

## Approach

Add a main-actor observable `TodayLoggingModel` between Today’s persisted rows,
`HabitLoggingComputation`, `LogEntryOperations`, and SwiftUI. Keep dashboard
projection in `TodayModel`; the logging model owns only selected sheet state,
amount editing, write dispatch, transient Undo, inline mutation errors, and
feedback events. Its successful mutation path asks TodayModel to rebuild from
the same completed store generation before control returns to the view.

Define an injected `TodayLoggingOperations` boundary for editable snapshot,
append, set total, and exact-entry delete. Every method receives one explicit
`TodayRefreshContext`; the live adapter forwards its instant and time zone to
TendCore. Tests inject closures, a controllable sleeper, deterministic contexts,
and lightweight or in-memory model values without a file store or SwiftUI.

The exact unit equality `unit == "times"` selects direct count logging. Expose
methods for current-ring activation and at-risk activation:

- direct `times` activation appends `1` to current or explicit grace period;
- quantity activation projects and publishes the sheet, selecting current or
  explicit grace scope without writing;
- unavailable, stale, inactive, or disappeared habits publish no retargeted
  action.

Model `LogSheetPresentation` as a complete immutable value with stable habit and
scope identity, cadence-aware labels, selected progress/target/unit/met state,
current streak, ordered copied entries, progress fraction, quick-add controls,
amount-editor mode/value/error, and sheet-level error. Re-project after every
successful write and external refresh. Preserve the selected period only while
it remains in the returned editable set; otherwise select current and expose an
announcement token.

Implement a pure `QuickAddAmounts` helper exactly from the feature contract:
target divided by six and three, sub-one clamped to one, rounded down to
`{1, 2, 5} × 10^n`, unique ascending presets, remaining Finish amount when
positive, and preset/Finish deduplication. All arithmetic is overflow-safe.

Validate string input before calling TendCore. Custom amount requires a positive
`Int`; set total requires a nonnegative `Int`. Empty, signed-negative,
nondecimal, overflow, and lower-than-progress input stay local and nonmutating.
Equal total calls the injected domain operation and treats its nil result as a
stable no-op with no Undo or feedback.

Keep exactly one `TodayLogUndo` with habit persistent identity, exact live entry,
copied amount/unit, origin period key, generation token, expiry, and inline
error. Every successful returned entry replaces it and starts a five-second
expiry. A stale sleeper completion must not clear a newer generation. Undo uses
a fresh context and deletes the exact stored entry; success clears it and
refreshes Today plus any open matching sheet. Failed Undo retains both entry and
affordance. External deletion of that entry clears it. No undo state survives
model recreation.

Emit value-semantic feedback events for ordinary log, unmet-to-met completion,
and successful Undo. Decide completion by comparing the selected bucket before
and after the write, not by amount or target guess. Do not emit for projection,
validation, equal-total no-op, failures, expiry, refresh, sheet presentation,
entry delete, or relaunch.

## Surfaces

- Create `App/Tend/Today/TodayLoggingModel.swift` for operation injection,
  sheet/amount/Undo state, dispatch, mutations, expiry, refresh, and feedback
  events.
- Create `App/Tend/Today/TodayLoggingFormatter.swift` only if keeping labels,
  entry timestamps, units, and stable error copy out of the model improves
  readability; reuse existing Today formatting rules instead of creating a
  second locale convention.
- Modify `App/Tend/Today/TodayModel.swift` only at the narrow successful-mutation
  refresh seam needed to rebuild the dashboard coherently.
- Create `App/TendTests/TodayLoggingModelTests.swift`.
- Do not edit SwiftUI views, UI-test fixtures, haptic APIs, shell navigation,
  persistence schema, or TendCore domain semantics in this task.

## Tests

Run:

```bash
Scripts/tiller-xcode-test TendTests/TodayLoggingModelTests
Scripts/tiller-xcode-test TendTests/TodayModelTests
Scripts/tiller-xcode-test TendTests
swift build
```

The focused suite must prove:

- only exact `times` performs direct append; `time`, case/space variants, and
  owner units present quantity state without writing;
- current and grace activations pass exact persistent habit and period identity;
- daily/weekly scope labels, grace unfinished marker, entry-list label, default
  selection, and at-risk preselection are correct;
- targets `3`, `30`, `64`, and `8,000`, progress below/equal/above target,
  integer boundaries, preset ordering, and Finish deduplication match the pure
  algorithm;
- custom and set-total parsing reject every invalid form before an operation;
- positive append, positive set-total difference, equal-total nil, lower total,
  overflow, domain failure, and save failure produce the specified complete
  state and feedback;
- each action uses one supplied context and a post-write projection before
  dashboard refresh or publication;
- scope selection survives valid refresh, falls back when stale, and never sends
  an old key as current after a boundary;
- entry delete targets the live entry/persistent identity, refreshes on success,
  leaves it visible on failure, and clears matching Undo only;
- one Undo appears for each returned entry, moves with a regrouped card, replaces
  an older window, expires at five seconds, ignores stale expiry, deletes the
  exact entry, retains failures, and starts empty after reconstruction;
- feedback distinguishes unmet-to-unmet, unmet-to-met, already-met append, Undo,
  no-op, delete, failure, refresh, and expiry.

## Edge cases

- A sheet may remain open after its habit becomes met or over target; Finish then
  disappears while preset/custom logging remains valid.
- A met grace scope is included but has no unfinished dot.
- A log can move a card between sections; Undo metadata follows persistent habit
  identity, never the old row instance or position.
- A later log supersedes the prior affordance without deleting prior history.
- Model cancellation or view disappearance cancels only expiry work, never a
  committed entry.
