# Build Today Presentation Model

## Approach

Add a main-actor observable presentation model between SwiftData/TendCore and
the SwiftUI dashboard. The model consumes persisted habits plus one explicit
`TodayRefreshContext` containing instant, time zone, calendar, and locale. Its
live operations adapter calls `HabitTodayComputation`; tests inject the same
small operation signature without a store or view.

Represent the published result as one complete Today presentation:

- first launch when there are no persisted habits;
- inactive-only when persisted habits exist but none are active;
- dashboard with TO TEND rows, TENDED rows, met count, and active count.

Filter active habits once, project every active persistent identifier exactly
once, and construct all replacement rows before assigning published state.
Successful rows carry one coherent snapshot. Failed rows retain the live habit,
stable identifier, exact name and stored requirement, unavailable progress and
streak state, a concise mapped message, and retry metadata.

Use `PersistentIdentifier` for row identity and retry lookup. Localized,
case-insensitive name ordering is followed by creation time and stable
identifier tie-breakers. Failed and unmet rows are TO TEND; met rows are TENDED.
The met fraction counts only successful met rows over every active row, and any
failure blocks `All tended.`

Add a small presentation formatter for locale-aware integers, built-in
`time`/`times` inflection, day/week streak units, daily/weekly risk copy, and
combined accessibility facts. Preserve all other owner-written units and names
verbatim. Clamp only the visual fraction to zero through one; never clamp the
displayed aggregate.

Retry exactly the failed persistent identity using a newly supplied refresh
context. Publish the replacement only after a complete successful projection.
If the habit disappeared, became inactive, or no longer matches the last input,
perform a complete refresh rather than retargeting by index, name, order, or
ordinary UUID.

The model does not own a timer, navigation, logging action, haptic, or sheet.

## Surfaces

- Create `App/Tend/Today/TodayModel.swift` for refresh context, injected
  operations, row/presentation values, live adapter, refresh, and retry.
- Create `App/Tend/Today/TodayPresentationFormatter.swift` for owner-visible and
  accessibility copy.
- Create `App/TendTests/TodayModelTests.swift`.
- Consume the public `HabitTodayComputation` contract from
  app-experience/today-dashboard/current-bucket-projection.
- Do not edit `TodayDestinationChrome`, the shell model, or SwiftUI cards in
  this task.

## Tests

Run:

```bash
Scripts/tiller-xcode-test TendTests/TodayModelTests
Scripts/tiller-xcode-test TendTests
swift build
```

The focused suite must prove:

- zero persisted habits and inactive-only stores produce distinct states;
- every active habit appears exactly once and inactive habits never appear;
- duplicate ordinary UUIDs do not collide;
- one sampled instant, time zone, calendar, and locale reach every operation;
- successful snapshots format exact progress, target, unit, cadence streak,
  risk, met state, visual fraction, and accessibility text;
- only built-in `times` inflects to `time` at a target of one;
- TO TEND and TENDED partition the active set exactly and use documented
  localized ordering and tie-breakers;
- met/active fractions include failures only in the denominator;
- all-tended appears only for a nonempty, fully successful met set;
- one thrown operation leaves a visible unavailable row while valid siblings
  remain complete;
- refresh publishes no mixed-generation intermediate result;
- retry is persistent-identity scoped, replaces one row atomically on success,
  retains the error on repeated failure, and triggers full refresh when the
  identity is no longer eligible;
- large values, long names, empty imported names, invalid stored requirements,
  and stable error messages do not crash formatting.

## Edge cases

- Progress above target displays the complete aggregate while its visual
  fraction is one.
- A zero progress/positive target fraction is zero; invalid targets remain
  unavailable rather than dividing by zero.
- Daily risk says `Yesterday open`; weekly risk says `Last week open`.
- Locale changes can reorder rows and reformat numbers, so the complete
  presentation is rebuilt from one context.
- A failed row never counts as met even if an older successful snapshot did.
- Repeated refreshes with identical facts remain safe and deterministic.
