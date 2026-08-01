import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Habit streak computation")
struct HabitStreakComputationTests {
  @Test("inactive empty history returns the stored best without saving")
  func inactiveEmptyHistoryReturnsStoredBestWithoutSaving() throws {
    let context = try makeContext()
    let habit = Habit(
      name: "Rest",
      cadence: .daily,
      target: 1,
      isActive: false,
      bestStreak: 7
    )
    context.insert(habit)
    try context.save()
    var saveCount = 0

    let state = try HabitStreakComputation(context: context) {
      saveCount += 1
      try context.save()
    }.compute(
      habit: habit,
      at: try instant("2024-01-10T12:00:00Z"),
      timeZone: try timeZone("UTC")
    )

    #expect(
      state
        == HabitStreakState(
          currentStreak: 0,
          bestStreak: 7,
          isAtRisk: false,
          cadence: .daily
        ))
    #expect(saveCount == 0)
    #expect(!context.hasChanges)
  }

  @Test("active daily computation reconciles and evaluates every bucket")
  func activeDailyComputationReconcilesAndEvaluatesEveryBucket() throws {
    let context = try makeContext()
    let habit = Habit(name: "Read", cadence: .daily, target: 1)
    habit.activityPeriods = [
      HabitActivityPeriod(startedAt: try instant("2024-01-01T00:00:00Z"))
    ]
    context.insert(habit)
    try context.save()
    let logging = LogEntryOperations(context: context)
    try logging.append(
      amount: 1,
      to: habit,
      at: try instant("2024-01-01T12:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    try logging.append(
      amount: 1,
      to: habit,
      at: try instant("2024-01-02T12:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    var saveCount = 0

    let state = try HabitStreakComputation(context: context) {
      saveCount += 1
      try context.save()
    }.compute(
      habit: habit,
      at: try instant("2024-01-03T12:00:00Z"),
      timeZone: try timeZone("UTC")
    )

    #expect(
      state
        == HabitStreakState(
          currentStreak: 2,
          bestStreak: 1,
          isAtRisk: false,
          cadence: .daily
        ))
    #expect(habit.bestStreak == 1)
    #expect(saveCount == 1)
    #expect(!context.hasChanges)
  }

  @Test("weekly slip remains at risk until its grace bucket finalizes")
  func weeklySlipRemainsAtRiskUntilGraceFinalizes() throws {
    let context = try makeContext()
    let habit = Habit(name: "Publish", cadence: .weekly, target: 1)
    habit.activityPeriods = [
      HabitActivityPeriod(startedAt: try instant("2024-01-01T00:00:00Z"))
    ]
    context.insert(habit)
    try context.save()
    let logging = LogEntryOperations(context: context)
    try logging.append(
      amount: 1,
      to: habit,
      at: try instant("2024-01-01T12:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    let operation = HabitStreakComputation(context: context)
    let settledFirstWeek = try operation.compute(
      habit: habit,
      at: try instant("2024-01-09T00:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    #expect(settledFirstWeek.currentStreak == 1)
    #expect(settledFirstWeek.bestStreak == 1)

    try logging.append(
      amount: 1,
      to: habit,
      at: try instant("2024-01-15T12:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    let savableSlip = try operation.compute(
      habit: habit,
      at: try instant("2024-01-15T12:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    #expect(savableSlip.currentStreak == 2)
    #expect(savableSlip.bestStreak == 1)
    #expect(savableSlip.isAtRisk)
    #expect(savableSlip.cadence == .weekly)

    let fossilizedSlip = try operation.compute(
      habit: habit,
      at: try instant("2024-01-16T00:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    #expect(fossilizedSlip.currentStreak == 1)
    #expect(fossilizedSlip.bestStreak == 1)
    #expect(!fossilizedSlip.isAtRisk)
  }

  @Test("grace backfill preserves the daily chain")
  func graceBackfillPreservesDailyChain() throws {
    let context = try makeContext()
    let habit = try insertActiveHabit(
      in: context,
      cadence: .daily,
      target: 30,
      unit: "min",
      activityStart: "2024-01-01T00:00:00Z"
    )
    let logging = LogEntryOperations(context: context)
    try logging.append(
      amount: 30,
      to: habit,
      at: try instant("2024-01-01T08:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    try logging.setTotal(
      30,
      for: habit,
      destination: .periodKey("day:2024-01-02"),
      at: try instant("2024-01-03T08:00:00Z"),
      timeZone: try timeZone("UTC")
    )

    let state = try HabitStreakComputation(context: context).compute(
      habit: habit,
      at: try instant("2024-01-03T08:00:00Z"),
      timeZone: try timeZone("UTC")
    )

    #expect(state.currentStreak == 2)
    #expect(state.bestStreak == 1)
    #expect(!state.isAtRisk)
  }

  @Test("a fossilized miss resets and cannot be backfilled")
  func fossilizedMissResetsAndCannotBeBackfilled() throws {
    let context = try makeContext()
    let habit = try insertActiveHabit(
      in: context,
      cadence: .daily,
      target: 30,
      unit: "min",
      activityStart: "2024-01-01T00:00:00Z"
    )
    let logging = LogEntryOperations(context: context)
    try logging.append(
      amount: 30,
      to: habit,
      at: try instant("2024-01-01T08:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    let operation = HabitStreakComputation(context: context)
    let state = try operation.compute(
      habit: habit,
      at: try instant("2024-01-04T00:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    #expect(state.currentStreak == 0)
    #expect(state.bestStreak == 1)

    try expectError(
      LogEntryOperationError.destinationNotEditable(
        key: "day:2024-01-02",
        phase: .final
      )
    ) {
      _ = try logging.setTotal(
        30,
        for: habit,
        destination: .periodKey("day:2024-01-02"),
        at: try instant("2024-01-04T08:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }
    let unchanged = try operation.compute(
      habit: habit,
      at: try instant("2024-01-04T08:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    #expect(unchanged.currentStreak == 0)
    #expect(unchanged.bestStreak == 1)
  }

  @Test("a partial multi-count day finalizes missed and resets")
  func partialMultiCountDayFinalizesMissedAndResets() throws {
    let context = try makeContext()
    let habit = try insertActiveHabit(
      in: context,
      cadence: .daily,
      target: 3,
      unit: "times",
      activityStart: "2024-01-01T00:00:00Z"
    )
    try LogEntryOperations(context: context).append(
      amount: 2,
      to: habit,
      at: try instant("2024-01-01T08:00:00Z"),
      timeZone: try timeZone("UTC")
    )

    let state = try HabitStreakComputation(context: context).compute(
      habit: habit,
      at: try instant("2024-01-03T00:00:00Z"),
      timeZone: try timeZone("UTC")
    )

    #expect(state.currentStreak == 0)
    #expect(state.bestStreak == 0)
    #expect(!state.isAtRisk)
  }

  @Test("inactive seasonal gaps freeze then resume a forty-day chain")
  func inactiveSeasonalGapFreezesThenResumesFortyDayChain() throws {
    let context = try makeContext()
    let habit = Habit(
      name: "Garden",
      cadence: .daily,
      target: 1,
      bestStreak: 40
    )
    habit.activityPeriods = [
      HabitActivityPeriod(startedAt: try instant("2024-01-01T00:00:00Z"))
    ]
    habit.buckets = try finalizedDailyRun(
      count: 40,
      startingAt: "2024-01-01T00:00:00Z"
    )
    context.insert(habit)
    try context.save()

    try HabitActivityOperations(context: context).deactivate(
      habit,
      at: try instant("2024-02-11T00:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    let bucketCountAtDeactivation = try bucketCount(for: habit, in: context)
    var streakSaveCount = 0
    let operation = HabitStreakComputation(context: context) {
      streakSaveCount += 1
      try context.save()
    }
    let frozen = try operation.compute(
      habit: habit,
      at: try instant("2024-03-01T12:00:00Z"),
      timeZone: try timeZone("UTC")
    )

    #expect(frozen.currentStreak == 40)
    #expect(frozen.bestStreak == 40)
    #expect(!frozen.isAtRisk)
    #expect(try bucketCount(for: habit, in: context) == bucketCountAtDeactivation)
    #expect(streakSaveCount == 0)

    try HabitActivityOperations(context: context).reactivate(
      habit,
      at: try instant("2024-03-01T12:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: try instant("2024-03-01T12:30:00Z"),
      timeZone: try timeZone("UTC")
    )
    let resumed = try operation.compute(
      habit: habit,
      at: try instant("2024-03-01T13:00:00Z"),
      timeZone: try timeZone("UTC")
    )

    #expect(resumed.currentStreak == 41)
    #expect(resumed.bestStreak == 40)
    #expect(!resumed.isAtRisk)
    #expect(habit.bestStreak == 40)
    #expect(streakSaveCount == 0)
  }

  @Test("twelve final days plus a savable miss report thirteen at risk")
  func twelveFinalDaysPlusSavableMissReportThirteenAtRisk() throws {
    let context = try makeContext()
    let schedule = CalendarBucketSchedule(timeZone: try timeZone("UTC"))
    let tuesday = try schedule.period(forKey: "day:2024-01-16")
    let wednesday = try schedule.period(forKey: "day:2024-01-17")
    let grace = HabitBucket(
      periodKey: tuesday.key,
      startAt: tuesday.start,
      endAt: tuesday.end,
      cadence: .daily
    )
    let current = HabitBucket(
      periodKey: wednesday.key,
      startAt: wednesday.start,
      endAt: wednesday.end,
      cadence: .daily
    )
    let habit = Habit(
      name: "Exercise",
      cadence: .daily,
      target: 1,
      bestStreak: 12
    )
    let entry = LogEntry(
      timestamp: try instant("2024-01-17T08:00:00Z"),
      amount: 1,
      habit: habit,
      bucket: current
    )
    habit.activityPeriods = [
      HabitActivityPeriod(startedAt: try instant("2024-01-04T00:00:00Z"))
    ]
    habit.buckets =
      try finalizedDailyRun(
        count: 12,
        startingAt: "2024-01-04T00:00:00Z"
      ) + [grace, current]
    habit.entries = [entry]
    current.entries = [entry]
    context.insert(habit)
    try context.save()

    let state = try HabitStreakComputation(context: context).compute(
      habit: habit,
      at: try instant("2024-01-17T12:00:00Z"),
      timeZone: try timeZone("UTC")
    )

    #expect(state.currentStreak == 13)
    #expect(state.bestStreak == 12)
    #expect(state.isAtRisk)
    #expect(state.cadence == .daily)
  }

  @Test("daily computation crosses spring-forward and fall-back at local midnight")
  func dailyComputationCrossesDSTAtLocalMidnight() throws {
    let springContext = try makeContext()
    let springHabit = try insertActiveHabit(
      in: springContext,
      cadence: .daily,
      target: 1,
      unit: "times",
      activityStart: "2024-03-09T08:00:00Z"
    )
    _ = try HabitStreakComputation(context: springContext).compute(
      habit: springHabit,
      at: try instant("2024-03-11T07:00:00Z"),
      timeZone: try timeZone("America/Los_Angeles")
    )
    let springBuckets = try buckets(for: springHabit, in: springContext)
    #expect(
      springBuckets.map(\.periodKey) == [
        "day:2024-03-09",
        "day:2024-03-10",
        "day:2024-03-11",
      ])
    let springForward = try #require(
      springBuckets.first { $0.periodKey == "day:2024-03-10" }
    )
    #expect(springForward.startAt == (try instant("2024-03-10T08:00:00Z")))
    #expect(springForward.endAt == (try instant("2024-03-11T07:00:00Z")))

    let fallContext = try makeContext()
    let fallHabit = try insertActiveHabit(
      in: fallContext,
      cadence: .daily,
      target: 1,
      unit: "times",
      activityStart: "2024-11-02T07:00:00Z"
    )
    _ = try HabitStreakComputation(context: fallContext).compute(
      habit: fallHabit,
      at: try instant("2024-11-04T08:00:00Z"),
      timeZone: try timeZone("America/Los_Angeles")
    )
    let fallBuckets = try buckets(for: fallHabit, in: fallContext)
    #expect(
      fallBuckets.map(\.periodKey) == [
        "day:2024-11-02",
        "day:2024-11-03",
        "day:2024-11-04",
      ])
    let fallBack = try #require(
      fallBuckets.first { $0.periodKey == "day:2024-11-03" }
    )
    #expect(fallBack.startAt == (try instant("2024-11-03T07:00:00Z")))
    #expect(fallBack.endAt == (try instant("2024-11-04T08:00:00Z")))
  }

  @Test("weekly computation creates the new bucket at Monday midnight")
  func weeklyComputationCreatesNewBucketAtMondayMidnight() throws {
    let context = try makeContext()
    let habit = try insertActiveHabit(
      in: context,
      cadence: .weekly,
      target: 1,
      unit: "times",
      activityStart: "2024-01-03T12:00:00Z"
    )

    let state = try HabitStreakComputation(context: context).compute(
      habit: habit,
      at: try instant("2024-01-08T00:00:00Z"),
      timeZone: try timeZone("UTC")
    )

    #expect(state.cadence == .weekly)
    #expect(
      try buckets(for: habit, in: context).map(\.periodKey) == [
        "week:2024-01-01",
        "week:2024-01-08",
      ])
  }

  @Test("a time-zone key change adds history without renaming a bucket")
  func timeZoneKeyChangeAddsHistoryWithoutRenamingBucket() throws {
    let context = try makeContext()
    let habit = Habit(name: "Read", cadence: .daily, target: 1)
    let activity = HabitActivityPeriod(
      startedAt: try instant("2024-01-01T23:30:00Z")
    )
    let existing = HabitBucket(
      periodKey: "day:2024-01-01",
      startAt: try instant("2024-01-01T00:00:00Z"),
      endAt: try instant("2024-01-02T00:00:00Z"),
      cadence: .daily
    )
    habit.activityPeriods = [activity]
    habit.buckets = [existing]
    context.insert(habit)
    try context.save()

    _ = try HabitStreakComputation(context: context).compute(
      habit: habit,
      at: try instant("2024-01-01T23:45:00Z"),
      timeZone: try timeZone("Asia/Tokyo")
    )

    let persisted = try buckets(for: habit, in: context)
    #expect(persisted.map(\.periodKey) == ["day:2024-01-01", "day:2024-01-02"])
    #expect(persisted[0].persistentModelID == existing.persistentModelID)
    #expect(persisted[1].startAt == (try instant("2024-01-01T15:00:00Z")))
  }

  @Test("provisional records do not save best and a new final saves once")
  func provisionalRecordsDoNotSaveBestAndNewFinalSavesOnce() throws {
    let container = try TendModelContainer.inMemory()
    let context = ModelContext(container)
    let habit = try insertActiveHabit(
      in: context,
      cadence: .daily,
      target: 1,
      unit: "times",
      activityStart: "2024-01-01T00:00:00Z"
    )
    let logging = LogEntryOperations(context: context)
    try logging.append(
      amount: 1,
      to: habit,
      at: try instant("2024-01-01T08:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    var saveCount = 0
    let operation = HabitStreakComputation(context: context) {
      saveCount += 1
      try context.save()
    }

    let graceOnly = try operation.compute(
      habit: habit,
      at: try instant("2024-01-02T08:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    #expect(graceOnly.currentStreak == 1)
    #expect(graceOnly.bestStreak == 0)
    #expect(saveCount == 0)

    try logging.append(
      amount: 1,
      to: habit,
      at: try instant("2024-01-02T09:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    let provisional = try operation.compute(
      habit: habit,
      at: try instant("2024-01-02T10:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    #expect(provisional.currentStreak == 2)
    #expect(provisional.bestStreak == 0)
    #expect(saveCount == 0)

    let finalized = try operation.compute(
      habit: habit,
      at: try instant("2024-01-03T00:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    #expect(finalized.currentStreak == 2)
    #expect(finalized.bestStreak == 1)
    #expect(saveCount == 1)
    _ = try operation.compute(
      habit: habit,
      at: try instant("2024-01-03T00:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    #expect(saveCount == 1)

    let refetchContext = ModelContext(container)
    let refetched = try #require(
      try refetchContext.fetch(FetchDescriptor<Habit>()).first {
        $0.persistentModelID == habit.persistentModelID
      }
    )
    #expect(refetched.bestStreak == 1)
  }

  @Test("smaller finalized history never lowers a persisted best")
  func smallerFinalizedHistoryNeverLowersPersistedBest() throws {
    let context = try makeContext()
    let habit = Habit(
      name: "Record",
      cadence: .daily,
      target: 1,
      isActive: false,
      bestStreak: 9
    )
    habit.buckets = [
      try finalBucket(
        key: "day:2024-01-01",
        cadence: .daily,
        verdict: .met
      ),
      try finalBucket(
        key: "day:2024-01-02",
        cadence: .daily,
        verdict: .met
      ),
    ]
    context.insert(habit)
    try context.save()
    var saveCount = 0

    let state = try HabitStreakComputation(context: context) {
      saveCount += 1
      try context.save()
    }.compute(
      habit: habit,
      at: try instant("2024-01-10T12:00:00Z"),
      timeZone: try timeZone("UTC")
    )

    #expect(state.currentStreak == 2)
    #expect(state.bestStreak == 9)
    #expect(habit.bestStreak == 9)
    #expect(saveCount == 0)
    #expect(!context.hasChanges)
  }

  @Test("best save failure rolls back only the streak mutation")
  func bestSaveFailureRollsBackOnlyStreakMutation() throws {
    let container = try TendModelContainer.inMemory()
    let context = ModelContext(container)
    let habit = try insertActiveHabit(
      in: context,
      cadence: .daily,
      target: 1,
      unit: "times",
      activityStart: "2024-01-01T00:00:00Z"
    )
    try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: try instant("2024-01-01T08:00:00Z"),
      timeZone: try timeZone("UTC")
    )

    try expectError(StreakSaveFailure.expected) {
      _ = try HabitStreakComputation(context: context) {
        throw StreakSaveFailure.expected
      }.compute(
        habit: habit,
        at: try instant("2024-01-03T00:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }

    #expect(habit.bestStreak == 0)
    #expect(!context.hasChanges)
    let refetchContext = ModelContext(container)
    let persistedHabit = try #require(
      try refetchContext.fetch(FetchDescriptor<Habit>()).first {
        $0.persistentModelID == habit.persistentModelID
      }
    )
    #expect(persistedHabit.bestStreak == 0)
    let firstBucket = try #require(
      try refetchContext.fetch(FetchDescriptor<HabitBucket>()).first {
        $0.habit?.persistentModelID == habit.persistentModelID
          && $0.periodKey == "day:2024-01-01"
      }
    )
    #expect(firstBucket.verdictRawValue == BucketVerdict.met.rawValue)
    #expect(firstBucket.finalizedAt == (try instant("2024-01-03T00:00:00Z")))
  }

  @Test("an unreconciled finalization candidate is refused")
  func unreconciledFinalizationCandidateIsRefused() throws {
    let context = try makeContext()
    let period = try CalendarBucketSchedule(timeZone: timeZone("UTC")).period(
      forKey: "day:2024-01-01"
    )
    let habit = Habit(
      name: "Inactive",
      cadence: .daily,
      target: 1,
      isActive: false
    )
    habit.buckets = [
      HabitBucket(
        periodKey: period.key,
        startAt: period.start,
        endAt: period.end,
        cadence: .daily
      )
    ]
    context.insert(habit)
    try context.save()

    try expectError(
      HabitStreakComputationError.unexpectedBucketState(
        key: period.key,
        phase: .dueForFinalization,
        standing: .missed
      )
    ) {
      _ = try HabitStreakComputation(context: context).compute(
        habit: habit,
        at: try instant("2024-01-03T00:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }
    #expect(habit.bestStreak == 0)
    #expect(!context.hasChanges)
  }

  @Test("reconciliation and evaluation failures propagate unchanged")
  func dependencyFailuresPropagateUnchanged() throws {
    let reconciliationContext = try makeContext()
    let missingActivity = Habit(
      name: "Missing activity",
      cadence: .daily,
      target: 1
    )
    reconciliationContext.insert(missingActivity)
    try reconciliationContext.save()
    try expectError(BucketReconciliationError.missingOpenActivityPeriod) {
      _ = try HabitStreakComputation(context: reconciliationContext).compute(
        habit: missingActivity,
        at: try instant("2024-01-01T12:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }

    let evaluationContext = try makeContext()
    let partial = Habit(
      name: "Partial finality",
      cadence: .daily,
      target: 1,
      isActive: false
    )
    partial.buckets = [
      HabitBucket(
        periodKey: "day:2024-01-01",
        startAt: try instant("2024-01-01T00:00:00Z"),
        endAt: try instant("2024-01-02T00:00:00Z"),
        cadence: .daily,
        finalizedAt: try instant("2024-01-03T00:00:00Z")
      )
    ]
    evaluationContext.insert(partial)
    try evaluationContext.save()
    try expectError(BucketEvaluationError.partialFinality) {
      _ = try HabitStreakComputation(context: evaluationContext).compute(
        habit: partial,
        at: try instant("2024-01-10T12:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }
    #expect(partial.bestStreak == 0)
    #expect(!evaluationContext.hasChanges)

    let calendarContext = try makeContext()
    let malformed = Habit(
      name: "Malformed",
      cadence: .daily,
      target: 1,
      isActive: false
    )
    malformed.buckets = [
      HabitBucket(
        periodKey: "not-a-period",
        startAt: try instant("2024-01-01T00:00:00Z"),
        endAt: try instant("2024-01-02T00:00:00Z"),
        cadence: .daily
      )
    ]
    calendarContext.insert(malformed)
    try calendarContext.save()
    try expectError(
      BucketEvaluationError.calendar(.malformedKey("not-a-period"))
    ) {
      _ = try HabitStreakComputation(context: calendarContext).compute(
        habit: malformed,
        at: try instant("2024-01-01T12:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }
    #expect(malformed.bestStreak == 0)
    #expect(!calendarContext.hasChanges)
  }

  @Test("detached deleted and foreign habits are rejected by persistent identity")
  func invalidPersistentHabitIdentityIsRejected() throws {
    let context = try makeContext()
    let detached = Habit(name: "Detached", cadence: .daily, target: 1)
    try expectError(HabitStreakComputationError.detachedHabit) {
      _ = try HabitStreakComputation(context: context).compute(
        habit: detached,
        at: try instant("2024-01-01T12:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }

    let foreignContext = try makeContext()
    let foreign = Habit(name: "Foreign", cadence: .daily, target: 1)
    foreignContext.insert(foreign)
    try foreignContext.save()
    try expectError(HabitStreakComputationError.detachedHabit) {
      _ = try HabitStreakComputation(context: context).compute(
        habit: foreign,
        at: try instant("2024-01-01T12:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }

    let deleted = Habit(name: "Deleted", cadence: .daily, target: 1)
    context.insert(deleted)
    try context.save()
    context.delete(deleted)
    try expectError(HabitStreakComputationError.detachedHabit) {
      _ = try HabitStreakComputation(context: context).compute(
        habit: deleted,
        at: try instant("2024-01-01T12:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }
  }

  @Test("habit values are validated before active reconciliation")
  func habitValuesAreValidatedBeforeActiveReconciliation() throws {
    let unsupportedContext = try makeContext()
    let unsupported = Habit(name: "Unsupported", cadence: .daily, target: 1)
    unsupported.cadenceRawValue = "monthly"
    unsupportedContext.insert(unsupported)
    try unsupportedContext.save()
    try expectError(BucketEvaluationError.unsupportedCadence("monthly")) {
      _ = try HabitStreakComputation(context: unsupportedContext).compute(
        habit: unsupported,
        at: try instant("2024-01-01T12:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }

    let targetContext = try makeContext()
    let invalidTarget = Habit(name: "Target", cadence: .daily, target: 0)
    targetContext.insert(invalidTarget)
    try targetContext.save()
    try expectError(BucketEvaluationError.invalidRequirement(0)) {
      _ = try HabitStreakComputation(context: targetContext).compute(
        habit: invalidTarget,
        at: try instant("2024-01-01T12:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }

    let bestContext = try makeContext()
    let invalidBest = Habit(
      name: "Best",
      cadence: .daily,
      target: 1,
      bestStreak: -3
    )
    bestContext.insert(invalidBest)
    try bestContext.save()
    try expectError(HabitStreakComputationError.invalidBestStreak(-3)) {
      _ = try HabitStreakComputation(context: bestContext).compute(
        habit: invalidBest,
        at: try instant("2024-01-01T12:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }
  }

  @Test("bucket fetches use persistent identity instead of the public UUID")
  func bucketFetchUsesPersistentIdentity() throws {
    let context = try makeContext()
    let sharedID = UUID()
    let metHabit = Habit(
      id: sharedID,
      name: "Met",
      cadence: .daily,
      target: 1,
      isActive: false,
      bestStreak: 1
    )
    let missedHabit = Habit(
      id: sharedID,
      name: "Missed",
      cadence: .daily,
      target: 1,
      isActive: false
    )
    metHabit.buckets = [
      try finalBucket(
        key: "day:2024-01-01",
        cadence: .daily,
        verdict: .met
      )
    ]
    missedHabit.buckets = [
      try finalBucket(
        key: "day:2024-01-01",
        cadence: .daily,
        verdict: .missed
      )
    ]
    context.insert(metHabit)
    context.insert(missedHabit)
    try context.save()
    let operation = HabitStreakComputation(context: context)

    let met = try operation.compute(
      habit: metHabit,
      at: try instant("2024-01-10T12:00:00Z"),
      timeZone: try timeZone("UTC")
    )
    let missed = try operation.compute(
      habit: missedHabit,
      at: try instant("2024-01-10T12:00:00Z"),
      timeZone: try timeZone("UTC")
    )

    #expect(met.currentStreak == 1)
    #expect(missed.currentStreak == 0)
  }

  @Test("inactive duplicate period keys fail before evaluation")
  func inactiveDuplicatePeriodKeysFailBeforeEvaluation() throws {
    let context = try makeContext()
    let habit = Habit(
      name: "Duplicate",
      cadence: .daily,
      target: 1,
      isActive: false
    )
    habit.buckets = [
      HabitBucket(
        periodKey: "day:2024-01-01",
        startAt: try instant("2024-01-01T00:00:00Z"),
        endAt: try instant("2024-01-02T00:00:00Z"),
        cadence: .daily
      ),
      HabitBucket(
        periodKey: "day:2024-01-01",
        startAt: try instant("2024-01-02T00:00:00Z"),
        endAt: try instant("2024-01-03T00:00:00Z"),
        cadence: .daily
      ),
    ]
    context.insert(habit)
    try context.save()

    try expectError(
      HabitStreakComputationError.duplicatePeriodKey("day:2024-01-01")
    ) {
      _ = try HabitStreakComputation(context: context).compute(
        habit: habit,
        at: try instant("2024-01-10T12:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }
    #expect(habit.bestStreak == 0)
    #expect(!context.hasChanges)
  }

  private func insertActiveHabit(
    in context: ModelContext,
    cadence: HabitCadence,
    target: Int,
    unit: String,
    activityStart: String,
    bestStreak: Int = 0
  ) throws -> Habit {
    let habit = Habit(
      name: "Habit",
      cadence: cadence,
      target: target,
      unit: unit,
      bestStreak: bestStreak
    )
    habit.activityPeriods = [
      HabitActivityPeriod(startedAt: try instant(activityStart))
    ]
    context.insert(habit)
    try context.save()
    return habit
  }

  private func buckets(for habit: Habit, in context: ModelContext) throws
    -> [HabitBucket]
  {
    let habitIdentifier = habit.persistentModelID
    return try context.fetch(FetchDescriptor<HabitBucket>())
      .filter { $0.habit?.persistentModelID == habitIdentifier }
      .sorted { $0.periodKey < $1.periodKey }
  }

  private func finalizedDailyRun(
    count: Int,
    startingAt value: String
  ) throws -> [HabitBucket] {
    let schedule = CalendarBucketSchedule(timeZone: try timeZone("UTC"))
    var nextStart = try instant(value)
    var buckets: [HabitBucket] = []
    buckets.reserveCapacity(count)
    for _ in 0..<count {
      let period = try schedule.period(containing: nextStart, cadence: .daily)
      buckets.append(
        HabitBucket(
          periodKey: period.key,
          startAt: period.start,
          endAt: period.end,
          cadence: .daily,
          finalizedAt: period.graceEnd,
          verdict: .met,
          targetSnapshot: 1,
          unitSnapshot: "times"
        ))
      nextStart = period.end
    }
    return buckets
  }

  private func bucketCount(for habit: Habit, in context: ModelContext) throws
    -> Int
  {
    let habitIdentifier = habit.persistentModelID
    return try context.fetch(FetchDescriptor<HabitBucket>())
      .count { $0.habit?.persistentModelID == habitIdentifier }
  }

  private func finalBucket(
    key: String,
    cadence: HabitCadence,
    verdict: BucketVerdict
  ) throws -> HabitBucket {
    let period = try CalendarBucketSchedule(timeZone: timeZone("UTC")).period(
      forKey: key
    )
    return HabitBucket(
      periodKey: key,
      startAt: period.start,
      endAt: period.end,
      cadence: cadence,
      finalizedAt: period.graceEnd,
      verdict: verdict,
      targetSnapshot: 1,
      unitSnapshot: "times"
    )
  }

  private func expectError<E>(
    _ expected: E,
    performing operation: () throws -> Void
  ) throws where E: Error & Equatable {
    do {
      try operation()
      Issue.record("Expected \(expected)")
    } catch let error as E {
      #expect(error == expected)
    }
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private func timeZone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }
}

private enum StreakSaveFailure: Error, Equatable {
  case expected
}
