public struct HabitStreakState: Equatable, Sendable {
  public let currentStreak: Int
  public let bestStreak: Int
  public let isAtRisk: Bool
  public let cadence: HabitCadence
}

public enum HabitStreakComputationError: Error, Equatable, Sendable {
  case detachedHabit
  case duplicatePeriodKey(String)
  case invalidBestStreak(Int)
  case unexpectedBucketState(
    key: String,
    phase: BucketPhase,
    standing: BucketStanding
  )
}

struct StreakBucketState: Equatable, Sendable {
  let key: String
  let phase: BucketPhase
  let standing: BucketStanding
}

struct StreakCalculation: Equatable, Sendable {
  let state: HabitStreakState
  let derivedFinalizedBest: Int
}

struct StreakCalculator: Sendable {
  func calculate(
    cadence: HabitCadence,
    persistedBest: Int,
    buckets: [StreakBucketState]
  ) throws -> StreakCalculation {
    guard persistedBest >= 0 else {
      throw HabitStreakComputationError.invalidBestStreak(persistedBest)
    }

    var currentStreak = 0
    var hasUnmetGrace = false
    var finalizedRun = 0
    var derivedFinalizedBest = 0
    for bucket in buckets {
      try validate(bucket)
      switch bucket.standing {
      case .met, .pendingMet:
        currentStreak += 1
      case .missed:
        currentStreak = 0
        hasUnmetGrace = false
      case .pendingUnmet:
        if bucket.phase == .grace {
          hasUnmetGrace = true
        }
      case .exempt:
        break
      }

      if bucket.phase == .final {
        switch bucket.standing {
        case .met:
          finalizedRun += 1
          derivedFinalizedBest = max(derivedFinalizedBest, finalizedRun)
        case .missed:
          finalizedRun = 0
        case .pendingMet, .pendingUnmet, .exempt:
          break
        }
      }
    }

    return StreakCalculation(
      state: HabitStreakState(
        currentStreak: currentStreak,
        bestStreak: max(persistedBest, derivedFinalizedBest),
        isAtRisk: currentStreak > 0 && hasUnmetGrace,
        cadence: cadence
      ),
      derivedFinalizedBest: derivedFinalizedBest
    )
  }

  private func validate(_ bucket: StreakBucketState) throws {
    switch (bucket.phase, bucket.standing) {
    case (.open, .pendingMet),
      (.open, .pendingUnmet),
      (.grace, .pendingMet),
      (.grace, .pendingUnmet),
      (.final, .met),
      (.final, .missed),
      (.exempt, .exempt):
      return
    default:
      throw HabitStreakComputationError.unexpectedBucketState(
        key: bucket.key,
        phase: bucket.phase,
        standing: bucket.standing
      )
    }
  }
}
