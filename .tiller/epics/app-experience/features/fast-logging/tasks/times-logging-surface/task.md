# Wire One-tap Count Logging

## Approach

Turn the established Today ring/check into a real button for rows whose exact
stored unit is `times`. Wire the control to `TodayLoggingModel` with the live
habit, current persisted identity, all current query habits, and one freshly
captured operation context. Production captures `.now` at activation; DEBUG
fixed-instant launches keep their injected instant.

Preserve the existing 52-point unmet and 44-point compact-complete geometry.
Add the centered plus glyph to empty and in-progress rings, retain the clockwise
moss arc and solid completion check, and ensure the hit region is at least 44 by
44 points. The visible card body is not a hidden tap target. Completed checks
remain buttons and append one additional real instance.

Make the at-risk line a separate control. On exact-`times` rows it appends one to
the explicit grace period key with no sheet or confirmation. On quantity rows
this task only exposes the callback seam consumed by the log-sheet task; do not
implement a second quantity interaction.

After a successful append, render the complete refreshed dashboard: exact
progress, fraction, section membership, streak/risk, and ring agree. Show
`Logged N unit · Undo` from logging-model state for five seconds, including a
second line under a compact TENDED row. Undo is a clay-deep text button targeting
the exact entry. Show model errors inline without fabricating progress or moving
the row.

Consume value-semantic feedback events once. Trigger light impact for an
ordinary/already-met append, success notification only for unmet-to-met, and
lighter selection feedback for successful Undo. Do not trigger on body refresh
or reappearance. Animate progress and completion with the Almanac liquid fill and
restrained 450 ms bloom; Reduce Motion uses cross-fades.

Rebuild available-card accessibility so visible facts are not announced once as
a static card and again as a control. The ring button announces habit, exact
progress/target/unit, streak, met state, and risk, with hint `Logs one instance`.
The risk control names Yesterday or Last Week and its stakes. Undo names the
habit and exact amount. Decorative glyphs/arcs/checks remain hidden. Unavailable
rows retain their existing summary and retry semantics.

Replace only the obsolete Today Dashboard tests that assert an available ring
has no button or write. Keep their unrelated ordering, projection, lifecycle,
relaunch, adaptation, and failure-isolation assertions unchanged.

## Surfaces

- Modify `App/Tend/Today/TodayView.swift` for ring buttons, risk action, inline
  Undo/error, feedback consumption, motion, and accessibility.
- Create `App/Tend/Today/TodayLogRing.swift` if extracting the interactive ring
  keeps `TodayView` focused; otherwise replace the existing private ring in
  place.
- Modify `App/Tend/Shell/TodayDestinationChrome.swift` only to inject a fresh
  production/fixed operation context and shared logging model.
- Create or extend `App/TendUITests/FastLoggingUITests.swift` with the exact
  `testTimesLoggingJourneys` method.
- Modify `App/TendUITests/TodayDashboardUITests.swift` only where the prior
  noninteractive-ring contract is superseded.
- Do not build the quantity sheet, change dashboard projection semantics, edit
  TendCore mutations/schema, alter shell destinations, or touch Habit Detail.

## Tests

Run:

```bash
Scripts/tiller-xcode-test TendUITests/FastLoggingUITests/testTimesLoggingJourneys
Scripts/tiller-xcode-test TendUITests/TodayDashboardUITests
Scripts/tiller-xcode-test TendTests/TodayLoggingModelTests
Scripts/tiller-xcode-test TendTests/TodayModelTests
swift build
```

Use independent named stores to prove:

- a target-one current ring appends one, moves the row to TENDED, updates the
  fraction, exposes Undo after regrouping, and Undo restores the exact prior
  state;
- a multi-count current ring appends one per activation, remains unresolved
  until target, completes on the last required activation, and supports a real
  over-target append from the completed check;
- the `times` at-risk line appends to Yesterday/Last Week by explicit period,
  leaves an under-target grace line reachable, clears risk only when genuinely
  met, and fails nonmutating after expiry;
- each activation creates a distinct persisted entry and same-store relaunch
  keeps committed progress but no transient Undo;
- a later log replaces the earlier Undo affordance without deleting either
  entry, and five-second expiry removes only the button;
- failed append and failed Undo retain truthful facts and expose one inline
  error with no completion feedback;
- exact `time` and owner quantity units do not append on ring activation;
- completed and incomplete ring controls have stable identifiers, button traits,
  44-point geometry, exact labels/values/hints, while visual facts and decorative
  shapes do not duplicate;
- Reduce Motion preserves every state transition without the scale bloom.

## Edge cases

- A card can move vertically between TO TEND and TENDED while the tapped control
  disappears; UI tests wait by persistent semantic identifier, never old frame.
- Very rapid repeated activation may enqueue distinct main-actor writes, but no
  tap can overwrite or combine another entry.
- A query removal, archive, or local-boundary rollover during activation clears
  stale sheet/Undo identity and never retargets another row.
- Over-target completed rows remain visually compact while their accessibility
  value and transient Undo report truthful progress.
