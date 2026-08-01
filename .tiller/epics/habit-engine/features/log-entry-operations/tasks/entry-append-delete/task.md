# Append and delete editable log entries

Build the persistence-aware mutation boundary that records contributions in
current and grace buckets and corrects mistakes by deletion.

## Approach

- Add `LogEntryDestination` with `.current` and `.periodKey(String)` selections,
  plus a typed `LogEntryOperationError` for inactive habits, invalid scalar
  input, missing or foreign relationships, unavailable destinations, and
  non-editable phases. Preserve dependency errors rather than flattening them
  into a generic logging failure.
- Add a main-actor `LogEntryOperations` over one `ModelContext`,
  `BucketReconciler`, `BucketEvaluator`, and `CalendarBucketSchedule`. Public
  append and delete operations accept one habit, an explicit instant, and an
  explicit time zone. Append also accepts a positive amount and destination;
  delete accepts the exact persisted entry to remove.
- Reject nonpositive amounts, inactive habits, detached models, and obvious
  cross-aggregate relationships before reconciliation. Compare SwiftData
  persistent identity, never the models' ordinary UUID attributes.
- Reconcile before bucket authorization. Resolve `.current` from the canonical
  period containing the instant; resolve an explicit key only within the same
  habit. Evaluate the persisted destination after reconciliation. Authorize an
  open result only when its key is the current key, or authorize a grace result;
  reject future-open, due, final, exempt, missing, malformed, and older keys.
- Before append, require checked existing progress and prove adding the amount
  cannot overflow. Insert exactly one `LogEntry` with the operation instant and
  both inverse relationships. Allow progress above target.
- Before delete, require that the entry's habit and bucket relationships are
  present, mutually consistent, persisted in the supplied context, and still
  editable after reconciliation. Delete exactly that entry; do not add an
  update API or rewrite any remaining record.
- Plan and validate the complete entry mutation before applying it, then save
  once. On application or save failure, undo inserted/deleted entry state and
  inverse relationship changes, roll back the context, and rethrow. Treat any
  earlier reconciliation save as an independently valid prerequisite, not part
  of the entry rollback.
- Keep SwiftData access in this operation surface. Do not add a repository,
  command bus, cached progress field, uniqueness constraint, clock abstraction,
  or UI-facing quick-add/Undo state.

## Surfaces

- `Sources/TendCore/Logging/LogEntryOperations.swift`
- `Tests/TendCoreTests/Logging/LogEntryOperationsTests.swift`

## Tests

- Bind feature criteria C1, C2, and C3 to
  `LogEntryOperationsTests.swift`.
- Use isolated in-memory model containers and explicit daily and weekly
  fixtures, operation instants, and time zones. Use real reconciliation and
  evaluation; inject only the mutation save failure needed to prove rollback.
- Prove default current append, explicit daily grace back-fill, weekly current
  and Monday grace append, operation-time timestamps outside the selected
  bucket, exact habit/bucket relationships, checked progress, above-target
  contributions, and repeated appends as distinct entries.
- Prove deletion of one or the last editable entry, relationship cleanup, and
  the resulting pending-met or pending-unmet evaluation without stored
  aggregates.
- Prove inactive, final, exempt, older-than-grace, future, missing, malformed,
  cadence-mismatched, detached, cross-habit, and internally inconsistent
  records fail without an entry mutation. Include two habits with the same UUID
  to establish persistent relationship identity.
- Prove exact period and grace boundaries, deterministic validation precedence,
  nonpositive amounts, checked-sum overflow, append and delete save failures,
  one mutation save on success, and no mutation save on refusal. Also prove
  valid catch-up/finality from the prerequisite reconciliation survives a later
  entry refusal or rollback.

## Edge cases

- A back-filled entry keeps the operation instant; timestamps do not select or
  rewrite bucket identity.
- An evaluator result of `open` is insufficient by itself because a future
  bucket is also before its end. Its canonical key must equal the current key.
- At the grace boundary, reconciliation finalizes the bucket before
  authorization, so append and delete both fail against fossilized history.
- Deleting the last entry is valid. Appending beyond target is valid. Neither
  operation clamps progress or stores a provisional verdict.
- Existing corrupt amounts, duplicate keys, activity-period errors, calendar
  errors, and finality inconsistencies propagate without guessed repair.
- Repeating append is intentionally not idempotent. Undo semantics are supplied
  later by retaining the returned entry and calling delete.
