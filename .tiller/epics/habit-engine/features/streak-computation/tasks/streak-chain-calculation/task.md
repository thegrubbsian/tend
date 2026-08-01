# Calculate current and finalized streak chains

## Approach

Add the feature's immutable result and pure calculator under
`Sources/TendCore/Streaks`. Begin with focused Swift Testing cases, confirm they
fail because the types do not exist, then implement the smallest scan that
satisfies them.

Define public `HabitStreakState: Equatable, Sendable` with
`currentStreak: Int`, `bestStreak: Int`, `isAtRisk: Bool`, and
`cadence: HabitCadence`. Keep the calculator and its ordered input internal to
TendCore:

- `StreakBucketState` carries a period key, `BucketPhase`, and
  `BucketStanding`.
- `StreakCalculation` carries the public state plus the derived finalized-best
  candidate needed by the persistence task.
- `StreakCalculator.calculate(cadence:persistedBest:buckets:)` consumes
  oldest-to-newest states and performs no fetch, save, model mutation, calendar
  lookup, or wall-clock read.

Use one current-chain accumulator and one finalized-run accumulator. Final met
and pending-met states increment current; final missed resets current and the
at-risk candidate; pending-unmet states do not increment or reset; exempt
states are skipped. Only final met and final missed affect the finalized run and
its maximum. A pending-unmet grace state after the latest final miss marks the
surviving nonzero current chain at risk; pending-unmet open state does not.
Return `max(persistedBest, derivedFinalizedBest)` as the displayed best while
retaining the candidate separately for the integration task.

Define the complete public `HabitStreakComputationError` surface here so the
dependent persistence task does not attempt to add enum cases later:
`detachedHabit`, `duplicatePeriodKey(String)`, `invalidBestStreak(Int)`, and
`unexpectedBucketState(key:phase:standing:)`. This calculator emits the latter
two; the persistence task emits the first two. Refuse `.dueForFinalization`
through `unexpectedBucketState` because the persistence operation must reconcile
before calculation. Validate every state before producing a result so malformed
input cannot yield a plausible streak.

## Surfaces

- Create `Sources/TendCore/Streaks/StreakCalculator.swift` for
  `HabitStreakState`, calculator input/output values, errors, and pure chain
  arithmetic.
- Create `Tests/TendCoreTests/Streaks/StreakCalculatorTests.swift` for
  calculator behavior.
- Do not modify SwiftData models, bucket scheduling/evaluation, reconciliation,
  lifecycle operations, logging operations, or package dependencies.

This task produces the exact calculator contract consumed by
habit-engine/streak-computation/streak-persistence-integration (T-ipovyn).

## Tests

Use `@testable import TendCore` and table-driven inputs where the table makes
the bucket sequence easier to read. Each test asserts observable result values,
not loop structure.

- Prove empty history returns current zero, a nonnegative persisted best, no
  risk, and the supplied daily or weekly cadence.
- Prove consecutive final met and pending-met buckets count, a final missed
  bucket hard-resets, and partial progress represented as pending-unmet never
  earns a link.
- Prove an unmet grace bucket preserves but does not increment the chain: twelve
  final met states, unmet grace, and pending-met current state yield thirteen
  and at risk.
- Prove an unmet open bucket is not at risk, a grace bucket before the latest
  final miss cannot mark the new chain at risk, and zero current streak is never
  at risk.
- Prove exempt states can occur between met states without incrementing or
  breaking the chain.
- Prove finalized runs establish the derived best, pending-met records do not,
  final misses divide historical runs, and a larger persisted best is never
  lowered.
- Prove negative persisted best, due-for-finalization input, and every
  impossible phase/standing pair return their precise typed error.

Run the focused test file with
`Scripts/tiller-swift-test Tests/TendCoreTests/Streaks/StreakCalculatorTests.swift`
and finish with a task-sized commit containing only this calculator and its
tests.

## Edge cases

- Open and grace `.pendingUnmet` are savable but unearned; neither counts and
  only grace can create risk.
- Open and grace `.pendingMet` count toward current but never toward finalized
  best.
- Exempt is valid only with exempt standing. Final is valid only with met or
  missed standing. Provisional phases are valid only with pending standings.
- The period key exists for deterministic error evidence; chain order is
  supplied by the caller and must not be re-sorted by the calculator.
- The chain count cannot exceed the number of supplied states; do not add
  speculative numeric machinery or a second representation.
