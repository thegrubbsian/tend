import Testing

@testable import TendCore

@Suite("Streak calculator")
struct StreakCalculatorTests {
  @Test(
    "empty history preserves the stored best and cadence",
    arguments: [HabitCadence.daily, .weekly]
  )
  func emptyHistoryPreservesStoredBestAndCadence(_ cadence: HabitCadence) throws {
    let calculation = try StreakCalculator().calculate(
      cadence: cadence,
      persistedBest: 7,
      buckets: []
    )

    #expect(
      calculation.state
        == HabitStreakState(
          currentStreak: 0,
          bestStreak: 7,
          isAtRisk: false,
          cadence: cadence
        )
    )
    #expect(calculation.derivedFinalizedBest == 0)
  }

  @Test("final and provisional met buckets count without partial credit")
  func metBucketsCountWithoutPartialCredit() throws {
    let calculation = try StreakCalculator().calculate(
      cadence: .daily,
      persistedBest: 0,
      buckets: [
        bucket("day:2024-01-01", .final, .met),
        bucket("day:2024-01-02", .grace, .pendingMet),
        bucket("day:2024-01-03", .open, .pendingUnmet),
      ]
    )

    #expect(calculation.state.currentStreak == 2)
    #expect(!calculation.state.isAtRisk)
  }

  @Test("a final miss hard-resets the current chain")
  func finalMissHardResetsCurrentChain() throws {
    let calculation = try StreakCalculator().calculate(
      cadence: .weekly,
      persistedBest: 0,
      buckets: [
        bucket("week:2023-12-18", .final, .met),
        bucket("week:2023-12-25", .final, .met),
        bucket("week:2024-01-01", .final, .missed),
        bucket("week:2024-01-08", .grace, .pendingUnmet),
        bucket("week:2024-01-15", .open, .pendingMet),
      ]
    )

    #expect(calculation.state.currentStreak == 1)
  }

  @Test("unmet grace preserves but does not increment a nonzero chain")
  func unmetGraceMarksSurvivingChainAtRisk() throws {
    var buckets = (1...12).map {
      bucket("day:final-\($0)", .final, .met)
    }
    buckets.append(bucket("day:grace", .grace, .pendingUnmet))
    buckets.append(bucket("day:open", .open, .pendingMet))

    let calculation = try StreakCalculator().calculate(
      cadence: .daily,
      persistedBest: 12,
      buckets: buckets
    )

    #expect(calculation.state.currentStreak == 13)
    #expect(calculation.state.isAtRisk)
  }

  @Test("a final miss clears risk inherited from older grace")
  func finalMissClearsOlderGraceRisk() throws {
    let calculation = try StreakCalculator().calculate(
      cadence: .daily,
      persistedBest: 3,
      buckets: [
        bucket("day:2024-01-01", .final, .met),
        bucket("day:2024-01-02", .grace, .pendingUnmet),
        bucket("day:2024-01-03", .final, .missed),
        bucket("day:2024-01-04", .open, .pendingMet),
      ]
    )

    #expect(calculation.state.currentStreak == 1)
    #expect(!calculation.state.isAtRisk)
  }

  @Test("exempt gaps neither count nor break grace risk")
  func exemptGapsPreserveGraceRisk() throws {
    let calculation = try StreakCalculator().calculate(
      cadence: .weekly,
      persistedBest: 1,
      buckets: [
        bucket("week:2023-12-25", .final, .met),
        bucket("week:2024-01-01", .grace, .pendingUnmet),
        bucket("week:2024-01-08", .exempt, .exempt),
        bucket("week:2024-01-15", .open, .pendingMet),
      ]
    )

    #expect(calculation.state.currentStreak == 2)
    #expect(calculation.state.isAtRisk)
  }

  @Test("an unmet grace bucket cannot put a zero streak at risk")
  func zeroStreakIsNeverAtRisk() throws {
    let calculation = try StreakCalculator().calculate(
      cadence: .daily,
      persistedBest: 0,
      buckets: [
        bucket("day:2024-01-01", .final, .missed),
        bucket("day:2024-01-02", .grace, .pendingUnmet),
        bucket("day:2024-01-03", .open, .pendingUnmet),
      ]
    )

    #expect(calculation.state.currentStreak == 0)
    #expect(!calculation.state.isAtRisk)
  }

  @Test("only finalized met runs establish the derived best")
  func finalizedRunsEstablishDerivedBest() throws {
    let calculation = try StreakCalculator().calculate(
      cadence: .daily,
      persistedBest: 2,
      buckets: [
        bucket("day:2024-01-01", .final, .met),
        bucket("day:2024-01-02", .final, .met),
        bucket("day:2024-01-03", .final, .missed),
        bucket("day:2024-01-04", .final, .met),
        bucket("day:2024-01-05", .exempt, .exempt),
        bucket("day:2024-01-06", .final, .met),
        bucket("day:2024-01-07", .final, .met),
        bucket("day:2024-01-08", .final, .met),
        bucket("day:2024-01-09", .grace, .pendingMet),
        bucket("day:2024-01-10", .open, .pendingMet),
      ]
    )

    #expect(calculation.state.currentStreak == 6)
    #expect(calculation.state.bestStreak == 4)
    #expect(calculation.derivedFinalizedBest == 4)
  }

  @Test("a larger persisted best is never lowered")
  func largerPersistedBestIsNeverLowered() throws {
    let calculation = try StreakCalculator().calculate(
      cadence: .weekly,
      persistedBest: 9,
      buckets: [
        bucket("week:2023-12-18", .final, .met),
        bucket("week:2023-12-25", .final, .met),
        bucket("week:2024-01-01", .final, .missed),
        bucket("week:2024-01-08", .final, .met),
        bucket("week:2024-01-15", .open, .pendingMet),
      ]
    )

    #expect(calculation.state.currentStreak == 2)
    #expect(calculation.state.bestStreak == 9)
    #expect(calculation.derivedFinalizedBest == 2)
  }

  @Test("negative persisted best is rejected before calculation")
  func negativePersistedBestIsRejected() throws {
    try expectError(.invalidBestStreak(-1)) {
      _ = try StreakCalculator().calculate(
        cadence: .daily,
        persistedBest: -1,
        buckets: []
      )
    }
  }

  @Test("every impossible phase and standing pair is rejected")
  func impossibleBucketStatesAreRejected() throws {
    let invalidStates: [(BucketPhase, BucketStanding)] = [
      (.open, .met),
      (.open, .missed),
      (.open, .exempt),
      (.grace, .met),
      (.grace, .missed),
      (.grace, .exempt),
      (.dueForFinalization, .pendingMet),
      (.dueForFinalization, .pendingUnmet),
      (.dueForFinalization, .met),
      (.dueForFinalization, .missed),
      (.dueForFinalization, .exempt),
      (.final, .pendingMet),
      (.final, .pendingUnmet),
      (.final, .exempt),
      (.exempt, .pendingMet),
      (.exempt, .pendingUnmet),
      (.exempt, .met),
      (.exempt, .missed),
    ]

    for (index, state) in invalidStates.enumerated() {
      let key = "invalid:\(index)"
      try expectError(
        .unexpectedBucketState(
          key: key,
          phase: state.0,
          standing: state.1
        )
      ) {
        _ = try StreakCalculator().calculate(
          cadence: .weekly,
          persistedBest: 0,
          buckets: [bucket(key, state.0, state.1)]
        )
      }
    }
  }
  private func bucket(
    _ key: String,
    _ phase: BucketPhase,
    _ standing: BucketStanding
  ) -> StreakBucketState {
    StreakBucketState(key: key, phase: phase, standing: standing)
  }

  private func expectError(
    _ expected: HabitStreakComputationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected HabitStreakComputationError: \(expected)")
    } catch let error as HabitStreakComputationError {
      #expect(error == expected)
    } catch {
      Issue.record("Expected \(expected), got \(error)")
    }
  }
}
