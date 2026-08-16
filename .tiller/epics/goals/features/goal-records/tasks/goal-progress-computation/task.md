# Compute truthful goal progress

## Approach

Complete the records domain on
goals/goal-records/goal-progress-operations (T-s3qtlr). Begin with
`GoalProgressComputationTests`. Build one persistence-aware computation that
validates the aggregate and returns a type-safe, immutable, Equatable, Sendable
snapshot without saving or caching.

Define:

- `AccumulateGoalProgress`: total, target, unit, and uncapped normalized
  progress;
- `MeasureGoalProgress`: baseline, target, current value, optional effective
  reading identity, completed distance, total distance, unit, and clamped
  normalized progress;
- `GoalProgressSnapshot`: an enum carrying exactly one kind-specific result;
- typed errors for malformed kind/configuration, relationship, date, sequence,
  scalar, and arithmetic state.

`GoalProgressComputation` runs on the main actor over one caller-supplied
ModelContext so it can validate SwiftData identity and complete inverse
membership. An Accumulate goal must have only valid GoalEntries; sum every
positive amount with checked arithmetic. Divide total by positive target as a
finite normalized value and do not cap it at one.

A Measure goal must have only valid GoalReadings. Validate every GoalDate and
unique nonnegative sequence. Choose the effective reading by latest assigned
GoalDate and then highest sequence on that date; append timestamp is display
history, not effectiveness. With no readings, use baseline as current and
return zero progress with no effective identity.

Derive direction from target versus baseline. For an increasing goal, traveled
distance is current minus baseline; for a decreasing goal, baseline minus
current. Use checked integer arithmetic. Clamp wrong-direction movement to zero
and at-or-past-target movement to total distance, while returning the truthful
unclamped current value. Normalize the clamped completed distance over the
nonzero total distance.

Reject unknown kind, invalid target/baseline, cross-kind children, missing or
foreign inverses, duplicate sequences, malformed dates, nonpositive entry
amounts, and integer overflow. Never ignore a bad child, return a fabricated
zero, mutate a record, persist a total, infer standing, or auto-close.

## Surfaces

- Create `Sources/TendCore/Goals/GoalProgressComputation.swift`.
- Create
  `Tests/TendCoreTests/Goals/GoalProgressComputationTests.swift`.
- Reuse GoalDate, GoalKind, Goal, GoalEntry, and GoalReading without adding
  cached properties.
- Do not modify lifecycle state, app presentation, Today, reminders, habit
  computations, or Pencil comps.

## Tests

Bind feature criterion C4 to `GoalProgressComputationTests`.

For Accumulate, cover empty, one, many, exact-target, and over-target entries;
all eligible and old dates; total and normalized values; deterministic results
independent of relationship array order; and checked sum overflow.

For Measure, cover no readings; increasing and decreasing movement; wrong-way
movement; exact target; beyond target; negative baselines and readings;
multiple dates; multiple readings on one date; a Yesterday reading appended
after a Today reading; and equal append timestamps. Assert latest GoalDate then
highest sequence selects the effective reading while all history stays stored.

Reject target-zero/negative, missing or target-equal Measure baseline, unknown
kind, entries on Measure, readings on Accumulate, detached/foreign children,
missing inverses, malformed date keys, negative/duplicate sequence, nonpositive
entry amount, span overflow, traveled-distance overflow, and total overflow.
Assert no context mutation or save on every path.

Run:

- `Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalProgressComputationTests.swift`
- `Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalProgressOperationsTests.swift`
- `Scripts/tiller-swift-test Tests/TendCoreTests/Goals/GoalCreationOperationsTests.swift`
- `Scripts/tiller-swift-test`
- `swift build`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination
  'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## Edge cases

- Accumulate normalized progress may exceed one and remains finite for every
  representable checked total and positive target.
- Measure normalized progress is always zero through one, but current value is
  never clamped.
- The latest append is not necessarily the effective reading when it is
  assigned to an earlier GoalDate.
- Equal timestamps do not make effectiveness ambiguous because sequence records
  append order.
- Extreme baseline/current/target combinations fail typed checked arithmetic
  rather than trapping or approximating stored integer facts.
- Progress computation does not filter history by Today/Yesterday; operation
  eligibility limits mutation, not contribution to the complete arc.
