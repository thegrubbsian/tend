# Close and reopen goals deliberately

## Approach

Complete the lifecycle boundary on
goals/goal-lifecycle/goal-management-operations (T-4gpnsw). Add a main-actor
`GoalLifecycleOperations` service over one caller-supplied `ModelContext`, with
the same persistent-identity checks, production initializer, injectable save
seam, precise rollback, and typed-error conventions established by goal
management.

`close(_:as:)` accepts a nonoptional `GoalClosure` so a caller must choose
Harvested or Let go. Require an owned open Goal, set only that disposition, and
save once. Do not inspect standing or require any progress threshold: on-pace,
behind, past-due, below-target, exact-target, and over-target goals all close by
the same deliberate operation.

`reopen(_:)` requires an owned harvested or let-go Goal, clears only closure,
and saves once. Preserve kind, all editable fields, creation time, deadline, and
every progress child. Do not compute or store the reopened standing; callers
recompute it for their current instant.

Extend the existing append and delete-item operations from goals/goal-records
(F-e149jw) with one lifecycle precondition: the owned Goal must be open. A
closed goal fails before child mutation or save. Reopening restores the same
Today-or-Yesterday operation eligibility already owned by the prerequisite.
Reuse those operations rather than adding lifecycle-specific append/delete
entry points.

Repeated close, repeated reopen, malformed closure, detached, deleted, and
foreign-context goals fail with typed errors and zero lifecycle saves. A close
or reopen save failure restores only the prior closure value and leaves
unrelated pending work intact. No progress append, edit, standing computation,
target attainment, or deadline passage may call close automatically.

## Surfaces

- Create `Sources/TendCore/Goals/GoalLifecycleOperations.swift`.
- Create
  `Tests/TendCoreTests/Goals/GoalLifecycleOperationsTests.swift`.
- Modify the progress append/delete operation file created by
  goals/goal-records (F-e149jw) to reject closed goals.
- Extend the prerequisite's focused progress-operation tests for the new closed
  guard where that behavior is best established.
- Do not modify schema, standing arithmetic, management update/delete, app UI,
  Today, reminders, habits, or Pencil comps.

## Tests

Bind feature criterion C4 to `GoalLifecycleOperationsTests`.

Close open goals as Harvested and Let go across both kinds, every standing, and
zero, partial, exact, and over-target progress. Assert only closure changes,
exactly one save occurs, all fields and progress identities remain stable, and
fresh standing computation returns no open snapshot.

Reopen both dispositions and assert closure alone clears, one save occurs,
progress and configuration remain byte-for-byte equivalent, and fresh standing
can resolve on pace, behind, or past due from the explicit current instant.

Attempt progress append and eligible item deletion while closed. Assert the
typed closed-goal failure, no child or inverse change, and zero progress saves;
then reopen and prove the same valid operations succeed under their original
Today-or-Yesterday rules.

Reject repeated close, repeated reopen, unknown closure, detached/deleted goal,
and foreign-context goal. Inject close and reopen save failures and assert the
prior open or closed value returns, no unrelated pending context change is
lost, and no progress or configuration fact moves.

Prove target attainment, over-achievement, past-due standing, progress append,
standing computation, and management update never mutate closure without an
explicit lifecycle call.

Run:

- `Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalLifecycleOperationsTests.swift`
- `Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalManagementOperationsTests.swift`
- `Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalStandingComputationTests.swift`
- the focused progress-operation tests created by goals/goal-records
  (F-e149jw)
- `Scripts/tiller-swift-test`
- `swift build`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination
  'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## Edge cases

- Harvested is an owner judgment, not a computed synonym for target met.
- Let go is not a failure verdict and does not erase progress.
- A complete or over-complete open goal becomes past due after its deadline and
  still requires explicit closure.
- Editing a closed goal remains legal; appending or deleting progress does not.
- Reopening a past-due goal immediately exposes past due when recomputed; it
  does not extend the deadline.
- Closure transitions do not add timestamps or create separate lifecycle
  records.
- A close requested while unrelated context changes are pending saves through
  the caller's context exactly once; rollback after failure restores only the
  lifecycle mutation.
