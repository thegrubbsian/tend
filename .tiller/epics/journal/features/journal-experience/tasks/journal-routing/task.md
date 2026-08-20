# Build identity-safe Journal routing

## Approach

Rename the reminder-specific `ReminderRoutingModel` to the shell-level
`ShellRoutingModel` in one clean cutover, preserving notification deep-link
behavior while giving all root destinations one owner. Replace direct selection
assignment with a request API that can await one active navigation guard before
committing a root change. The Journal editor registers that guard only while it
has unsaved or pending text; failed flushes cancel the requested route.

Add an ephemeral Journal route with overview, compose(`LocalDate`), and
entry(UUID) states. Journal route preparation records stable scalar identity;
it never retains a SwiftData model object or persists across process launch.
Resolve entry identity through `JournalEntryQuery`; missing identities collapse
to overview while query corruption remains a truthful failure. Repeated
identical route preparation is inert, and current root-destination changes
preserve the in-process Journal route.

Do not add `.journal`, a visible fourth tab, a placeholder screen, or actual
Journal selection in this task. The final destination task adds the real root
case and view, then combines root selection with the prepared Journal route.
Until then, cold launch remains Today with Journal overview prepared.

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
Duplicate or malformed persisted entries remain truthful query failures rather
than choosing a route target. Reminder navigation through the guarded request
API must retain its strict ownership checks, and changing among the current
Today, Goals, and Habits roots must not clear a prepared Journal route.
