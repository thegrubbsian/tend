# Set bucket totals by appending deltas

Add cadence-neutral set-total sugar on top of the authorized entry mutation
surface without introducing a second aggregate model.

## Approach

- Extend `LogEntryOperations` with a set-total operation that accepts one habit,
  a nonnegative total, a `LogEntryDestination`, an explicit instant, and an
  explicit time zone. Return the created delta entry, or `nil` for an equal
  no-op.
- Reuse the append/delete task's scalar ownership checks, reconciliation,
  destination resolution, evaluator result, and current-or-grace authorization.
  Do not call the public append operation recursively or reconcile twice.
- Read the selected bucket's checked persisted progress. If the requested total
  is greater, compute the positive difference without overflow and apply the
  same one-entry insertion plan as append. If equal, return `nil` without an
  entry mutation or mutation save. If lower, return a typed error that carries
  the current and requested totals; callers correct the history by deleting
  entries.
- Keep the calculation bucket-grained. A daily destination means that day's
  sum; a weekly destination means that Monday-Sunday bucket's sum. Never group
  weekly entries by their timestamps or create daily buckets under a weekly
  habit.
- Preserve the existing one-save and rollback rules for a positive delta.
  Reconciliation remains an independently committed prerequisite. Do not add a
  persisted total, replace existing entries, or special-case units such as
  `steps`; the operation is valid for every integer-valued habit.

## Surfaces

- `Sources/TendCore/Logging/LogEntryOperations.swift`
- `Tests/TendCoreTests/Logging/BucketTotalOperationsTests.swift`

## Tests

- Bind feature criterion C4 to `BucketTotalOperationsTests.swift`.
- Use isolated in-memory containers, explicit time zones and instants, real
  reconciliation/evaluation, and persisted entry collections with zero, one,
  and multiple contributions.
- Prove a greater daily total appends exactly one positive difference with the
  operation timestamp and correct relationships, including a total above the
  target and a daily grace back-fill.
- Prove current-week and Monday last-week totals use the whole selected weekly
  bucket. Assert that no daily bucket or per-day subtotal is created or used.
- Prove equal totals, including zero for an empty bucket, return `nil`, preserve
  every entry, and perform no mutation save. Prove lower and negative totals
  are distinct typed failures with no mutation.
- Prove invalid existing amounts or overflow propagate, destination
  authorization matches append, a positive-delta save failure rolls back the
  entry and inverse relationships, and each successful delta performs one
  mutation save.

## Edge cases

- `Int.max` is a valid requested total only when the existing checked sum lets
  the positive difference be represented and persisted without aggregate
  overflow.
- A requested zero against nonzero progress is lower, not a reset command.
- An equal total after reconciliation is still a no-op even if reconciliation
  itself legitimately saved catch-up or finality facts.
- Timestamps never partition a weekly total. Thursday and Sunday entries in the
  same weekly bucket contribute to one sum, and last week is editable only
  during Monday grace.
