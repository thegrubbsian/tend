# Project today's Journal invitation state

## Approach

Extend the existing atomic Today generation with Journal entry inputs rather
than adding another observable model, task, timer, or scheduler. Fingerprint the
queried Journal graph beside Habit and Goal inputs, derive the current
`LocalDate` from the same explicit refresh context, and use
`JournalEntryQuery` to project one of three states: invitation, complete
(omitted), or unavailable with a retry action.

Keep the Journal result independent from Habit sections, Goal rows, `All
tended`, logging state, and Goal transition scheduling. Feed query mutations,
scene activation, environment changes, local-day schedule entries, and retry
through the one established Today refresh entry. An entry create/delete must
change the graph fingerprint and refresh exactly once.

## Surfaces

- `App/Tend/Today/TodayModel.swift` generation, fingerprints, and refresh result
- A focused Journal projection type beside the existing Today helpers when that
  keeps `TodayModel` from growing another responsibility
- `App/Tend/Today/TodayLoggingModel.swift` only where the shared refresh
  signature must carry Journal inputs
- `App/TendTests/TodayJournalInvitationModelTests.swift`
- `App/TendTests/TodayJournalRefreshTests.swift`

## Tests

Write failing tests for absent/present today's entry, yesterday-only and old
entries, empty bodies, create/delete fingerprint changes, local midnight, scene
and time-zone refresh, isolated malformed/duplicate Journal data, retry, and
stable repeated generation. Assert Habit and Goal row identities, ordering,
fractions, standing, failures, next transitions, and `All tended` are identical
with the Journal input removed.

## Edge cases

Do not use body emptiness as eligibility; durable entry existence is the only
condition. A failed Journal query must not suppress valid Habit or Goal output.
Current-time refreshes must not reuse a stale timeline instant on resume.
Deduplicate SwiftData query identities before fingerprinting so a repeated
object cannot create a refresh loop, while still surfacing a persisted
duplicate-day invariant failure.
