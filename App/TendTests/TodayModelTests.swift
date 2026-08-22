import Foundation
import SwiftData
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Today presentation model")
struct TodayModelTests {
  @Test("empty and inactive-only stores produce distinct presentations")
  func emptyAndInactiveStoresProduceDistinctPresentations() throws {
    let context = try makeContext()
    var projectionCount = 0
    let model = TodayModel(
      operations: TodayOperations { _, _ in
        projectionCount += 1
        return snapshot(progress: 0, target: 1)
      })
    let refreshContext = makeRefreshContext()

    model.refresh(habits: [], context: refreshContext)
    guard case .firstLaunch? = model.presentation else {
      Issue.record("Expected first-launch presentation")
      return
    }

    let inactive = try insertHabit(
      in: context,
      name: "Dormant",
      isActive: false
    )
    model.refresh(habits: [inactive], context: refreshContext)
    guard case .inactiveOnly? = model.presentation else {
      Issue.record("Expected inactive-only presentation")
      return
    }
    #expect(projectionCount == 0)
  }

  @Test("active persistent identities appear once without ordinary UUID collisions")
  func activePersistentIdentitiesAppearOnceWithoutOrdinaryUUIDCollisions() throws {
    let context = try makeContext()
    let sharedID = UUID()
    let first = try insertHabit(
      in: context,
      id: sharedID,
      name: "First",
      createdAt: Date(timeIntervalSince1970: 10)
    )
    let second = try insertHabit(
      in: context,
      id: sharedID,
      name: "Second",
      createdAt: Date(timeIntervalSince1970: 20)
    )
    let inactive = try insertHabit(
      in: context,
      name: "Inactive",
      isActive: false
    )
    var projectedIDs: [PersistentIdentifier] = []
    let model = TodayModel(
      operations: TodayOperations { habit, _ in
        projectedIDs.append(habit.persistentModelID)
        return snapshot(
          progress: habit.name == "First" ? 0 : 1,
          target: 1,
          isMet: habit.name == "Second"
        )
      })

    model.refresh(
      habits: [first, first, inactive, second, second],
      context: makeRefreshContext()
    )

    let dashboard = try requireDashboard(model)
    let rows = dashboard.toTendRows + dashboard.tendedRows
    #expect(rows.count == 2)
    #expect(Set(rows.map(\.id)).count == 2)
    #expect(Set(rows.map { $0.habit.id }).count == 1)
    #expect(!rows.contains { $0.habit === inactive })
    #expect(projectedIDs.count == 2)
    #expect(Set(projectedIDs) == Set([first.persistentModelID, second.persistentModelID]))
  }

  @Test("one refresh context reaches every operation and publishes atomically")
  func oneRefreshContextReachesEveryOperationAndPublishesAtomically() throws {
    let context = try makeContext()
    let habits = try ["Alpha", "Beta", "Gamma"].enumerated().map { index, name in
      try insertHabit(
        in: context,
        name: name,
        target: 2,
        createdAt: Date(timeIntervalSince1970: Double(index))
      )
    }
    let initialContext = makeRefreshContext(
      instant: Date(timeIntervalSince1970: 1_000),
      timeZoneIdentifier: "UTC",
      localeIdentifier: "en_US"
    )
    let replacementContext = makeRefreshContext(
      instant: Date(timeIntervalSince1970: 2_000),
      timeZoneIdentifier: "America/Los_Angeles",
      localeIdentifier: "fr_FR"
    )
    var generation = 0
    var receivedContexts: [TodayRefreshContext] = []
    var model: TodayModel!
    let operations = TodayOperations { _, refreshContext in
      receivedContexts.append(refreshContext)
      if generation == 1 {
        let published = try requireDashboard(model)
        #expect(
          (published.toTendRows + published.tendedRows)
            .compactMap { $0.facts?.snapshot.progress }
            == [0, 0, 0]
        )
      }
      return snapshot(
        progress: generation,
        target: 2,
        isMet: false
      )
    }
    model = TodayModel(operations: operations)
    model.refresh(habits: habits, context: initialContext)

    generation = 1
    receivedContexts.removeAll()
    model.refresh(habits: habits, context: replacementContext)

    #expect(receivedContexts == Array(repeating: replacementContext, count: 3))
    let replacement = try requireDashboard(model)
    #expect(
      (replacement.toTendRows + replacement.tendedRows)
        .compactMap { $0.facts?.snapshot.progress }
        == [1, 1, 1]
    )
  }

  @Test("successful rows format exact progress streak risk and accessibility facts")
  func successfulRowsFormatExactFacts() throws {
    let context = try makeContext()
    let exercise = try insertHabit(
      in: context,
      name: "Exercise",
      target: 8_000,
      unit: "steps"
    )
    let once = try insertHabit(
      in: context,
      name: "Once",
      target: 1,
      unit: "times"
    )
    let custom = try insertHabit(
      in: context,
      name: "Custom",
      target: 1,
      unit: "reps"
    )
    let weekly = try insertHabit(
      in: context,
      name: "Weekly",
      cadence: .weekly,
      target: 3,
      unit: "times"
    )
    let zero = try insertHabit(
      in: context,
      name: "Zero",
      target: 3,
      unit: "times"
    )
    let snapshots = [
      "Exercise": snapshot(
        progress: 9_000,
        target: 8_000,
        unit: "steps",
        currentStreak: 12_345,
        isAtRisk: true,
        isMet: true
      ),
      "Once": snapshot(
        progress: 1,
        target: 1,
        unit: "times",
        currentStreak: 1,
        isMet: true
      ),
      "Custom": snapshot(
        progress: 1,
        target: 1,
        unit: "reps",
        currentStreak: 1,
        isMet: true
      ),
      "Weekly": snapshot(
        progress: 1,
        target: 3,
        unit: "times",
        cadence: .weekly,
        currentStreak: 2,
        isAtRisk: true
      ),
      "Zero": snapshot(progress: 0, target: 3, unit: "times"),
    ]
    let model = TodayModel(
      operations: TodayOperations { habit, _ in
        try #require(snapshots[habit.name])
      })

    model.refresh(
      habits: [exercise, once, custom, weekly, zero],
      context: makeRefreshContext(localeIdentifier: "en_US")
    )

    let dashboard = try requireDashboard(model)
    let rows = Dictionary(
      uniqueKeysWithValues: (dashboard.toTendRows + dashboard.tendedRows).map {
        ($0.name, $0)
      })
    let exerciseRow = try #require(rows["Exercise"])
    #expect(exerciseRow.progressText == "9,000 of 8,000 steps")
    #expect(exerciseRow.streakText == "12,345 days")
    #expect(exerciseRow.riskText == "Yesterday open · 12,345 day streak at risk")
    #expect(exerciseRow.facts?.visualProgressFraction == 1)
    #expect(exerciseRow.facts?.snapshot.isMet == true)
    #expect(exerciseRow.accessibilityLabel == "Exercise")
    #expect(
      exerciseRow.accessibilityValue
        == "9,000 of 8,000 steps, 12,345 days, Met, Yesterday open · 12,345 day streak at risk"
    )

    let onceRow = try #require(rows["Once"])
    #expect(onceRow.requirementText == "1 time")
    #expect(onceRow.progressText == "1 of 1 time")
    #expect(onceRow.streakText == "1 day")

    let customRow = try #require(rows["Custom"])
    #expect(customRow.requirementText == "1 reps")
    #expect(customRow.progressText == "1 of 1 reps")

    let weeklyRow = try #require(rows["Weekly"])
    #expect(weeklyRow.streakText == "2 weeks")
    #expect(weeklyRow.riskText == "Last week open · 2 week streak at risk")
    #expect(weeklyRow.facts?.snapshot.cadence == .weekly)

    let zeroRow = try #require(rows["Zero"])
    #expect(zeroRow.facts?.visualProgressFraction == 0)
    #expect(zeroRow.progressText == "0 of 3 times")
  }

  @Test("partition ordering uses locale creation time and persistent identity")
  func partitionOrderingUsesDocumentedTieBreakers() throws {
    let context = try makeContext()
    let sameInstant = Date(timeIntervalSince1970: 100)
    let sameNameFirst = try insertHabit(
      in: context,
      name: "alpha",
      createdAt: sameInstant
    )
    let sameNameSecond = try insertHabit(
      in: context,
      name: "Alpha",
      createdAt: sameInstant
    )
    let earlier = try insertHabit(
      in: context,
      name: "Beta",
      createdAt: Date(timeIntervalSince1970: 1)
    )
    let later = try insertHabit(
      in: context,
      name: "beta",
      createdAt: Date(timeIntervalSince1970: 2)
    )
    let umlaut = try insertHabit(in: context, name: "ä")
    let zed = try insertHabit(in: context, name: "z")
    let habits = [sameNameSecond, later, zed, sameNameFirst, umlaut, earlier]
    let model = TodayModel(
      operations: TodayOperations { habit, _ in
        snapshot(
          progress: habit.name.lowercased() == "beta" ? 1 : 0,
          target: 1,
          isMet: habit.name.lowercased() == "beta"
        )
      })

    model.refresh(
      habits: habits,
      context: makeRefreshContext(localeIdentifier: "en_US")
    )
    let english = try requireDashboard(model)
    let expectedAlphaOrder = [sameNameFirst, sameNameSecond].sorted {
      $0.persistentModelID < $1.persistentModelID
    }
    #expect(
      english.toTendRows.map(\.id)
        == [umlaut.persistentModelID]
        + expectedAlphaOrder.map(\.persistentModelID)
        + [zed.persistentModelID]
    )
    #expect(english.tendedRows.map(\.id) == [earlier, later].map(\.persistentModelID))

    model.refresh(
      habits: habits,
      context: makeRefreshContext(localeIdentifier: "sv_SE")
    )
    let swedish = try requireDashboard(model)
    #expect(
      Array(swedish.toTendRows.suffix(2)).map(\.id) == [zed, umlaut].map(\.persistentModelID))
  }

  @Test("failures remain visible in the denominator and block all tended")
  func failuresRemainVisibleAndBlockAllTended() throws {
    let context = try makeContext()
    let first = try insertHabit(in: context, name: "First")
    let failed = try insertHabit(in: context, name: "Malformed", target: 4, unit: "pages")
    let second = try insertHabit(in: context, name: "Second")
    var fails = true
    let model = TodayModel(
      operations: TodayOperations { habit, _ in
        if fails, habit === failed {
          throw ProjectionFailure.fixture
        }
        return snapshot(
          progress: habit.target,
          target: habit.target,
          unit: habit.unit,
          isMet: true
        )
      })
    let refreshContext = makeRefreshContext()

    model.refresh(habits: [first, failed, second], context: refreshContext)
    let partial = try requireDashboard(model)
    #expect(partial.metCount == 2)
    #expect(partial.activeCount == 3)
    #expect(partial.fractionText == "2 of 3")
    #expect(!partial.showsAllTended)
    #expect(partial.toTendRows.map(\.name) == ["Malformed"])
    #expect(partial.tendedRows.count == 2)
    let failedRow = try #require(partial.toTendRows.first)
    #expect(failedRow.requirementText == "4 pages")
    #expect(failedRow.progressText == "Progress unavailable")
    #expect(failedRow.streakText == "Streak unavailable")
    #expect(failedRow.failure?.message == "Fixture unavailable.")
    #expect(failedRow.failure?.retryTitle == "Try again")
    #expect(
      failedRow.accessibilityValue
        == "4 pages, Progress unavailable, Streak unavailable, Fixture unavailable., Try again"
    )

    fails = false
    model.refresh(habits: [first, failed, second], context: refreshContext)
    let complete = try requireDashboard(model)
    #expect(complete.metCount == 3)
    #expect(complete.activeCount == 3)
    #expect(complete.fractionText == "3 of 3")
    #expect(complete.showsAllTended)
    #expect(complete.toTendRows.isEmpty)
    #expect(complete.tendedRows.count == 3)
  }

  @Test("retry is identity scoped atomic and preserves failures")
  func retryIsIdentityScopedAtomicAndPreservesFailures() throws {
    let context = try makeContext()
    let first = try insertHabit(in: context, name: "First")
    let failed = try insertHabit(in: context, name: "Failed")
    let second = try insertHabit(in: context, name: "Second")
    var shouldFail = true
    var calls: [PersistentIdentifier: Int] = [:]
    let model = TodayModel(
      operations: TodayOperations { habit, _ in
        calls[habit.persistentModelID, default: 0] += 1
        if shouldFail, habit === failed {
          throw ProjectionFailure.fixture
        }
        return snapshot(progress: 1, target: 1, isMet: true)
      })
    let habits = [first, failed, second]
    let refreshContext = makeRefreshContext()
    model.refresh(habits: habits, context: refreshContext)
    let initial = try requireDashboard(model)
    #expect(initial.toTendRows.first?.failure?.message == "Fixture unavailable.")

    model.retry(
      habitID: failed.persistentModelID,
      habits: habits,
      journalEntries: [],
      context: refreshContext
    )
    let repeated = try requireDashboard(model)
    #expect(repeated.toTendRows.first?.failure?.message == "Fixture unavailable.")
    #expect(calls[first.persistentModelID] == 1)
    #expect(calls[second.persistentModelID] == 1)
    #expect(calls[failed.persistentModelID] == 2)

    shouldFail = false
    model.retry(
      habitID: failed.persistentModelID,
      habits: habits,
      journalEntries: [],
      context: refreshContext
    )
    let recovered = try requireDashboard(model)
    #expect(recovered.toTendRows.isEmpty)
    #expect(recovered.tendedRows.count == 3)
    #expect(recovered.showsAllTended)
    #expect(calls[first.persistentModelID] == 1)
    #expect(calls[second.persistentModelID] == 1)
    #expect(calls[failed.persistentModelID] == 3)
  }

  @Test("ineligible retry inputs trigger a complete refresh")
  func ineligibleRetryInputsTriggerCompleteRefresh() throws {
    try exerciseIneligibleRetry { habits, failed in
      habits.filter { $0 !== failed }
    } verify: { dashboard, failed in
      #expect(dashboard.activeCount == 2)
      #expect(!(dashboard.toTendRows + dashboard.tendedRows).contains { $0.habit === failed })
    }

    try exerciseIneligibleRetry { habits, failed in
      failed.isActive = false
      return habits
    } verify: { dashboard, failed in
      #expect(dashboard.activeCount == 2)
      #expect(!(dashboard.toTendRows + dashboard.tendedRows).contains { $0.habit === failed })
    }

    try exerciseIneligibleRetry { habits, failed in
      failed.name = "Changed"
      return habits
    } verify: { dashboard, failed in
      #expect(dashboard.activeCount == 3)
      #expect((dashboard.toTendRows + dashboard.tendedRows).contains { $0.name == "Changed" })
      #expect((dashboard.toTendRows + dashboard.tendedRows).contains { $0.habit === failed })
    }
  }

  @Test("projection graph changes make scoped retry ineligible")
  func projectionGraphChangesMakeScopedRetryIneligible() throws {
    let context = try makeContext()
    let first = try insertHabit(in: context, name: "First")
    let failed = try insertHabit(in: context, name: "Failed")
    let second = try insertHabit(in: context, name: "Second")
    let entry = LogEntry(
      timestamp: Date(timeIntervalSince1970: 100),
      amount: 1,
      habit: first
    )
    context.insert(entry)
    try context.save()
    var fails = true
    var calls: [PersistentIdentifier: Int] = [:]
    let model = TodayModel(
      operations: TodayOperations { habit, _ in
        calls[habit.persistentModelID, default: 0] += 1
        if fails, habit === failed {
          throw ProjectionFailure.fixture
        }
        return snapshot(progress: 1, target: 1, isMet: true)
      })
    let habits = [first, failed, second]
    let refreshContext = makeRefreshContext()
    model.refresh(habits: habits, context: refreshContext)

    entry.amount = 2
    try context.save()
    fails = false
    model.retry(
      habitID: failed.persistentModelID,
      habits: habits,
      journalEntries: [],
      context: refreshContext
    )

    #expect(calls[first.persistentModelID] == 2)
    #expect(calls[failed.persistentModelID] == 2)
    #expect(calls[second.persistentModelID] == 2)
  }

  @Test("extreme imported values remain deterministic and unavailable when invalid")
  func extremeImportedValuesRemainDeterministic() throws {
    let context = try makeContext()
    let longName = String(repeating: "Long owner name ", count: 20)
    let longUnit = String(repeating: "custom-unit-", count: 20)
    let large = try insertHabit(
      in: context,
      name: longName,
      target: Int.max,
      unit: longUnit
    )
    let emptyName = try insertHabit(in: context, name: "", target: 1, unit: "times")
    let invalid = try insertHabit(in: context, name: "Invalid", target: 0, unit: "times")
    let model = TodayModel(
      operations: TodayOperations { habit, _ in
        if habit === invalid {
          return snapshot(progress: 0, target: 0, unit: "times")
        }
        return snapshot(
          progress: habit === large ? Int.max : 0,
          target: habit.target,
          unit: habit.unit,
          isMet: habit === large
        )
      })
    let refreshContext = makeRefreshContext(localeIdentifier: "en_US")

    model.refresh(habits: [large, emptyName, invalid], context: refreshContext)
    let first = try requireDashboard(model)
    let rows = first.toTendRows + first.tendedRows
    let largeRow = try #require(rows.first { $0.habit === large })
    #expect(largeRow.name == longName)
    #expect(largeRow.progressText.contains(longUnit))
    #expect(largeRow.facts?.visualProgressFraction == 1)
    let emptyRow = try #require(rows.first { $0.habit === emptyName })
    #expect(emptyRow.name.isEmpty)
    #expect(emptyRow.progressText == "0 of 1 time")
    let invalidRow = try #require(rows.first { $0.habit === invalid })
    #expect(invalidRow.facts == nil)
    #expect(invalidRow.failure?.message == "Requirement unavailable.")

    let firstFingerprint = presentationFingerprint(first)
    model.refresh(habits: [large, emptyName, invalid], context: refreshContext)
    let second = try requireDashboard(model)
    #expect(presentationFingerprint(second) == firstFingerprint)
  }

  private func exerciseIneligibleRetry(
    update: (_ habits: [Habit], _ failed: Habit) -> [Habit],
    verify: (_ dashboard: TodayDashboardPresentation, _ failed: Habit) -> Void
  ) throws {
    let context = try makeContext()
    let first = try insertHabit(in: context, name: "First")
    let failed = try insertHabit(in: context, name: "Failed")
    let second = try insertHabit(in: context, name: "Second")
    var fails = true
    var calls: [PersistentIdentifier: Int] = [:]
    let model = TodayModel(
      operations: TodayOperations { habit, _ in
        calls[habit.persistentModelID, default: 0] += 1
        if fails, habit === failed {
          throw ProjectionFailure.fixture
        }
        return snapshot(progress: 1, target: 1, isMet: true)
      })
    let originalHabits = [first, failed, second]
    let refreshContext = makeRefreshContext()
    model.refresh(habits: originalHabits, context: refreshContext)
    fails = false
    let updatedHabits = update(originalHabits, failed)

    model.retry(
      habitID: failed.persistentModelID,
      habits: updatedHabits,
      journalEntries: [],
      context: refreshContext
    )

    let dashboard = try requireDashboard(model)
    verify(dashboard, failed)
    #expect(calls[first.persistentModelID] == 2)
    #expect(calls[second.persistentModelID] == 2)
  }

  private func presentationFingerprint(
    _ presentation: TodayDashboardPresentation
  ) -> [String] {
    (presentation.toTendRows + presentation.tendedRows).map { row in
      [
        String(describing: row.id),
        row.name,
        row.requirementText,
        row.progressText,
        row.streakText,
        row.riskText ?? "",
        row.failure?.message ?? "",
        row.accessibilityValue,
      ].joined(separator: "|")
    }
  }

  private func requireDashboard(_ model: TodayModel) throws -> TodayDashboardPresentation {
    guard case .dashboard(let dashboard)? = model.presentation else {
      throw TestSetupError.expectedDashboard
    }
    return dashboard
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func insertHabit(
    in context: ModelContext,
    id: UUID = UUID(),
    name: String,
    cadence: HabitCadence = .daily,
    target: Int = 1,
    unit: String = "times",
    isActive: Bool = true,
    createdAt: Date = Date(timeIntervalSince1970: 100)
  ) throws -> Habit {
    let habit = Habit(
      id: id,
      name: name,
      cadence: cadence,
      target: target,
      unit: unit,
      isActive: isActive,
      createdAt: createdAt
    )
    context.insert(habit)
    try context.save()
    return habit
  }

  private func makeRefreshContext(
    instant: Date = Date(timeIntervalSince1970: 1_000),
    timeZoneIdentifier: String = "UTC",
    localeIdentifier: String = "en_US"
  ) -> TodayRefreshContext {
    let timeZone = TimeZone(identifier: timeZoneIdentifier)!
    let locale = Locale(identifier: localeIdentifier)
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    calendar.timeZone = timeZone
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return TodayRefreshContext(
      instant: instant,
      timeZone: timeZone,
      calendar: calendar,
      locale: locale
    )
  }

  private func snapshot(
    progress: Int,
    target: Int,
    unit: String = "times",
    cadence: HabitCadence = .daily,
    currentStreak: Int = 0,
    isAtRisk: Bool = false,
    isMet: Bool = false
  ) -> HabitTodaySnapshot {
    HabitTodaySnapshot(
      periodKey: cadence == .daily ? "day:2026-08-04" : "week:2026-08-03",
      progress: progress,
      target: target,
      unit: unit,
      cadence: cadence,
      currentStreak: currentStreak,
      isAtRisk: isAtRisk,
      isMet: isMet
    )
  }

  private enum ProjectionFailure: Error, LocalizedError {
    case fixture

    var errorDescription: String? {
      "Fixture unavailable."
    }
  }

  private enum TestSetupError: Error {
    case expectedDashboard
  }
}
