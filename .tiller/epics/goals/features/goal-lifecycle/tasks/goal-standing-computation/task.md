# Compute deadline pace and standing

## Approach

Build a pure, allocation-light standing computation on
goals/goal-lifecycle/goal-lifecycle-schema (T-i30n7j) and the normalized
kind-specific progress result from goals/goal-records (F-e149jw). Write
`GoalStandingComputationTests` before the implementation. Keep persistence
fetches, writes, formatting, timers, and UI colors outside the calculator.

Define public `Equatable` and `Sendable` values for:

- `GoalStanding`: on pace, behind, or past due;
- `GoalStandingSnapshot`: standing, actual normalized progress, optional
  expected normalized progress, optional resolved deadline boundary, and
  optional next time-only refresh;
- typed computation failures for invalid creation chronology, deadline,
  evaluation instant, closure data, or progress input.

The public computation accepts a Goal, its prerequisite progress result, an
explicit instant, Calendar, and TimeZone. Resolve a stored deadline date to the
start of its following local day. Require that exclusive boundary to follow
`createdAt`. Reject an evaluation instant before creation. Use real Date
durations between creation and the resolved boundary after calendar resolution;
do not assume every local day is 24 hours.

For an open goal with no deadline, return on pace with no expectation,
boundary, or next refresh. For an open deadlined goal at or after the boundary,
return past due even when actual progress is complete or over target. Before the
boundary, calculate expected progress as elapsed duration divided by total
duration, clamped from zero through one. Equality is on pace; lower actual
progress is behind.

Derive the next time-only refresh without scheduling it:

- nil for no deadline, closed, or already past-due;
- the deadline boundary for a behind goal;
- the point after which expectation can overtake unchanged actual progress for
  an on-pace goal below complete;
- the deadline boundary for progress at or above complete.

Closed goals return no standing snapshot; their checked closure value remains
available directly from Goal. Validate that the progress result belongs to the
same goal kind and contains a finite, nonnegative normalized value. Consume
over-achievement honestly; never cap accumulate progress before comparison.

## Surfaces

- Create `Sources/TendCore/Goals/GoalStandingComputation.swift`.
- Create
  `Tests/TendCoreTests/Goals/GoalStandingComputationTests.swift`.
- Reuse the Goal, GoalClosure, local deadline representation, and progress
  result defined by prerequisite work.
- Do not modify SwiftData schema, goal progress operations, habit
  computations, app UI, or notification code.

## Tests

Bind feature criterion C2 to `GoalStandingComputationTests`.

Cover no-deadline open goals; exact creation; before, at, and after the
expectation threshold; exact deadline boundary; past-due complete and
over-complete goals; closed harvested and let-go goals; accumulate, increasing
measure, and decreasing measure progress; and the worked books and weight
examples from `.tiller/feedback/06-goals.md`.

Use explicit Gregorian calendars and time zones to cover a deadline on the
creation day, a spring-forward day, a fall-back day, a time-zone change, and a
deadline edited into the past but still after creation. Assert expected
fractions and next refreshes from resolved instants, not fixed 24-hour
assumptions.

Reject an instant before creation, a deadline whose full day ended at or before
creation, malformed or unknown closure, non-finite or negative progress, and a
kind-mismatched progress result.

Run:

- `Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalStandingComputationTests.swift`
- the focused progress test file created by goals/goal-records (F-e149jw)
- `Scripts/tiller-swift-test`
- `swift build`

## Edge cases

- Zero actual progress equals zero expectation at creation and is on pace; it
  becomes behind only after time advances.
- At the exact expectation threshold equality remains on pace. The returned
  refresh marks when a later recomputation may change it and must not create a
  busy scheduling loop.
- Past due dominates complete progress because closure remains manual.
- An Accumulate value above one remains above one in the snapshot even though
  expected progress never exceeds one.
- No-deadline goals expose no fake zero expectation or deadline boundary.
- Time-zone changes may move the resolved deadline boundary; stored owner date
  and creation timestamp remain unchanged.
- The calculator performs no save, model mutation, timer creation, locale
  formatting, color selection, or automatic closure.
