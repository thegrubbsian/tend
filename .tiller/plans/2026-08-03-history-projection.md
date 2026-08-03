# Habit Detail History Projection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic TendCore read boundary that returns streak, month-range, bucket-history, and editable-entry facts for one persisted habit.

**Architecture:** `HabitDetailComputation` is a main-actor SwiftData orchestration boundary. It validates the aggregate, asks existing reconciliation/streak/evaluation APIs for domain truth, and returns immutable `Equatable & Sendable` values; calendar and classification helpers remain private implementation details. The app receives no live persistence models or formatted strings.

**Tech Stack:** Swift 6, Foundation calendar APIs, SwiftData, Swift Testing, existing TendCore domain operations.

## Global Constraints

- Use the device-local Gregorian calendar semantics already implemented by `CalendarBucketSchedule`; never add fixed-second day arithmetic.
- Preserve existing SwiftData schema, reconciliation, streak, lifecycle, and logging semantics.
- Use persistent model identity for ownership; ordinary UUID collisions cannot cross aggregates.
- Final buckets expose frozen target/unit and verdict but no fabricated progress.
- Only current-open and grace entries are editable; bucket ownership, not entry timestamp, determines editability.
- Do not add app/UI sources, sample data, localization strings, or project metadata.
- Follow red-green-refactor: every production behavior begins with a focused failing test.

---

### Task 1: Public projection values and month contract

**Files:**
- Create: `Sources/TendCore/History/HabitDetailSnapshot.swift`
- Create: `Tests/TendCoreTests/History/HabitDetailComputationTests.swift`

**Interfaces:**
- Consumes: `HabitCadence`, `HabitStreakState`, `UUID`, and `Date`.
- Produces:

```swift
public struct HabitDetailMonthRange: Equatable, Sendable {
  public let earliest: Date
  public let selected: Date
  public let latest: Date
}

public enum HabitHistoryState: Equatable, Sendable {
  case met
  case missed
  case open
  case grace
  case inactive
  case beforeCreation
  case future
}

public struct HabitHistoryPeriod: Equatable, Sendable {
  public let key: String
  public let start: Date
  public let end: Date
  public let state: HabitHistoryState
  public let progress: Int?
  public let target: Int?
  public let unit: String?
  public let isRequirementMet: Bool?
}

public struct HabitEditableEntry: Equatable, Sendable {
  public let id: UUID
  public let timestamp: Date
  public let amount: Int
  public let bucketKey: String
  public let unit: String
  public let bucketStart: Date
  public let bucketEnd: Date
}

public struct HabitDetailSnapshot: Equatable, Sendable {
  public let habitID: UUID
  public let cadence: HabitCadence
  public let monthRange: HabitDetailMonthRange
  public let streak: HabitStreakState
  public let history: [HabitHistoryPeriod]
  public let editableEntries: [HabitEditableEntry]
}
```

- [ ] **Step 1: Write a compile-time contract test**

Construct every value explicitly and assert round-trip equality. The test names each property so accidental API drift fails compilation.

- [ ] **Step 2: Run the focused suite and verify red**

Run: `Scripts/tiller-swift-test Tests/TendCoreTests/History/HabitDetailComputationTests.swift`

Expected: compilation fails because the projection types do not exist.

- [ ] **Step 3: Add only the immutable public value types**

Use explicit public initializers and `let` properties. Add no view formatting or persistence references.

- [ ] **Step 4: Re-run and verify green**

Expected: the contract test passes; existing tests remain untouched.

---

### Task 2: Snapshot orchestration and calendar windows

**Files:**
- Create: `Sources/TendCore/History/HabitDetailComputation.swift`
- Modify: `Tests/TendCoreTests/History/HabitDetailComputationTests.swift`

**Interfaces:**
- Consumes: a persisted `Habit`, `ModelContext`, `Date`, `TimeZone`, `CalendarBucketSchedule`, and `HabitStreakComputation`.
- Produces:

```swift
@MainActor
public final class HabitDetailComputation {
  public init(context: ModelContext)

  public func snapshot(
    for habit: Habit,
    selectedMonth: Date,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> HabitDetailSnapshot
}
```

- [ ] **Step 1: Add failing daily window tests**

Cover a new daily habit at `2024-03-10T12:00:00-07:00` in `America/Los_Angeles`. Assert March is selected/latest, January is earliest, March contains 31 chronological daily periods, and the spring-forward period is 23 elapsed hours while still one bucket.

- [ ] **Step 2: Run focused tests and verify red**

Expected: `HabitDetailComputation` is missing.

- [ ] **Step 3: Implement context identity, local month normalization, clamping, and daily period generation**

Use a private Gregorian POSIX calendar configured with the injected time zone, plus `CalendarBucketSchedule` for every bucket boundary. Compute earliest as the earlier of the creation-bucket month and latest minus two calendar months.

- [ ] **Step 4: Run focused tests and verify green**

- [ ] **Step 5: Add failing weekly boundary tests**

Select March 2024 for a weekly habit and assert every Monday-through-Sunday bucket intersecting `[March 1, April 1)` appears, including the week beginning February 26 and the week beginning April 1 only when it actually intersects. Select February and prove the February 26 bucket shares the same period key across adjacent pages.

- [ ] **Step 6: Implement weekly intersecting-period generation**

Begin with the weekly bucket containing month start, append while `period.start < monthEnd`, and advance only with `CalendarBucketSchedule.next(after:)`.

- [ ] **Step 7: Add failing full-lifetime and rollover clamp tests**

Assert an older habit reaches its creation-bucket month, a new habit still exposes three pages, an earlier selected date clamps to earliest, and a later date clamps to latest.

- [ ] **Step 8: Implement clamping and verify all calendar tests green**

---

### Task 3: Persisted bucket classification and streak projection

**Files:**
- Modify: `Sources/TendCore/History/HabitDetailComputation.swift`
- Modify: `Tests/TendCoreTests/History/HabitDetailComputationTests.swift`

**Interfaces:**
- Consumes: `BucketEvaluator.evaluate(habit:bucket:at:timeZone:)` and `HabitStreakComputation.compute(habit:at:timeZone:)`.
- Produces: `HabitHistoryPeriod` facts whose state and requirement fields are mutually consistent.

- [ ] **Step 1: Add failing final/provisional classification tests**

Build the valid graph through `HabitManagementOperations` and `LogEntryOperations`. Advance injected time to assert final met/missed use frozen target/unit with `progress == nil`; open/grace retain progress/current requirement and report `isRequirementMet` below and at target.

- [ ] **Step 2: Run focused tests and verify red**

Expected: history periods still contain placeholder/synthesized states.

- [ ] **Step 3: Index persisted buckets by period key and classify with `BucketEvaluator`**

Map `.final + .met/.missed`, `.open`, `.grace`, and `.exempt` exactly. Treat `.dueForFinalization` and impossible phase/standing pairs as existing domain errors, never UI states.

- [ ] **Step 4: Re-run and verify green**

- [ ] **Step 5: Add failing streak tests**

Assert current, best, cadence, and risk exactly match `HabitStreakComputation`, including an unmet grace bucket preserving a nonzero chain.

- [ ] **Step 6: Delegate streak truth to `HabitStreakComputation` and verify green**

Use the internal save-injected initializer only in tests that need to observe best-streak persistence failure or no-op saves.

---

### Task 4: Activity gaps and structural integrity

**Files:**
- Modify: `Sources/TendCore/History/HabitDetailComputation.swift`
- Modify: `Tests/TendCoreTests/History/HabitDetailComputationTests.swift`

**Interfaces:**
- Produces focused errors:

```swift
public enum HabitDetailComputationError: Error, Equatable, Sendable {
  case invalidBucketRelationship(String)
  case invalidEntryRelationship(UUID)
  case duplicateEntryID(UUID)
  case missingActiveBucket(String)
  case nonAdvancingCalendarPeriod(String)
}
```

- [ ] **Step 1: Add failing creation/future/inactive tests**

Cover creation mid-day and mid-week, future periods while an activity interval is open, an exempt deactivation bucket, and a multi-period inactive gap between valid closed/open activity intervals.

- [ ] **Step 2: Run focused tests and verify red**

- [ ] **Step 3: Validate and sort activity intervals**

Reuse `HabitActivityOperationError` for missing/multiple/unexpected open intervals and invalid chronology. Check persistent ownership before interval math.

- [ ] **Step 4: Implement synthesized classification in fixed precedence**

Apply: persisted bucket → future → before creation bucket → missing-active-bucket error → inactive. Future classification runs before open-ended interval overlap.

- [ ] **Step 5: Add failing integrity tests**

Cover detached/foreign/deleted habit, UUID-colliding habits, duplicate bucket keys, missing elapsed active bucket, foreign/missing bucket relationships, unsupported cadence/verdict, partial finality, invalid target/entry amount, progress overflow, and backward/overlapping activity intervals.

- [ ] **Step 6: Add the smallest relationship/integrity validation and verify green**

Preserve `HabitStreakComputationError`, `BucketEvaluationError`, and `HabitActivityOperationError` where they already express the failure. Use `HabitDetailComputationError` only for detail-specific relationship and missing-period invariants.

---

### Task 5: Editable recent-entry projection

**Files:**
- Modify: `Sources/TendCore/History/HabitDetailComputation.swift`
- Modify: `Tests/TendCoreTests/History/HabitDetailComputationTests.swift`

**Interfaces:**
- Produces `HabitEditableEntry` values for entries in the current open bucket or any evaluated grace bucket.

- [ ] **Step 1: Add failing editability and ordering tests**

Create current and grace entries through `LogEntryOperations`; include identical timestamps with deterministic UUIDs. Assert newest timestamp first and UUID string ascending as tie-breaker. Assert bucket effective unit/boundaries and exact IDs.

- [ ] **Step 2: Run focused tests and verify red**

- [ ] **Step 3: Implement entry validation, editability, and sorting**

Fetch by persistent habit identity. Validate entry/habit/bucket ownership and unique entry IDs. Include `.open` only when its key equals the injected current-period key; include `.grace`; exclude final/exempt/future. Do not inspect entry timestamp for authorization.

- [ ] **Step 4: Add failing exclusion/error tests**

Cover inactive habit, final and exempt entries, a back-filled grace entry whose timestamp is current, duplicate IDs, foreign/missing relationships, and invalid/overflowing bucket progress.

- [ ] **Step 5: Complete minimal validation and verify green**

- [ ] **Step 6: Verify no-op and save-failure behavior**

Use an inactive valid graph to assert no context write, and the internal save seam to prove a best-streak save failure propagates without returning a partial snapshot.

---

### Task 6: Task verification and review handoff

**Files:**
- Review: `Sources/TendCore/History/HabitDetailSnapshot.swift`
- Review: `Sources/TendCore/History/HabitDetailComputation.swift`
- Review: `Tests/TendCoreTests/History/HabitDetailComputationTests.swift`

- [ ] **Step 1: Run targeted contract suite**

Run: `Scripts/tiller-swift-test Tests/TendCoreTests/History/HabitDetailComputationTests.swift`

Expected: all history projection tests pass with no warnings.

- [ ] **Step 2: Run full TendCore suite**

Run: `Scripts/tiller-swift-test`

Expected: all pre-existing and new tests pass.

- [ ] **Step 3: Run package build**

Run: `swift build`

Expected: build completes successfully.

- [ ] **Step 4: Format only changed Swift sources**

Run: `swift format --in-place Sources/TendCore/History/HabitDetailSnapshot.swift Sources/TendCore/History/HabitDetailComputation.swift Tests/TendCoreTests/History/HabitDetailComputationTests.swift`

- [ ] **Step 5: Review the diff against task scope**

Reject app/UI, schema, lifecycle, logging, and project-file changes. Confirm public values contain no localized strings or persistence models and every enum branch is intentional.

- [ ] **Step 6: Run the formatter-adjacent targeted suite again**

Run: `Scripts/tiller-swift-test Tests/TendCoreTests/History/HabitDetailComputationTests.swift`

Expected: all tests still pass.
