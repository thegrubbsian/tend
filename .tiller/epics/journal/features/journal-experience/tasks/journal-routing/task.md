# Build identity-safe Journal routing

## Approach

Rename the reminder-specific `ReminderRoutingModel` to the shell-level
`ShellRoutingModel` in one clean cutover, preserving notification deep-link
behavior while giving all root destinations one owner. Replace direct selection
assignment with a request API that can await one active navigation guard before
committing a root change. The Journal editor registers that guard only while it
has unsaved or pending text; failed flushes cancel the requested route.

Add an ephemeral Journal route with overview, compose(`LocalDate`), and
entry(UUID) states. A route request selects Journal and records stable scalar
identity; it never retains a SwiftData model object or persists across process
launch.

Resolve entry identity through `JournalEntryQuery` when the Journal destination
renders. Missing or deleted identities collapse to overview with a truthful
load result. Repeated identical requests are inert. Changing to another root
destination preserves the in-process Journal route, while cold launch starts
with Today and Journal overview.

Do not add the visible fourth tab in this task; establish the tested routing
contract consumed by the final destination task.

## Surfaces

- `App/Tend/Application/ReminderRoutingModel.swift`, renamed to
  `ShellRoutingModel.swift`
- `App/Tend/TendApp.swift` and `App/Tend/TendRootView.swift`
- Reminder runtime, coordinator, and notification delegate routing callers
- `App/Tend/Journal/JournalRoute.swift`
- `App/TendTests/JournalRoutingModelTests.swift`
- Existing reminder routing tests

## Tests

Write failing tests for overview, dated compose, stable entry identity,
idempotent requests, successful and failed guarded destination switching,
missing/deleted entry recovery, notification deep links, background
preservation, and cold-start reset. Rename existing reminder-routing test
vocabulary without changing its contracts.

## Edge cases

Never retain a deleted or foreign `JournalEntry` instance in routing state.
Two entries cannot share a day, but route resolution must report that persisted
invariant failure rather than choose one. A reminder notification arriving
while Journal is selected must still route to the requested Habit without
leaving stale Journal focus behind.
