import Foundation
import Testing

@testable import TendCore

@Suite("Bucket evaluator")
struct BucketEvaluatorTests {
  @Test("daily boundaries enter grace and finality exactly")
  func dailyBoundariesEnterGraceAndFinalityExactly() throws {
    let habit = Habit(name: "Read", cadence: .daily, target: 4, unit: "pages")
    let bucket = makeBucket(
      key: "day:2024-01-01",
      cadence: .daily,
      habit: habit
    )
    setEntries([2, 2], on: bucket, habit: habit)

    let open = try evaluate(
      habit: habit,
      bucket: bucket,
      at: "2024-01-01T23:59:59Z"
    )
    #expect(open.phase == .open)
    #expect(open.standing == .pendingMet)
    #expect(open.progress == 4)
    #expect(open.period?.end == (try instant("2024-01-02T00:00:00Z")))
    #expect(open.finalization == nil)

    let grace = try evaluate(
      habit: habit,
      bucket: bucket,
      at: "2024-01-02T00:00:00Z"
    )
    #expect(grace.phase == .grace)
    #expect(grace.standing == .pendingMet)
    #expect(grace.finalization == nil)

    let due = try evaluate(
      habit: habit,
      bucket: bucket,
      at: "2024-01-03T00:00:00Z"
    )
    #expect(due.phase == .dueForFinalization)
    #expect(due.standing == .met)
    #expect(due.finalization?.targetSnapshot == 4)
    #expect(due.finalization?.unitSnapshot == "pages")
    #expect(due.finalization?.verdict == .met)
    #expect(due.finalization?.finalizedAt == (try instant("2024-01-03T00:00:00Z")))
  }

  @Test("weekly boundaries enter grace and finality exactly")
  func weeklyBoundariesEnterGraceAndFinalityExactly() throws {
    let habit = Habit(name: "Practice", cadence: .weekly, target: 3, unit: "times")
    let bucket = makeBucket(
      key: "week:2024-01-01",
      cadence: .weekly,
      habit: habit
    )
    setEntries([2], on: bucket, habit: habit)

    let grace = try evaluate(
      habit: habit,
      bucket: bucket,
      at: "2024-01-08T00:00:00Z"
    )
    #expect(grace.phase == .grace)
    #expect(grace.standing == .pendingUnmet)
    #expect(grace.period?.end == (try instant("2024-01-08T00:00:00Z")))
    #expect(grace.period?.graceEnd == (try instant("2024-01-09T00:00:00Z")))

    let due = try evaluate(
      habit: habit,
      bucket: bucket,
      at: "2024-01-09T00:00:00Z"
    )
    #expect(due.phase == .dueForFinalization)
    #expect(due.standing == .missed)
    #expect(due.finalization?.verdict == .missed)
    #expect(due.finalization?.finalizedAt == (try instant("2024-01-09T00:00:00Z")))
  }

  @Test("checked progress distinguishes below equal and above target sums")
  func checkedProgressDistinguishesBelowEqualAndAboveTargetSums() throws {
    let habit = Habit(name: "Water", cadence: .daily, target: 4, unit: "glasses")
    let bucket = makeBucket(
      key: "day:2024-01-01",
      cadence: .daily,
      habit: habit
    )

    setEntries([1, 2], on: bucket, habit: habit)
    let below = try evaluate(
      habit: habit,
      bucket: bucket,
      at: "2024-01-01T12:00:00Z"
    )
    #expect(below.progress == 3)
    #expect(below.standing == .pendingUnmet)

    setEntries([1, 3], on: bucket, habit: habit)
    let equal = try evaluate(
      habit: habit,
      bucket: bucket,
      at: "2024-01-01T12:00:00Z"
    )
    #expect(equal.progress == 4)
    #expect(equal.standing == .pendingMet)

    setEntries([2, 3], on: bucket, habit: habit)
    let above = try evaluate(
      habit: habit,
      bucket: bucket,
      at: "2024-01-01T12:00:00Z"
    )
    #expect(above.progress == 5)
    #expect(above.standing == .pendingMet)
  }

  @Test("open and grace buckets use the current requirement")
  func openAndGraceBucketsUseTheCurrentRequirement() throws {
    let habit = Habit(name: "Move", cadence: .daily, target: 5, unit: "minutes")
    let bucket = makeBucket(
      key: "day:2024-01-01",
      cadence: .daily,
      habit: habit
    )
    setEntries([4], on: bucket, habit: habit)

    let open = try evaluate(
      habit: habit,
      bucket: bucket,
      at: "2024-01-01T12:00:00Z"
    )
    #expect(open.target == 5)
    #expect(open.unit == "minutes")
    #expect(open.standing == .pendingUnmet)

    habit.target = 4
    habit.unit = "sets"
    let grace = try evaluate(
      habit: habit,
      bucket: bucket,
      at: "2024-01-02T12:00:00Z"
    )
    #expect(grace.target == 4)
    #expect(grace.unit == "sets")
    #expect(grace.standing == .pendingMet)
  }

  @Test("settled buckets use only frozen facts")
  func settledBucketsUseOnlyFrozenFacts() throws {
    let habit = Habit(name: "Write", cadence: .daily, target: 99, unit: "new")
    let finalizedAt = try instant("2024-01-03T00:00:00Z")
    let bucket = makeBucket(
      key: "day:2024-01-01",
      cadence: .daily,
      finalizedAt: finalizedAt,
      verdict: .missed,
      targetSnapshot: 3,
      unitSnapshot: "pages",
      habit: habit
    )
    setEntries([99], on: bucket, habit: habit)

    let first = try evaluate(
      habit: habit,
      bucket: bucket,
      at: "2030-06-01T12:00:00Z",
      timeZoneIdentifier: "America/Los_Angeles"
    )
    habit.target = 1
    habit.unit = "changed"
    setEntries([1], on: bucket, habit: habit)
    let second = try evaluate(
      habit: habit,
      bucket: bucket,
      at: "2000-01-01T00:00:00Z",
      timeZoneIdentifier: "Asia/Tokyo"
    )

    #expect(first == second)
    #expect(first.phase == .final)
    #expect(first.standing == .missed)
    #expect(first.progress == nil)
    #expect(first.target == 3)
    #expect(first.unit == "pages")
    #expect(first.period == nil)
    #expect(first.finalization?.finalizedAt == finalizedAt)
    #expect(first.finalization?.verdict == .missed)
  }

  @Test("exempt buckets report progress without becoming finalization candidates")
  func exemptBucketsReportProgressWithoutBecomingFinalizationCandidates() throws {
    let habit = Habit(name: "Rest", cadence: .daily, target: 3, unit: "times")
    let bucket = makeBucket(
      key: "day:2024-01-01",
      cadence: .daily,
      isExempt: true,
      habit: habit
    )
    setEntries([2], on: bucket, habit: habit)

    let evaluation = try evaluate(
      habit: habit,
      bucket: bucket,
      at: "2024-02-01T00:00:00Z"
    )
    #expect(evaluation.phase == .exempt)
    #expect(evaluation.standing == .exempt)
    #expect(evaluation.progress == 2)
    #expect(evaluation.target == 3)
    #expect(evaluation.finalization == nil)
  }

  @Test("non-final buckets reject invalid requirements entries and overflow")
  func nonFinalBucketsRejectInvalidRequirementsEntriesAndOverflow() throws {
    let habit = Habit(name: "Count", cadence: .daily, target: 1)
    let bucket = makeBucket(
      key: "day:2024-01-01",
      cadence: .daily,
      habit: habit
    )

    habit.target = 0
    try expectError(.invalidRequirement(0)) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-01T12:00:00Z")
    }

    habit.target = 1
    setEntries([0], on: bucket, habit: habit)
    try expectError(.invalidEntryAmount(0)) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-01T12:00:00Z")
    }

    setEntries([-1], on: bucket, habit: habit)
    try expectError(.invalidEntryAmount(-1)) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-01T12:00:00Z")
    }

    setEntries([Int.max, 1], on: bucket, habit: habit)
    try expectError(.progressOverflow) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-01T12:00:00Z")
    }
  }

  @Test("non-final buckets reject invalid cadence and period keys")
  func nonFinalBucketsRejectInvalidCadenceAndPeriodKeys() throws {
    let habit = Habit(name: "Count", cadence: .daily, target: 1)
    let bucket = makeBucket(
      key: "day:2024-01-01",
      cadence: .daily,
      habit: habit
    )

    habit.cadenceRawValue = "monthly"
    try expectError(.unsupportedCadence("monthly")) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-01T12:00:00Z")
    }

    habit.cadenceRawValue = HabitCadence.daily.rawValue
    bucket.cadenceRawValue = "monthly"
    try expectError(.unsupportedCadence("monthly")) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-01T12:00:00Z")
    }

    bucket.cadenceRawValue = HabitCadence.weekly.rawValue
    try expectError(.cadenceMismatch(habit: .daily, bucket: .weekly)) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-01T12:00:00Z")
    }

    habit.cadenceRawValue = HabitCadence.weekly.rawValue
    bucket.periodKey = "not-a-period"
    try expectError(.calendar(.malformedKey("not-a-period"))) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-01T12:00:00Z")
    }

    bucket.periodKey = "day:2024-01-01"
    try expectError(
      .periodCadenceMismatch(key: "day:2024-01-01", cadence: .weekly)
    ) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-01T12:00:00Z")
    }
  }

  @Test("partial finality facts are rejected")
  func partialFinalityFactsAreRejected() throws {
    let habit = Habit(name: "Count", cadence: .daily, target: 1)
    let bucket = makeBucket(
      key: "day:2024-01-01",
      cadence: .daily,
      habit: habit
    )

    bucket.finalizedAt = try instant("2024-01-03T00:00:00Z")
    try expectError(.partialFinality) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-04T00:00:00Z")
    }

    bucket.finalizedAt = nil
    bucket.verdictRawValue = BucketVerdict.met.rawValue
    try expectError(.partialFinality) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-04T00:00:00Z")
    }

    bucket.verdictRawValue = nil
    bucket.targetSnapshot = 1
    try expectError(.partialFinality) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-04T00:00:00Z")
    }

    bucket.targetSnapshot = nil
    bucket.unitSnapshot = "times"
    try expectError(.partialFinality) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-04T00:00:00Z")
    }
  }

  @Test("settled buckets reject invalid frozen facts and exemption conflicts")
  func settledBucketsRejectInvalidFrozenFactsAndExemptionConflicts() throws {
    let habit = Habit(name: "Count", cadence: .daily, target: 1)
    let bucket = makeBucket(
      key: "day:2024-01-01",
      cadence: .daily,
      finalizedAt: try instant("2024-01-03T00:00:00Z"),
      verdict: .met,
      targetSnapshot: 1,
      unitSnapshot: "times",
      habit: habit
    )

    bucket.verdictRawValue = "pending-met"
    try expectError(.unsupportedVerdict("pending-met")) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-04T00:00:00Z")
    }

    bucket.verdictRawValue = BucketVerdict.met.rawValue
    bucket.targetSnapshot = 0
    try expectError(.invalidRequirement(0)) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-04T00:00:00Z")
    }

    bucket.targetSnapshot = 1
    bucket.isExempt = true
    try expectError(.exemptFinalityConflict) {
      _ = try evaluate(habit: habit, bucket: bucket, at: "2024-01-04T00:00:00Z")
    }
  }

  private func evaluate(
    habit: Habit,
    bucket: HabitBucket,
    at value: String,
    timeZoneIdentifier: String = "UTC"
  ) throws -> BucketEvaluation {
    try BucketEvaluator().evaluate(
      habit: habit,
      bucket: bucket,
      at: instant(value),
      timeZone: timeZone(timeZoneIdentifier)
    )
  }

  private func makeBucket(
    key: String,
    cadence: HabitCadence,
    isExempt: Bool = false,
    finalizedAt: Date? = nil,
    verdict: BucketVerdict? = nil,
    targetSnapshot: Int? = nil,
    unitSnapshot: String? = nil,
    habit: Habit
  ) -> HabitBucket {
    HabitBucket(
      periodKey: key,
      startAt: Date(timeIntervalSince1970: 0),
      endAt: Date(timeIntervalSince1970: 1),
      cadence: cadence,
      isExempt: isExempt,
      finalizedAt: finalizedAt,
      verdict: verdict,
      targetSnapshot: targetSnapshot,
      unitSnapshot: unitSnapshot,
      habit: habit
    )
  }

  private func setEntries(_ amounts: [Int], on bucket: HabitBucket, habit: Habit) {
    bucket.entries = amounts.map {
      LogEntry(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        amount: $0,
        habit: habit,
        bucket: bucket
      )
    }
  }

  private func expectError(
    _ expected: BucketEvaluationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected BucketEvaluationError: \(expected)")
    } catch let error as BucketEvaluationError {
      #expect(error == expected)
    }
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private func timeZone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }
}
