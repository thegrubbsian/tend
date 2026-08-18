import Foundation
import SwiftData
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Tend application startup")
struct TendApplicationModelTests {
  @Test("successful startup exposes the produced container exactly once")
  func successfulStartupExposesProducedContainerExactlyOnce() throws {
    let expectedContainer = try TendModelContainer.inMemory()
    var factoryCallCount = 0

    let model = TendApplicationModel {
      factoryCallCount += 1
      return expectedContainer
    }

    #expect(factoryCallCount == 1)
    guard case .ready(let ready) = model.state else {
      Issue.record("Expected successful startup to enter the ready state")
      return
    }
    #expect(ready.container === expectedContainer)
    #expect(model.diagnosticError == nil)
  }

  @Test("failed startup retains the diagnostic without a container")
  func failedStartupRetainsDiagnosticWithoutContainer() {
    var factoryCallCount = 0

    let model = TendApplicationModel {
      factoryCallCount += 1
      throw TestStoreError.unavailable
    }

    #expect(factoryCallCount == 1)
    guard case .failed = model.state else {
      Issue.record("Expected a failed factory to enter the failed state")
      return
    }
    #expect(model.diagnosticError as? TestStoreError == .unavailable)
  }

  @Test("retry can recover with the next produced container")
  func retryCanRecoverWithNextProducedContainer() throws {
    let recoveredContainer = try TendModelContainer.inMemory()
    var factoryCallCount = 0
    let model = TendApplicationModel {
      factoryCallCount += 1
      if factoryCallCount == 1 {
        throw TestStoreError.unavailable
      }
      return recoveredContainer
    }

    model.retry()

    #expect(factoryCallCount == 2)
    guard case .ready(let ready) = model.state else {
      Issue.record("Expected retry success to enter the ready state")
      return
    }
    #expect(ready.container === recoveredContainer)
    #expect(model.diagnosticError == nil)
  }

  @Test("repeated failure keeps only the latest diagnostic")
  func repeatedFailureKeepsOnlyLatestDiagnostic() {
    var factoryCallCount = 0
    let model = TendApplicationModel {
      factoryCallCount += 1
      throw factoryCallCount == 1
        ? TestStoreError.unavailable
        : TestStoreError.stillUnavailable
    }

    model.retry()

    #expect(factoryCallCount == 2)
    guard case .failed = model.state else {
      Issue.record("Expected retry failure to remain in the failed state")
      return
    }
    #expect(model.diagnosticError as? TestStoreError == .stillUnavailable)
  }

  @Test("observing startup state never reopens the store")
  func observingStartupStateNeverReopensStore() throws {
    let container = try TendModelContainer.inMemory()
    var factoryCallCount = 0
    let model = TendApplicationModel {
      factoryCallCount += 1
      return container
    }

    for _ in 0..<10 {
      guard case .ready(let ready) = model.state else {
        Issue.record("Expected state observation to remain ready")
        return
      }
      #expect(ready.container === container)
    }

    #expect(factoryCallCount == 1)
  }

  @Test("UI test stores persist by name until explicitly reset")
  func uiTestStorePersistsByNameUntilExplicitReset() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let resetFactory = try uiTestStoreFactory(
      name: "persisted-store",
      reset: true,
      supportDirectory: supportDirectory
    )
    try createHabit(named: "Read deliberately", using: resetFactory)

    let reopeningFactory = try uiTestStoreFactory(
      name: "persisted-store",
      reset: false,
      supportDirectory: supportDirectory
    )
    #expect(try habitCount(using: reopeningFactory) == 1)

    let secondResetFactory = try uiTestStoreFactory(
      name: "persisted-store",
      reset: true,
      supportDirectory: supportDirectory
    )
    #expect(try habitCount(using: secondResetFactory) == 0)
  }

  @Test("resetting one UI test store preserves every other store")
  func uiTestStoreResetIsNameScoped() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let firstFactory = try uiTestStoreFactory(
      name: "first-store",
      reset: true,
      supportDirectory: supportDirectory
    )
    let secondFactory = try uiTestStoreFactory(
      name: "second-store",
      reset: true,
      supportDirectory: supportDirectory
    )
    try createHabit(named: "First", using: firstFactory)
    try createHabit(named: "Second", using: secondFactory)

    let resetFirstFactory = try uiTestStoreFactory(
      name: "first-store",
      reset: true,
      supportDirectory: supportDirectory
    )
    #expect(try habitCount(using: resetFirstFactory) == 0)

    let reopenSecondFactory = try uiTestStoreFactory(
      name: "second-store",
      reset: false,
      supportDirectory: supportDirectory
    )
    #expect(try habitCount(using: reopenSecondFactory) == 1)
  }

  @Test("unnamed UI test launches fail closed")
  func unnamedUITestStoreIsRejected() throws {
    let factory = try #require(
      TendUITestStore.containerFactory(
        arguments: ["Tend", "-tend-ui-testing"]
      ))

    #expect(throws: (any Error).self) {
      _ = try factory()
    }
  }

  @Test("invalid UI test configuration cannot fall through to production")
  func invalidUIStoreConfigurationThrows() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let missingNameFactory = try #require(
      TendUITestStore.containerFactory(
        arguments: ["Tend", "-tend-ui-testing", "-tend-ui-test-store"],
        applicationSupportDirectory: supportDirectory
      ))
    let invalidNameFactory = try #require(
      TendUITestStore.containerFactory(
        arguments: [
          "Tend",
          "-tend-ui-testing",
          "-tend-ui-test-store",
          "../production",
        ],
        applicationSupportDirectory: supportDirectory
      ))
    let optionAsNameFactory = try #require(
      TendUITestStore.containerFactory(
        arguments: [
          "Tend",
          "-tend-ui-testing",
          "-tend-ui-test-store",
          "-tend-ui-test-reset",
        ],
        applicationSupportDirectory: supportDirectory
      ))
    let orphanedNameFactory = try #require(
      TendUITestStore.containerFactory(
        arguments: ["Tend", "-tend-ui-test-store", "orphaned"],
        applicationSupportDirectory: supportDirectory
      ))
    let orphanedResetFactory = try #require(
      TendUITestStore.containerFactory(
        arguments: ["Tend", "-tend-ui-test-reset"],
        applicationSupportDirectory: supportDirectory
      ))

    #expect(throws: (any Error).self) {
      _ = try missingNameFactory()
    }
    #expect(throws: (any Error).self) {
      _ = try invalidNameFactory()
    }
    #expect(throws: (any Error).self) {
      _ = try optionAsNameFactory()
    }
    #expect(throws: (any Error).self) {
      _ = try orphanedNameFactory()
    }
    #expect(throws: (any Error).self) {
      _ = try orphanedResetFactory()
    }
  }

  @Test("normal launches cannot select a UI test store")
  func normalLaunchDoesNotSelectUITestStore() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }

    #expect(
      TendUITestStore.containerFactory(
        arguments: ["Tend"],
        applicationSupportDirectory: supportDirectory
      ) == nil)
  }

  @Test("habit-detail fixture requires an enabled reset named store")
  func habitDetailFixtureRequiresResetNamedStore() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }

    for arguments in [
      ["Tend", "-tend-ui-test-fixture", "habit-detail"],
      [
        "Tend", "-tend-ui-testing", "-tend-ui-test-store", "fixture",
        "-tend-ui-test-fixture", "habit-detail",
      ],
      [
        "Tend", "-tend-ui-testing", "-tend-ui-test-reset",
        "-tend-ui-test-fixture", "habit-detail",
      ],
      [
        "Tend", "-tend-ui-testing", "-tend-ui-test-store", "fixture",
        "-tend-ui-test-reset", "-tend-ui-test-fixture", "unknown",
      ],
      [
        "Tend", "-tend-ui-testing", "-tend-ui-test-store", "fixture",
        "-tend-ui-test-reset", "-tend-ui-test-fixture",
      ],
      [
        "Tend", "-tend-ui-testing", "-tend-ui-test-store", "fixture",
        "-tend-ui-test-reset", "-tend-ui-test-fixture", "habit-detail",
        "-tend-ui-test-fixture", "habit-detail",
      ],
    ] {
      let factory = try #require(
        TendUITestStore.containerFactory(
          arguments: arguments,
          applicationSupportDirectory: supportDirectory
        )
      )
      #expect(throws: (any Error).self) { _ = try factory() }
    }
  }

  @Test("UI test launch options cannot be used as store names")
  func uiTestLaunchOptionCannotBeStoreName() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let factory = try #require(
      TendUITestStore.containerFactory(
        arguments: [
          "Tend", "-tend-ui-testing", "-tend-ui-test-store",
          "-tend-ui-test-fixture", "habit-detail", "-tend-ui-test-reset",
        ],
        applicationSupportDirectory: supportDirectory
      )
    )

    #expect(throws: TendUITestStoreError.missingName) {
      _ = try factory()
    }
  }

  @Test("habit-detail fixture seeds the complete graph exactly once")
  func habitDetailFixtureSeedsCompleteGraphExactlyOnce() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let launchInstant = try #require(
      ISO8601DateFormatter().date(from: "2026-08-03T12:00:00-07:00")
    )
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    var nowCallCount = 0
    let factory = try #require(
      TendUITestStore.containerFactory(
        arguments: [
          "Tend", "-tend-ui-testing", "-tend-ui-test-store", "habit-detail",
          "-tend-ui-test-reset", "-tend-ui-test-fixture", "habit-detail",
        ],
        applicationSupportDirectory: supportDirectory,
        now: {
          nowCallCount += 1
          return launchInstant
        },
        fixtureTimeZone: timeZone
      )
    )
    #expect(nowCallCount == 1)

    do {
      let container = try factory()
      #expect(nowCallCount == 1)
      let habits = try fetchHabitsOrderedByName(from: container)
      #expect(
        habits.map(\.name) == [
          "Daily garden",
          "Dormant reading",
          "Weekly field notes",
        ])

      let habitsByName = Dictionary(
        uniqueKeysWithValues: habits.map { ($0.name, $0) }
      )
      let dailyHabit = try #require(habitsByName["Daily garden"])
      let weeklyHabit = try #require(habitsByName["Weekly field notes"])
      let inactiveHabit = try #require(habitsByName["Dormant reading"])
      let computation = HabitDetailComputation(context: container.mainContext)
      let dailyAugust = try computation.snapshot(
        for: dailyHabit,
        selectedMonth: launchInstant,
        at: launchInstant,
        timeZone: timeZone
      )
      let dailyJuly = try computation.snapshot(
        for: dailyHabit,
        selectedMonth: try localNoon(
          daysFromLaunch: -12,
          launchInstant: launchInstant,
          timeZone: timeZone
        ),
        at: launchInstant,
        timeZone: timeZone
      )
      let weekly = try computation.snapshot(
        for: weeklyHabit,
        selectedMonth: launchInstant,
        at: launchInstant,
        timeZone: timeZone
      )
      let inactive = try computation.snapshot(
        for: inactiveHabit,
        selectedMonth: launchInstant,
        at: launchInstant,
        timeZone: timeZone
      )
      let dailyHistory = dailyJuly.history + dailyAugust.history
      for state: HabitHistoryState in [.met, .missed, .inactive, .open, .grace, .future] {
        #expect(dailyHistory.contains { $0.state == state })
      }

      let schedule = CalendarBucketSchedule(timeZone: timeZone)
      let currentDailyKey = try schedule.period(
        containing: launchInstant,
        cadence: .daily
      ).key
      let graceDailyKey = try schedule.period(
        containing: try localNoon(
          daysFromLaunch: -1,
          launchInstant: launchInstant,
          timeZone: timeZone
        ),
        cadence: .daily
      ).key
      let currentEntries = dailyAugust.editableEntries.filter {
        $0.bucketKey == currentDailyKey
      }
      let graceEntries = dailyAugust.editableEntries.filter {
        $0.bucketKey == graceDailyKey
      }
      #expect(currentEntries.count == 1)
      #expect(currentEntries.allSatisfy { $0.amount == 1 })
      #expect(graceEntries.count == 2)
      #expect(graceEntries.allSatisfy { $0.amount == 1 })
      #expect(weekly.cadence == .weekly)
      #expect(weekly.history.contains { $0.state == .open })
      #expect(inactiveHabit.isActive == false)
      #expect(inactive.editableEntries.isEmpty)
    }

    let reopeningFactory = try #require(
      TendUITestStore.containerFactory(
        arguments: [
          "Tend", "-tend-ui-testing", "-tend-ui-test-store", "habit-detail",
        ],
        applicationSupportDirectory: supportDirectory
      )
    )
    let reopenedContainer = try reopeningFactory()
    let reopenedNames = try fetchHabitsOrderedByName(from: reopenedContainer).map(\.name)
    #expect(reopenedNames.count == 3)
    #expect(
      reopenedNames == [
        "Daily garden",
        "Dormant reading",
        "Weekly field notes",
      ])
  }

  @Test("Today fixtures require strict complete launch arguments")
  func todayFixturesRequireStrictCompleteLaunchArguments() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }

    for fixture in todayFixtureNames {
      let validPrefix = [
        "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
        "fixture-store", TendUITestStore.resetArgument,
        TendUITestStore.fixtureArgument, fixture,
      ]
      try expectUITestStoreError(
        .missingEnabledArgument,
        arguments: Array(validPrefix.dropFirst(2)),
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .duplicateEnabledArgument,
        arguments: [
          "Tend", TendUITestStore.enabledArgument, TendUITestStore.enabledArgument,
          TendUITestStore.nameArgument, "fixture-store", TendUITestStore.resetArgument,
          TendUITestStore.fixtureArgument, fixture,
        ],
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .missingName,
        arguments: [
          "Tend", TendUITestStore.enabledArgument, TendUITestStore.resetArgument,
          TendUITestStore.fixtureArgument, fixture,
        ],
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .duplicateNameArgument,
        arguments: [
          "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
          "fixture-store", TendUITestStore.nameArgument, "other-store",
          TendUITestStore.resetArgument, TendUITestStore.fixtureArgument, fixture,
        ],
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .fixtureRequiresReset,
        arguments: [
          "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
          "fixture-store", TendUITestStore.fixtureArgument, fixture,
        ],
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .duplicateResetArgument,
        arguments: [
          "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
          "fixture-store", TendUITestStore.resetArgument,
          TendUITestStore.resetArgument, TendUITestStore.fixtureArgument, fixture,
        ],
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .duplicateFixtureArgument,
        arguments: validPrefix + [TendUITestStore.fixtureArgument, fixture],
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .invalidName("../fixture-store"),
        arguments: [
          "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
          "../fixture-store", TendUITestStore.resetArgument,
          TendUITestStore.fixtureArgument, fixture,
        ],
        supportDirectory: supportDirectory
      )
    }

    try expectUITestStoreError(
      .missingFixture,
      arguments: [
        "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
        "fixture-store", TendUITestStore.resetArgument,
        TendUITestStore.fixtureArgument,
      ],
      supportDirectory: supportDirectory
    )
    try expectUITestStoreError(
      .unsupportedFixture("today-unknown"),
      arguments: [
        "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
        "fixture-store", TendUITestStore.resetArgument,
        TendUITestStore.fixtureArgument, "today-unknown",
      ],
      supportDirectory: supportDirectory
    )

    let validInstantArguments = [
      "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
      "fixture-store", TendUITestStore.resetArgument,
      TendUITestStore.fixtureArgument, "today-mixed",
    ]
    try expectUITestStoreError(
      .missingEnabledArgument,
      arguments: [
        "Tend", TendUITestStore.instantArgument, "2026-08-03T19:00:00Z",
      ],
      supportDirectory: supportDirectory
    )
    try expectUITestStoreError(
      .duplicateInstantArgument,
      arguments: validInstantArguments + [
        TendUITestStore.instantArgument, "2026-08-03T19:00:00Z",
        TendUITestStore.instantArgument, "2026-08-04T19:00:00Z",
      ],
      supportDirectory: supportDirectory
    )
    try expectUITestStoreError(
      .invalidInstant("not-a-date"),
      arguments: validInstantArguments + [
        TendUITestStore.instantArgument, "not-a-date",
      ],
      supportDirectory: supportDirectory
    )
  }

  @Test("Fast Logging fixtures require strict complete launch arguments")
  func fastLoggingFixturesRequireStrictCompleteLaunchArguments() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let instant = "2027-01-04T20:00:00Z"
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

    for fixture in fastLoggingFixtureNames {
      let validArguments = [
        "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
        "fixture-store", TendUITestStore.resetArgument,
        TendUITestStore.fixtureArgument, fixture,
        TendUITestStore.instantArgument, instant,
      ]
      let factory = try #require(
        TendUITestStore.containerFactory(
          arguments: validArguments,
          applicationSupportDirectory: supportDirectory,
          fixtureTimeZone: timeZone
        ))
      let container = try factory()
      #expect(try container.mainContext.fetchCount(FetchDescriptor<Habit>()) > 0)
      try expectUITestStoreError(
        .fixtureRequiresInstant,
        arguments: validArguments.filter {
          $0 != TendUITestStore.instantArgument && $0 != instant
        },
        supportDirectory: supportDirectory
      )

      try expectUITestStoreError(
        .missingEnabledArgument,
        arguments: Array(validArguments.dropFirst(2)),
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .duplicateEnabledArgument,
        arguments: validArguments + [TendUITestStore.enabledArgument],
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .missingName,
        arguments: [
          "Tend", TendUITestStore.enabledArgument, TendUITestStore.resetArgument,
          TendUITestStore.fixtureArgument, fixture,
          TendUITestStore.instantArgument, instant,
        ],
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .duplicateNameArgument,
        arguments: validArguments + [TendUITestStore.nameArgument, "other-store"],
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .fixtureRequiresReset,
        arguments: validArguments.filter { $0 != TendUITestStore.resetArgument },
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .duplicateResetArgument,
        arguments: validArguments + [TendUITestStore.resetArgument],
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .duplicateFixtureArgument,
        arguments: validArguments + [TendUITestStore.fixtureArgument, fixture],
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .duplicateInstantArgument,
        arguments: validArguments + [TendUITestStore.instantArgument, instant],
        supportDirectory: supportDirectory
      )
      try expectUITestStoreError(
        .invalidName("../fixture-store"),
        arguments: [
          "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
          "../fixture-store", TendUITestStore.resetArgument,
          TendUITestStore.fixtureArgument, fixture,
          TendUITestStore.instantArgument, instant,
        ],
        supportDirectory: supportDirectory
      )
    }

    try expectUITestStoreError(
      .missingFixture,
      arguments: [
        "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
        "fixture-store", TendUITestStore.resetArgument,
        TendUITestStore.fixtureArgument,
      ],
      supportDirectory: supportDirectory
    )
    try expectUITestStoreError(
      .unsupportedFixture("../fast-logging-daily"),
      arguments: [
        "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
        "fixture-store", TendUITestStore.resetArgument,
        TendUITestStore.fixtureArgument, "../fast-logging-daily",
      ],
      supportDirectory: supportDirectory
    )
  }

  @Test("fast-logging-daily projects exact current and grace facts")
  func fastLoggingDailyProjectsExactCurrentAndGraceFacts() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let launchInstant = try fixtureInstant("2026-12-31T12:00:00-08:00")
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let container = try fastLoggingFixtureFactory(
      storeName: "fast-logging-daily",
      fixture: "fast-logging-daily",
      supportDirectory: supportDirectory,
      launchInstant: launchInstant,
      timeZone: timeZone
    )()
    let habits = try fetchHabitsOrderedByName(from: container)
    #expect(
      habits.map(\.name) == [
        "Feed the cat",
        "Meditate",
        "Posture checks",
        "Read 20 pages",
        "Walk 8K steps",
      ])

    let schedule = CalendarBucketSchedule(timeZone: timeZone)
    let currentPeriod = try schedule.period(containing: launchInstant, cadence: .daily)
    let gracePeriod = try schedule.period(
      containing: currentPeriod.start.addingTimeInterval(-1),
      cadence: .daily
    )
    let logging = HabitLoggingComputation(context: container.mainContext)
    let today = HabitTodayComputation(context: container.mainContext)
    let loggingSnapshots = try Dictionary(
      uniqueKeysWithValues: habits.map {
        ($0.name, try logging.snapshot(for: $0, at: launchInstant, timeZone: timeZone))
      })
    let todaySnapshots = try Dictionary(
      uniqueKeysWithValues: habits.map {
        ($0.name, try today.snapshot(for: $0, at: launchInstant, timeZone: timeZone))
      })
    #expect(loggingSnapshots.values.allSatisfy { $0.current.periodKey == currentPeriod.key })
    #expect(loggingSnapshots.values.allSatisfy { $0.current.phase == .open })
    #expect(todaySnapshots.values.filter(\.isAtRisk).count == 1)

    let targetOne = try #require(loggingSnapshots["Feed the cat"])
    #expect(targetOne.cadence == .daily)
    #expect(targetOne.target == 1)
    #expect(targetOne.unit == "times")
    #expect(targetOne.current.progress == 0)
    #expect(!targetOne.current.isMet)
    #expect(targetOne.current.entries.isEmpty)
    #expect(targetOne.grace == nil)

    let exactTime = try #require(loggingSnapshots["Meditate"])
    #expect(exactTime.target == 10)
    #expect(exactTime.unit == "time")
    #expect(exactTime.current.progress == 0)
    #expect(!exactTime.current.isMet)
    #expect(exactTime.current.entries.isEmpty)
    #expect(exactTime.grace == nil)

    let multiCount = try #require(loggingSnapshots["Posture checks"])
    #expect(multiCount.target == 4)
    #expect(multiCount.unit == "times")
    #expect(multiCount.current.progress == 4)
    #expect(multiCount.current.entries.map(\.amount) == [4])
    #expect(multiCount.current.isMet)
    #expect(multiCount.grace == nil)

    let completedQuantity = try #require(loggingSnapshots["Read 20 pages"])
    #expect(completedQuantity.target == 20)
    #expect(completedQuantity.unit == "pages")
    #expect(completedQuantity.current.progress == 20)
    #expect(completedQuantity.current.entries.map(\.amount) == [20])
    #expect(completedQuantity.current.isMet)
    #expect(completedQuantity.grace == nil)

    let partialQuantity = try #require(loggingSnapshots["Walk 8K steps"])
    #expect(partialQuantity.target == 8_000)
    #expect(partialQuantity.unit == "steps")
    #expect(partialQuantity.current.progress == 4_000)
    #expect(partialQuantity.current.entries.map(\.amount) == [2_000, 2_000])
    #expect(partialQuantity.current.entries.map(\.timestamp) == [launchInstant, launchInstant])
    #expect(Set(partialQuantity.current.entries.map(\.uuid)).count == 2)
    #expect(Set(partialQuantity.current.entries.map(\.id)).count == 2)
    #expect(partialQuantity.current.entries[0].id < partialQuantity.current.entries[1].id)
    #expect(!partialQuantity.current.isMet)
    let grace = try #require(partialQuantity.grace)
    #expect(grace.periodKey == gracePeriod.key)
    #expect(grace.phase == .grace)
    #expect(grace.progress == 3_000)
    #expect(grace.target == 8_000)
    #expect(grace.unit == "steps")
    #expect(!grace.isMet)
    #expect(grace.entries.map(\.amount) == [3_000])

    let partialToday = try #require(todaySnapshots["Walk 8K steps"])
    #expect(partialToday.periodKey == currentPeriod.key)
    #expect(partialToday.progress == 4_000)
    #expect(partialToday.target == 8_000)
    #expect(partialToday.unit == "steps")
    #expect(partialToday.cadence == .daily)
    #expect(partialToday.currentStreak == 3)
    #expect(partialToday.isAtRisk)
    #expect(!partialToday.isMet)
    #expect(try #require(todaySnapshots["Read 20 pages"]).isMet)
    #expect(try #require(todaySnapshots["Posture checks"]).isMet)
    #expect(!(try #require(todaySnapshots["Feed the cat"])).isMet)
  }

  @Test("fast-logging-weekly projects This Week and Last Week on Monday")
  func fastLoggingWeeklyProjectsCurrentAndGraceFacts() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let launchInstant = try fixtureInstant("2027-01-04T12:00:00-08:00")
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let container = try fastLoggingFixtureFactory(
      storeName: "fast-logging-weekly",
      fixture: "fast-logging-weekly",
      supportDirectory: supportDirectory,
      launchInstant: launchInstant,
      timeZone: timeZone
    )()
    let habits = try fetchHabitsOrderedByName(from: container)
    #expect(habits.map(\.name) == ["Weekly check-ins", "Weekly field notes"])

    let schedule = CalendarBucketSchedule(timeZone: timeZone)
    let currentPeriod = try schedule.period(containing: launchInstant, cadence: .weekly)
    let gracePeriod = try schedule.period(
      containing: currentPeriod.start.addingTimeInterval(-1),
      cadence: .weekly
    )
    #expect(currentPeriod.key == "week:2027-01-04")
    #expect(gracePeriod.key == "week:2026-12-28")

    let logging = HabitLoggingComputation(context: container.mainContext)
    let today = HabitTodayComputation(context: container.mainContext)
    let snapshots = try Dictionary(
      uniqueKeysWithValues: habits.map {
        ($0.name, try logging.snapshot(for: $0, at: launchInstant, timeZone: timeZone))
      })
    let todaySnapshots = try Dictionary(
      uniqueKeysWithValues: habits.map {
        ($0.name, try today.snapshot(for: $0, at: launchInstant, timeZone: timeZone))
      })
    #expect(todaySnapshots.values.allSatisfy { $0.periodKey == currentPeriod.key })
    #expect(todaySnapshots.values.allSatisfy { $0.cadence == .weekly })

    let checkInsHabit = try #require(habits.first { $0.name == "Weekly check-ins" })
    #expect(checkInsHabit.pinnedWeekdaysRawValue == PinnedWeekdays.monday.rawValue)
    let checkIns = try #require(snapshots[checkInsHabit.name])
    #expect(checkIns.target == 3)
    #expect(checkIns.unit == "times")
    #expect(checkIns.current.periodKey == currentPeriod.key)
    #expect(checkIns.current.phase == .open)
    #expect(checkIns.current.progress == 1)
    #expect(checkIns.current.entries.map(\.amount) == [1])
    let checkInsGrace = try #require(checkIns.grace)
    #expect(checkInsGrace.periodKey == gracePeriod.key)
    #expect(checkInsGrace.phase == .grace)
    #expect(checkInsGrace.progress == 1)
    #expect(checkInsGrace.entries.map(\.amount) == [1])
    let checkInsToday = try #require(todaySnapshots[checkInsHabit.name])
    #expect(checkInsToday.currentStreak == 3)
    #expect(checkInsToday.isAtRisk)
    #expect(!checkInsToday.isMet)

    let notesHabit = try #require(habits.first { $0.name == "Weekly field notes" })
    #expect(notesHabit.pinnedWeekdaysRawValue == PinnedWeekdays.friday.rawValue)
    let notes = try #require(snapshots[notesHabit.name])
    #expect(notes.target == 100)
    #expect(notes.unit == "pages")
    #expect(notes.current.periodKey == currentPeriod.key)
    #expect(notes.current.phase == .open)
    #expect(notes.current.progress == 40)
    #expect(notes.current.entries.map(\.amount) == [20, 20])
    #expect(notes.current.entries.map(\.timestamp) == [launchInstant, launchInstant])
    #expect(Set(notes.current.entries.map(\.uuid)).count == 2)
    #expect(Set(notes.current.entries.map(\.id)).count == 2)
    #expect(notes.current.entries[0].id < notes.current.entries[1].id)
    let notesGrace = try #require(notes.grace)
    #expect(notesGrace.periodKey == gracePeriod.key)
    #expect(notesGrace.phase == .grace)
    #expect(notesGrace.progress == 30)
    #expect(notesGrace.entries.map(\.amount) == [30])
    let notesToday = try #require(todaySnapshots[notesHabit.name])
    #expect(!notesToday.isAtRisk)
    #expect(!notesToday.isMet)
  }

  @Test("Fast Logging fixtures persist mutations without cross-store reseeding")
  func fastLoggingFixturesPersistMutationsAndRemainStoreScoped() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let launchInstant = try fixtureInstant("2027-01-04T12:00:00-08:00")
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let dailyStore = "persistent-fast-logging-daily"
    let weeklyStore = "persistent-fast-logging-weekly"
    let expectedDailyFingerprint: StoreFingerprint

    do {
      let dailyContainer = try fastLoggingFixtureFactory(
        storeName: dailyStore,
        fixture: "fast-logging-daily",
        supportDirectory: supportDirectory,
        launchInstant: launchInstant,
        timeZone: timeZone
      )()
      let targetOne = try #require(
        try fetchHabitsOrderedByName(from: dailyContainer)
          .first { $0.name == "Feed the cat" }
      )
      try LogEntryOperations(context: dailyContainer.mainContext).append(
        amount: 1,
        to: targetOne,
        at: launchInstant,
        timeZone: timeZone
      )
      expectedDailyFingerprint = try storeFingerprint(of: dailyContainer)
    }

    let weeklyContainer = try fastLoggingFixtureFactory(
      storeName: weeklyStore,
      fixture: "fast-logging-weekly",
      supportDirectory: supportDirectory,
      launchInstant: launchInstant,
      timeZone: timeZone
    )()
    #expect(
      try fetchHabitsOrderedByName(from: weeklyContainer).map(\.name)
        == ["Weekly check-ins", "Weekly field notes"])

    let reopeningFactory = try uiTestStoreFactory(
      name: dailyStore,
      reset: false,
      supportDirectory: supportDirectory
    )
    let reopenedDaily = try reopeningFactory()
    #expect(try storeFingerprint(of: reopenedDaily) == expectedDailyFingerprint)
    #expect(
      try fetchHabitsOrderedByName(from: reopenedDaily).map(\.name) == [
        "Feed the cat",
        "Meditate",
        "Posture checks",
        "Read 20 pages",
        "Walk 8K steps",
      ])
    let reopenedTargetOne = try #require(
      try fetchHabitsOrderedByName(from: reopenedDaily)
        .first { $0.name == "Feed the cat" }
    )
    let reopenedSnapshot = try HabitLoggingComputation(
      context: reopenedDaily.mainContext
    ).snapshot(
      for: reopenedTargetOne,
      at: launchInstant,
      timeZone: timeZone
    )
    #expect(reopenedSnapshot.current.progress == 1)
    #expect(reopenedSnapshot.current.entries.map(\.amount) == [1])
  }

  @Test("Today fixture names cannot stand in for a missing store name")
  func todayFixtureNamesCannotStandInForMissingStoreName() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }

    for fixture in todayFixtureNames {
      try expectUITestStoreError(
        .missingName,
        arguments: [
          "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
          TendUITestStore.fixtureArgument, fixture, TendUITestStore.resetArgument,
        ],
        supportDirectory: supportDirectory
      )
    }
  }

  @Test("today-mixed projects exact rows across civil calendar boundaries")
  func todayMixedProjectsExactRowsAcrossCivilCalendarBoundaries() throws {
    let launchCases = [
      (
        name: "monday",
        instant: "2026-08-03T12:00:00-07:00",
        timeZone: "America/Los_Angeles"
      ),
      (
        name: "dst-transition",
        instant: "2026-11-01T12:00:00-08:00",
        timeZone: "America/Los_Angeles"
      ),
      (
        name: "year-boundary",
        instant: "2026-12-31T12:00:00-08:00",
        timeZone: "America/Los_Angeles"
      ),
      (
        name: "iso-week-boundary",
        instant: "2027-01-04T12:00:00-08:00",
        timeZone: "America/Los_Angeles"
      ),
    ]

    for launchCase in launchCases {
      let supportDirectory = try makeTemporarySupportDirectory()
      defer { try? FileManager.default.removeItem(at: supportDirectory) }
      let launchInstant = try fixtureInstant(launchCase.instant)
      let timeZone = try #require(TimeZone(identifier: launchCase.timeZone))
      let factory = try todayFixtureFactory(
        storeName: "today-mixed-\(launchCase.name)",
        fixture: "today-mixed",
        supportDirectory: supportDirectory,
        launchInstant: launchInstant,
        timeZone: timeZone
      )
      let container = try factory()
      let habits = try fetchHabitsOrderedByName(from: container)
      #expect(
        habits.map(\.name) == [
          "Check in",
          "Exercise",
          "Meditate",
          "Read",
          "Water seedlings",
        ])
      #expect(habits.allSatisfy { $0.isActive })

      let computation = HabitTodayComputation(context: container.mainContext)
      let snapshots = try Dictionary(
        uniqueKeysWithValues: habits.map { habit in
          (
            habit.name,
            try computation.snapshot(
              for: habit,
              at: launchInstant,
              timeZone: timeZone
            )
          )
        })
      let unresolved = snapshots.values.filter { !$0.isMet }
      let met = snapshots.values.filter(\.isMet)
      #expect(unresolved.count == 3)
      #expect(met.count == 2)
      #expect(snapshots.values.filter(\.isAtRisk).count == 1)

      let exercise = try #require(snapshots["Exercise"])
      #expect(exercise.progress == 5_200)
      #expect(exercise.target == 8_000)
      #expect(exercise.unit == "steps")
      #expect(exercise.cadence == .daily)
      #expect(exercise.currentStreak == 12)
      #expect(exercise.isAtRisk)
      #expect(!exercise.isMet)

      let meditate = try #require(snapshots["Meditate"])
      #expect(meditate.progress == 0)
      #expect(meditate.target == 1)
      #expect(meditate.unit == "time")
      #expect(meditate.cadence == .daily)
      #expect(meditate.currentStreak == 0)
      #expect(!meditate.isAtRisk)
      #expect(!meditate.isMet)

      let checkIn = try #require(snapshots["Check in"])
      #expect(checkIn.progress == 1)
      #expect(checkIn.target == 3)
      #expect(checkIn.unit == "times")
      #expect(checkIn.cadence == .weekly)
      #expect(checkIn.currentStreak == 0)
      #expect(!checkIn.isAtRisk)
      #expect(!checkIn.isMet)
      let weeklyHabit = try #require(habits.first { $0.name == "Check in" })
      #expect(weeklyHabit.pinnedWeekdaysRawValue == PinnedWeekdays.monday.rawValue)

      let read = try #require(snapshots["Read"])
      #expect(read.progress == 20)
      #expect(read.target == 20)
      #expect(read.unit == "pages")
      #expect(read.cadence == .daily)
      #expect(read.currentStreak == 1)
      #expect(!read.isAtRisk)
      #expect(read.isMet)

      let water = try #require(snapshots["Water seedlings"])
      #expect(water.progress == 5)
      #expect(water.target == 3)
      #expect(water.unit == "times")
      #expect(water.cadence == .daily)
      #expect(water.currentStreak == 1)
      #expect(!water.isAtRisk)
      #expect(water.isMet)

      let schedule = CalendarBucketSchedule(timeZone: timeZone)
      for habit in habits {
        let cadence = try #require(HabitCadence(rawValue: habit.cadenceRawValue))
        let expectedKey = try schedule.period(
          containing: launchInstant,
          cadence: cadence
        ).key
        let snapshot = try #require(snapshots[habit.name])
        #expect(snapshot.periodKey == expectedKey)
        let currentAmounts = (habit.entries ?? [])
          .filter { $0.bucket?.periodKey == expectedKey }
          .map(\.amount)
          .sorted()
        switch habit.name {
        case "Check in":
          #expect(currentAmounts == [1])
        case "Exercise":
          #expect(currentAmounts == [2_000, 3_200])
        case "Meditate":
          #expect(currentAmounts.isEmpty)
        case "Read":
          #expect(currentAmounts == [20])
        case "Water seedlings":
          #expect(currentAmounts == [2, 3])
        default:
          Issue.record("Unexpected mixed fixture habit \(habit.name)")
        }
      }
    }
  }

  @Test("today-all-tended projects a nonempty fully met set")
  func todayAllTendedProjectsNonemptyFullyMetSet() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let launchInstant = try fixtureInstant("2026-08-05T12:00:00-07:00")
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let factory = try todayFixtureFactory(
      storeName: "today-all-tended",
      fixture: "today-all-tended",
      supportDirectory: supportDirectory,
      launchInstant: launchInstant,
      timeZone: timeZone
    )
    let container = try factory()
    let habits = try fetchHabitsOrderedByName(from: container)
    #expect(habits.map(\.name) == ["Drink water", "Weekly review"])
    let computation = HabitTodayComputation(context: container.mainContext)
    let snapshots = try habits.map {
      try computation.snapshot(for: $0, at: launchInstant, timeZone: timeZone)
    }
    #expect(!snapshots.isEmpty)
    #expect(snapshots.allSatisfy { $0.isMet })
    #expect(snapshots.allSatisfy { !$0.isAtRisk })
    #expect(Set(snapshots.map(\.cadence)) == Set([.daily, .weekly]))
    #expect(
      Set(snapshots.map { "\($0.progress)/\($0.target)" })
        == Set(["1/1", "2/2"]))
  }

  @Test("today-inactive retains history without an active row")
  func todayInactiveRetainsHistoryWithoutActiveRow() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let launchInstant = try fixtureInstant("2026-03-08T12:00:00-07:00")
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let factory = try todayFixtureFactory(
      storeName: "today-inactive",
      fixture: "today-inactive",
      supportDirectory: supportDirectory,
      launchInstant: launchInstant,
      timeZone: timeZone
    )
    let container = try factory()
    let habits = try fetchHabitsOrderedByName(from: container)
    #expect(habits.map(\.name) == ["Dormant journal"])
    let habit = try #require(habits.first)
    #expect(!habit.isActive)
    #expect((habit.entries ?? []).map(\.amount) == [1])
    #expect((habit.activityPeriods ?? []).count == 1)
    #expect((habit.activityPeriods ?? []).allSatisfy { $0.endedAt != nil })
    #expect(habits.filter(\.isActive).isEmpty)
    #expect(throws: HabitTodayComputationError.inactiveHabit) {
      _ = try HabitTodayComputation(context: container.mainContext).snapshot(
        for: habit,
        at: launchInstant,
        timeZone: timeZone
      )
    }
  }

  @Test("today-failure isolates one exact unsupported cadence")
  func todayFailureIsolatesOneExactUnsupportedCadence() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let launchInstant = try fixtureInstant("2027-01-04T12:00:00-08:00")
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let factory = try todayFixtureFactory(
      storeName: "today-failure",
      fixture: "today-failure",
      supportDirectory: supportDirectory,
      launchInstant: launchInstant,
      timeZone: timeZone
    )
    let container = try factory()
    let habits = try fetchHabitsOrderedByName(from: container)
    #expect(
      habits.map(\.name) == [
        "Failure met",
        "Failure open",
        "Malformed cadence",
      ])
    let malformed = try #require(habits.first { $0.name == "Malformed cadence" })
    #expect(malformed.cadenceRawValue == "unsupported-today-fixture")
    let computation = HabitTodayComputation(context: container.mainContext)
    #expect(
      try habits.filter { $0 !== malformed }.map {
        try computation.snapshot(for: $0, at: launchInstant, timeZone: timeZone)
      }.count == 2
    )
    #expect(throws: BucketEvaluationError.unsupportedCadence("unsupported-today-fixture")) {
      _ = try computation.snapshot(
        for: malformed,
        at: launchInstant,
        timeZone: timeZone
      )
    }
  }

  @Test("Today fixtures persist without reseeding and remain store scoped")
  func todayFixturesPersistWithoutReseedingAndRemainStoreScoped() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let launchInstant = try fixtureInstant("2026-12-31T12:00:00-08:00")
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let expectedNames = [
      "today-mixed": [
        "Check in", "Exercise", "Meditate", "Read", "Water seedlings",
      ],
      "today-all-tended": ["Drink water", "Weekly review"],
      "today-inactive": ["Dormant journal"],
      "today-failure": ["Failure met", "Failure open", "Malformed cadence"],
    ]

    for fixture in todayFixtureNames {
      let storeName = "persistent-\(fixture)"
      let expectedFingerprint: StoreFingerprint
      do {
        let factory = try todayFixtureFactory(
          storeName: storeName,
          fixture: fixture,
          supportDirectory: supportDirectory,
          launchInstant: launchInstant,
          timeZone: timeZone
        )
        let container = try factory()
        #expect(
          try fetchHabitsOrderedByName(from: container).map(\.name)
            == expectedNames[fixture])
        expectedFingerprint = try storeFingerprint(of: container)
      }

      let reopeningFactory = try uiTestStoreFactory(
        name: storeName,
        reset: false,
        supportDirectory: supportDirectory
      )
      let reopenedContainer = try reopeningFactory()
      #expect(try storeFingerprint(of: reopenedContainer) == expectedFingerprint)
      #expect(
        try fetchHabitsOrderedByName(from: reopenedContainer).map(\.name)
          == expectedNames[fixture])
    }
  }

  @Test("Today fixture application state opens its store exactly once")
  func todayFixtureApplicationStateOpensStoreExactlyOnce() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let launchInstantValue = "2026-08-03T19:00:00Z"
    let launchInstant = try fixtureInstant(launchInstantValue)
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    var nowCallCount = 0
    let arguments = [
      "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
      "single-open", TendUITestStore.resetArgument,
      TendUITestStore.fixtureArgument, "today-all-tended",
      TendUITestStore.instantArgument, launchInstantValue,
    ]
    let factory = try #require(
      TendUITestStore.containerFactory(
        arguments: arguments,
        applicationSupportDirectory: supportDirectory,
        now: {
          nowCallCount += 1
          return launchInstant.addingTimeInterval(1)
        },
        fixtureTimeZone: timeZone
      ))
    #expect(nowCallCount == 0)
    #expect(TendUITestStore.fixedInstant(arguments: arguments) == launchInstant)
    var factoryCallCount = 0
    let model = TendApplicationModel {
      factoryCallCount += 1
      return try factory()
    }

    for _ in 0..<10 {
      guard case .ready(let ready) = model.state else {
        Issue.record("Expected seeded fixture state to remain ready")
        return
      }
      #expect(
        try ready.container.mainContext.fetchCount(FetchDescriptor<Habit>()) == 2
      )
    }
    #expect(factoryCallCount == 1)
  }

  @Test("goal-roster fixture seeds six valid deterministic lifecycle and progress shapes")
  func goalRosterFixtureSeedsExactLifecycleAndProgressFacts() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let instantValue = "2026-01-15T17:00:00Z"
    let instant = try fixtureInstant(instantValue)
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let arguments = [
      "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
      "goal-roster-fixture", TendUITestStore.resetArgument,
      TendUITestStore.fixtureArgument, "goal-roster",
      TendUITestStore.instantArgument, instantValue,
    ]
    try expectUITestStoreError(
      .fixtureRequiresInstant,
      arguments: Array(arguments.dropLast(2)),
      supportDirectory: supportDirectory
    )
    let factory = try #require(
      TendUITestStore.containerFactory(
        arguments: arguments,
        applicationSupportDirectory: supportDirectory,
        fixtureTimeZone: timeZone
      ))

    #expect(TendUITestStore.fixedInstant(arguments: arguments) == instant)
    let container = try factory()
    let context = container.mainContext
    let goals = try context.fetch(FetchDescriptor<Goal>())
      .sorted { $0.id.uuidString < $1.id.uuidString }
    #expect(goals.count == 6)
    #expect(
      goals.map(\.id.uuidString) == [
        "10000000-0000-0000-0000-000000000001",
        "10000000-0000-0000-0000-000000000002",
        "10000000-0000-0000-0000-000000000003",
        "10000000-0000-0000-0000-000000000004",
        "10000000-0000-0000-0000-000000000005",
        "10000000-0000-0000-0000-000000000006",
      ])
    #expect(try context.fetchCount(FetchDescriptor<GoalEntry>()) == 3)
    #expect(try context.fetchCount(FetchDescriptor<GoalReading>()) == 3)
    let entries = try context.fetch(FetchDescriptor<GoalEntry>())
      .sorted { $0.id.uuidString < $1.id.uuidString }
    #expect(
      entries.map(\.id.uuidString) == [
        "20000000-0000-0000-0000-000000000001",
        "20000000-0000-0000-0000-000000000002",
        "20000000-0000-0000-0000-000000000003",
      ])
    #expect(entries.allSatisfy { $0.assignedDateKey == "2026-01-15" })
    #expect(entries.allSatisfy { $0.appendSequence == 0 })
    let readings = try context.fetch(FetchDescriptor<GoalReading>())
      .sorted { $0.id.uuidString < $1.id.uuidString }
    #expect(
      readings.map(\.id.uuidString) == [
        "30000000-0000-0000-0000-000000000001",
        "30000000-0000-0000-0000-000000000002",
        "30000000-0000-0000-0000-000000000003",
      ])
    #expect(readings.allSatisfy { $0.assignedDateKey == "2026-01-15" })
    #expect(readings.allSatisfy { $0.appendSequence == 0 })

    let goalsByName = Dictionary(uniqueKeysWithValues: goals.map { ($0.name, $0) })
    let progress = GoalProgressComputation(context: context)
    let standing = GoalStandingComputation()
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone

    let accumulate = try #require(
      goalsByName["Fund neighborhood science kits for every after-school classroom"]
    )
    #expect(accumulate.kindRawValue == GoalKind.accumulate.rawValue)
    #expect(accumulate.target == 2_000_000)
    #expect(accumulate.unit == "dollars pledged across neighborhoods")
    #expect(accumulate.baseline == nil)
    #expect(accumulate.deadlineKey == nil)
    #expect(accumulate.closureRawValue == nil)
    #expect((accumulate.entries ?? []).map(\.amount) == [1_250_000])
    guard case .accumulate(let accumulateProgress) = try progress.snapshot(for: accumulate)
    else {
      Issue.record("Expected the fund goal to project accumulate progress")
      return
    }
    #expect(accumulateProgress.total == 1_250_000)
    #expect(accumulateProgress.normalizedProgress == 0.625)
    #expect(
      try standing.snapshot(
        for: accumulate,
        progress: .accumulate(accumulateProgress),
        at: instant,
        calendar: calendar,
        timeZone: timeZone
      )?.standing == .onPace
    )

    let increasing = try #require(goalsByName["Grow oak seedlings"])
    #expect(increasing.kindRawValue == GoalKind.measure.rawValue)
    #expect(increasing.baseline == 120)
    #expect(increasing.target == 200)
    #expect(increasing.deadlineKey == "2026-01-31")
    #expect((increasing.readings ?? []).map(\.value) == [150])
    guard case .measure(let increasingProgress) = try progress.snapshot(for: increasing)
    else {
      Issue.record("Expected the seedling goal to project measure progress")
      return
    }
    #expect(increasingProgress.currentValue == 150)
    #expect(increasingProgress.completedDistance == 30)
    #expect(increasingProgress.totalDistance == 80)
    #expect(increasingProgress.normalizedProgress == 0.375)
    #expect(
      try standing.snapshot(
        for: increasing,
        progress: .measure(increasingProgress),
        at: instant,
        calendar: calendar,
        timeZone: timeZone
      )?.standing == .behind
    )

    let decreasing = try #require(goalsByName["Lower resting heart rate"])
    #expect(decreasing.kindRawValue == GoalKind.measure.rawValue)
    #expect(decreasing.baseline == 80)
    #expect(decreasing.target == 60)
    #expect(decreasing.deadlineKey == "2026-01-31")
    #expect((decreasing.readings ?? []).map(\.value) == [70])
    guard case .measure(let decreasingProgress) = try progress.snapshot(for: decreasing)
    else {
      Issue.record("Expected the heart-rate goal to project measure progress")
      return
    }
    #expect(decreasingProgress.currentValue == 70)
    #expect(decreasingProgress.completedDistance == 10)
    #expect(decreasingProgress.totalDistance == 20)
    #expect(decreasingProgress.normalizedProgress == 0.5)
    #expect(
      try standing.snapshot(
        for: decreasing,
        progress: .measure(decreasingProgress),
        at: instant,
        calendar: calendar,
        timeZone: timeZone
      )?.standing == .onPace
    )

    let pastDue = try #require(goalsByName["Submit winter grant application"])
    #expect(pastDue.deadlineKey == "2026-01-14")
    #expect((pastDue.entries ?? []).map(\.amount) == [7])
    let pastDueProgress = try progress.snapshot(for: pastDue)
    #expect(
      try standing.snapshot(
        for: pastDue,
        progress: pastDueProgress,
        at: instant,
        calendar: calendar,
        timeZone: timeZone
      )?.standing == .pastDue
    )

    let harvested = try #require(goalsByName["Read the field guide"])
    #expect(try harvested.checkedClosure == .harvested)
    #expect((harvested.entries ?? []).map(\.amount) == [12])
    #expect(
      try standing.snapshot(
        for: harvested,
        progress: progress.snapshot(for: harvested),
        at: instant,
        calendar: calendar,
        timeZone: timeZone
      ) == nil
    )

    let letGo = try #require(goalsByName["Walk the coastal trail"])
    #expect(try letGo.checkedClosure == .letGo)
    #expect((letGo.readings ?? []).map(\.value) == [20])
    #expect(
      try standing.snapshot(
        for: letGo,
        progress: progress.snapshot(for: letGo),
        at: instant,
        calendar: calendar,
        timeZone: timeZone
      ) == nil
    )

    let roster = GoalRosterModel(context: context)
    roster.refresh(
      at: instant,
      calendar: calendar,
      timeZone: timeZone,
      locale: Locale(identifier: "en_US")
    )
    #expect(roster.loadFailure == nil)
    #expect(
      roster.openRows.map(\.name) == [
        "Grow oak seedlings",
        "Lower resting heart rate",
        "Fund neighborhood science kits for every after-school classroom",
      ])
    #expect(roster.pastDueRows.map(\.name) == ["Submit winter grant application"])
    #expect(roster.closedRows.map(\.name) == ["Read the field guide", "Walk the coastal trail"])
    #expect(
      roster.openRows.map(\.progressText) == [
        "150 centimeters now · 30 of 80 centimeters",
        "70 beats per minute now · 10 of 20 beats per minute",
        "1,250,000 of 2,000,000 dollars pledged across neighborhoods",
      ])
    #expect(roster.openRows.map(\.stateText) == ["Behind", "On pace", "On pace"])
    #expect(roster.pastDueRows.first?.stateText == "Past due")
    #expect(roster.closedRows.map(\.stateText) == ["Harvested", "Let go"])
  }

  @Test("goal-experience fixture seeds and reopens one deterministic graph")
  func goalExperienceFixtureSeedsDeterministicPersistentGraph() throws {
    let supportDirectory = try makeTemporarySupportDirectory()
    defer { try? FileManager.default.removeItem(at: supportDirectory) }
    let instantValue = "2026-01-15T17:00:00Z"
    let instant = try fixtureInstant(instantValue)
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let storeName = "goal-experience-fixture"
    let arguments = [
      "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
      storeName, TendUITestStore.resetArgument,
      TendUITestStore.fixtureArgument, "goal-experience",
      TendUITestStore.instantArgument, instantValue,
    ]
    let expectedGoalIDs = [
      "11000000-0000-0000-0000-000000000001",
      "11000000-0000-0000-0000-000000000002",
      "11000000-0000-0000-0000-000000000003",
      "11000000-0000-0000-0000-000000000004",
      "11000000-0000-0000-0000-000000000005",
      "11000000-0000-0000-0000-000000000006",
    ]
    let expectedEntryIDs = [
      "21000000-0000-0000-0000-000000000001",
      "21000000-0000-0000-0000-000000000002",
      "21000000-0000-0000-0000-000000000003",
      "21000000-0000-0000-0000-000000000004",
    ]
    let expectedReadingIDs = [
      "31000000-0000-0000-0000-000000000001",
      "31000000-0000-0000-0000-000000000002",
      "31000000-0000-0000-0000-000000000003",
      "31000000-0000-0000-0000-000000000004",
    ]

    try expectUITestStoreError(
      .fixtureRequiresInstant,
      arguments: Array(arguments.dropLast(2)),
      supportDirectory: supportDirectory
    )
    try expectUITestStoreError(
      .missingEnabledArgument,
      arguments: Array(arguments.dropFirst(2)),
      supportDirectory: supportDirectory
    )
    #expect(TendUITestStore.fixedInstant(arguments: arguments) == instant)

    let seededGoalFacts: [String]
    let seededEntryFacts: [String]
    let seededReadingFacts: [String]
    do {
      let factory = try #require(
        TendUITestStore.containerFactory(
          arguments: arguments,
          applicationSupportDirectory: supportDirectory,
          fixtureTimeZone: timeZone
        ))
      let container = try factory()
      let context = container.mainContext
      let goals = try context.fetch(FetchDescriptor<Goal>())
        .sorted { $0.id.uuidString < $1.id.uuidString }
      let entries = try context.fetch(FetchDescriptor<GoalEntry>())
        .sorted { $0.id.uuidString < $1.id.uuidString }
      let readings = try context.fetch(FetchDescriptor<GoalReading>())
        .sorted { $0.id.uuidString < $1.id.uuidString }

      #expect(goals.count == 6)
      #expect(goals.map(\.id.uuidString) == expectedGoalIDs)
      #expect(
        goals.map(\.name) == [
          "Practice piano hours",
          "Grow oak seedlings",
          "Lower resting heart rate",
          "Submit winter grant application",
          "Read the field guide",
          "Walk the coastal trail",
        ])
      #expect(entries.count == 4)
      #expect(entries.map(\.id.uuidString) == expectedEntryIDs)
      #expect(entries.map(\.amount) == [95, 10, 7, 12])
      #expect(
        entries.map(\.assignedDateKey) == [
          "2026-01-01", "2026-01-15", "2026-01-15", "2026-01-15",
        ])
      #expect(entries.map(\.appendSequence) == [0, 1, 0, 0])
      #expect(
        entries.compactMap { $0.goal?.id.uuidString } == [
          expectedGoalIDs[0], expectedGoalIDs[0], expectedGoalIDs[3], expectedGoalIDs[4],
        ])
      #expect(readings.count == 4)
      #expect(readings.map(\.id.uuidString) == expectedReadingIDs)
      #expect(readings.map(\.value) == [140, 150, 70, 20])
      #expect(readings.allSatisfy { $0.assignedDateKey == "2026-01-15" })
      #expect(readings.map(\.appendSequence) == [0, 1, 0, 0])
      #expect(
        readings.compactMap { $0.goal?.id.uuidString } == [
          expectedGoalIDs[1], expectedGoalIDs[1], expectedGoalIDs[2], expectedGoalIDs[5],
        ])

      let goalsByName = Dictionary(uniqueKeysWithValues: goals.map { ($0.name, $0) })
      let progress = GoalProgressComputation(context: context)
      let standing = GoalStandingComputation()
      var calendar = Calendar(identifier: .gregorian)
      calendar.locale = Locale(identifier: "en_US_POSIX")
      calendar.timeZone = timeZone

      let piano = try #require(goalsByName["Practice piano hours"])
      #expect(piano.kindRawValue == GoalKind.accumulate.rawValue)
      #expect(piano.target == 100)
      #expect(piano.unit == "hours")
      #expect(piano.baseline == nil)
      #expect(piano.deadlineKey == nil)
      #expect(try piano.checkedClosure == nil)
      guard case .accumulate(let pianoProgress) = try progress.snapshot(for: piano) else {
        Issue.record("Expected the piano goal to project accumulate progress")
        return
      }
      #expect(pianoProgress.total == 105)
      #expect(pianoProgress.normalizedProgress == 1.05)
      #expect(
        try standing.snapshot(
          for: piano,
          progress: .accumulate(pianoProgress),
          at: instant,
          calendar: calendar,
          timeZone: timeZone
        )?.standing == .onPace
      )

      let increasing = try #require(goalsByName["Grow oak seedlings"])
      #expect(increasing.kindRawValue == GoalKind.measure.rawValue)
      #expect(increasing.target == 200)
      #expect(increasing.unit == "centimeters")
      #expect(increasing.baseline == 120)
      #expect(increasing.deadlineKey == "2026-01-31")
      #expect(try increasing.checkedClosure == nil)
      let increasingReadings = (increasing.readings ?? [])
        .sorted { $0.appendSequence < $1.appendSequence }
      #expect(increasingReadings.map(\.value) == [140, 150])
      #expect(increasingReadings.map(\.assignedDateKey) == ["2026-01-15", "2026-01-15"])
      #expect(increasingReadings.map(\.appendSequence) == [0, 1])
      guard case .measure(let increasingProgress) = try progress.snapshot(for: increasing)
      else {
        Issue.record("Expected the seedling goal to project measure progress")
        return
      }
      #expect(increasingProgress.currentValue == 150)
      #expect(increasingProgress.effectiveReadingID?.uuidString == expectedReadingIDs[1])
      #expect(increasingProgress.completedDistance == 30)
      #expect(increasingProgress.totalDistance == 80)
      #expect(increasingProgress.normalizedProgress == 0.375)
      #expect(
        try standing.snapshot(
          for: increasing,
          progress: .measure(increasingProgress),
          at: instant,
          calendar: calendar,
          timeZone: timeZone
        )?.standing == .behind
      )

      let decreasing = try #require(goalsByName["Lower resting heart rate"])
      #expect(decreasing.kindRawValue == GoalKind.measure.rawValue)
      #expect(decreasing.target == 60)
      #expect(decreasing.unit == "beats per minute")
      #expect(decreasing.baseline == 80)
      #expect(decreasing.deadlineKey == "2026-01-31")
      #expect(try decreasing.checkedClosure == nil)
      guard case .measure(let decreasingProgress) = try progress.snapshot(for: decreasing)
      else {
        Issue.record("Expected the heart-rate goal to project measure progress")
        return
      }
      #expect(decreasingProgress.currentValue == 70)
      #expect(decreasingProgress.effectiveReadingID?.uuidString == expectedReadingIDs[2])
      #expect(decreasingProgress.completedDistance == 10)
      #expect(decreasingProgress.totalDistance == 20)
      #expect(decreasingProgress.normalizedProgress == 0.5)
      #expect(
        try standing.snapshot(
          for: decreasing,
          progress: .measure(decreasingProgress),
          at: instant,
          calendar: calendar,
          timeZone: timeZone
        )?.standing == .onPace
      )

      let pastDue = try #require(goalsByName["Submit winter grant application"])
      #expect(pastDue.kindRawValue == GoalKind.accumulate.rawValue)
      #expect(pastDue.target == 10)
      #expect(pastDue.unit == "sections")
      #expect(pastDue.baseline == nil)
      #expect(pastDue.deadlineKey == "2026-01-14")
      #expect(try pastDue.checkedClosure == nil)
      guard case .accumulate(let pastDueProgress) = try progress.snapshot(for: pastDue) else {
        Issue.record("Expected the grant goal to project accumulate progress")
        return
      }
      #expect(pastDueProgress.total == 7)
      #expect(
        try standing.snapshot(
          for: pastDue,
          progress: .accumulate(pastDueProgress),
          at: instant,
          calendar: calendar,
          timeZone: timeZone
        )?.standing == .pastDue
      )

      let harvested = try #require(goalsByName["Read the field guide"])
      #expect(harvested.kindRawValue == GoalKind.accumulate.rawValue)
      #expect(harvested.target == 12)
      #expect(harvested.unit == "chapters")
      #expect(harvested.baseline == nil)
      #expect(harvested.deadlineKey == nil)
      #expect(try harvested.checkedClosure == .harvested)
      guard case .accumulate(let harvestedProgress) = try progress.snapshot(for: harvested)
      else {
        Issue.record("Expected the field-guide goal to project accumulate progress")
        return
      }
      #expect(harvestedProgress.total == 12)
      #expect(harvestedProgress.target == 12)
      #expect(
        try standing.snapshot(
          for: harvested,
          progress: .accumulate(harvestedProgress),
          at: instant,
          calendar: calendar,
          timeZone: timeZone
        ) == nil
      )

      let letGo = try #require(goalsByName["Walk the coastal trail"])
      #expect(letGo.kindRawValue == GoalKind.measure.rawValue)
      #expect(letGo.target == 100)
      #expect(letGo.unit == "miles")
      #expect(letGo.baseline == 0)
      #expect(letGo.deadlineKey == nil)
      #expect(try letGo.checkedClosure == .letGo)
      guard case .measure(let letGoProgress) = try progress.snapshot(for: letGo) else {
        Issue.record("Expected the coastal-trail goal to project measure progress")
        return
      }
      #expect(letGoProgress.currentValue == 20)
      #expect(letGoProgress.effectiveReadingID?.uuidString == expectedReadingIDs[3])
      #expect(letGoProgress.completedDistance == 20)
      #expect(letGoProgress.totalDistance == 100)
      #expect(letGoProgress.normalizedProgress == 0.2)
      #expect(
        try standing.snapshot(
          for: letGo,
          progress: .measure(letGoProgress),
          at: instant,
          calendar: calendar,
          timeZone: timeZone
        ) == nil
      )

      seededGoalFacts = goals.map { goal in
        [
          goal.id.uuidString,
          goal.name,
          goal.kindRawValue,
          String(goal.target),
          goal.unit,
          goal.baseline.map { String($0) } ?? "nil",
          goal.deadlineKey ?? "nil",
          goal.closureRawValue ?? "nil",
        ].joined(separator: "|")
      }
      seededEntryFacts = entries.map { entry in
        [
          entry.id.uuidString,
          String(entry.amount),
          entry.assignedDateKey,
          String(entry.appendSequence),
          entry.goal?.id.uuidString ?? "nil",
        ].joined(separator: "|")
      }
      seededReadingFacts = readings.map { reading in
        [
          reading.id.uuidString,
          String(reading.value),
          reading.assignedDateKey,
          String(reading.appendSequence),
          reading.goal?.id.uuidString ?? "nil",
        ].joined(separator: "|")
      }
    }

    let reopeningFactory = try uiTestStoreFactory(
      name: storeName,
      reset: false,
      supportDirectory: supportDirectory
    )
    let reopenedContainer = try reopeningFactory()
    let reopenedContext = reopenedContainer.mainContext
    let reopenedGoals = try reopenedContext.fetch(FetchDescriptor<Goal>())
      .sorted { $0.id.uuidString < $1.id.uuidString }
    let reopenedEntries = try reopenedContext.fetch(FetchDescriptor<GoalEntry>())
      .sorted { $0.id.uuidString < $1.id.uuidString }
    let reopenedReadings = try reopenedContext.fetch(FetchDescriptor<GoalReading>())
      .sorted { $0.id.uuidString < $1.id.uuidString }

    #expect(reopenedGoals.count == 6)
    #expect(reopenedEntries.count == 4)
    #expect(reopenedReadings.count == 4)
    #expect(reopenedGoals.map(\.id.uuidString) == expectedGoalIDs)
    #expect(reopenedEntries.map(\.id.uuidString) == expectedEntryIDs)
    #expect(reopenedReadings.map(\.id.uuidString) == expectedReadingIDs)
    #expect(
      reopenedGoals.map { goal in
        [
          goal.id.uuidString,
          goal.name,
          goal.kindRawValue,
          String(goal.target),
          goal.unit,
          goal.baseline.map { String($0) } ?? "nil",
          goal.deadlineKey ?? "nil",
          goal.closureRawValue ?? "nil",
        ].joined(separator: "|")
      } == seededGoalFacts
    )
    #expect(
      reopenedEntries.map { entry in
        [
          entry.id.uuidString,
          String(entry.amount),
          entry.assignedDateKey,
          String(entry.appendSequence),
          entry.goal?.id.uuidString ?? "nil",
        ].joined(separator: "|")
      } == seededEntryFacts
    )
    #expect(
      reopenedReadings.map { reading in
        [
          reading.id.uuidString,
          String(reading.value),
          reading.assignedDateKey,
          String(reading.appendSequence),
          reading.goal?.id.uuidString ?? "nil",
        ].joined(separator: "|")
      } == seededReadingFacts
    )
  }

  private func uiTestStoreFactory(
    name: String,
    reset: Bool,
    supportDirectory: URL
  ) throws -> ModelContainerFactory {
    var arguments = [
      "Tend",
      "-tend-ui-testing",
      "-tend-ui-test-store",
      name,
    ]
    if reset {
      arguments.append("-tend-ui-test-reset")
    }
    return try #require(
      TendUITestStore.containerFactory(
        arguments: arguments,
        applicationSupportDirectory: supportDirectory
      ))
  }

  private func makeTemporarySupportDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(
        path: "TendApplicationModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  private func createHabit(
    named name: String,
    using factory: ModelContainerFactory
  ) throws {
    let container = try factory()
    _ = try HabitManagementOperations(context: container.mainContext).create(
      fields: HabitEditableFields(name: name, target: 1),
      cadence: .daily,
      at: Date(timeIntervalSince1970: 1_725_214_400),
      timeZone: TimeZone(secondsFromGMT: 0)!
    )
  }

  private func habitCount(using factory: ModelContainerFactory) throws -> Int {
    let container = try factory()
    return try container.mainContext.fetchCount(FetchDescriptor<Habit>())
  }

  private func fetchHabitsOrderedByName(from container: ModelContainer) throws -> [Habit] {
    try container.mainContext.fetch(
      FetchDescriptor<Habit>(sortBy: [SortDescriptor(\Habit.name)])
    )
  }

  private func localNoon(
    daysFromLaunch: Int,
    launchInstant: Date,
    timeZone: TimeZone
  ) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    let launchDay = calendar.startOfDay(for: launchInstant)
    let day = try #require(
      calendar.date(byAdding: .day, value: daysFromLaunch, to: launchDay)
    )
    return try #require(
      calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)
    )
  }

  private static let todayFixtureNames = [
    "today-mixed",
    "today-all-tended",
    "today-inactive",
    "today-failure",
  ]

  private var todayFixtureNames: [String] {
    Self.todayFixtureNames
  }

  private static let fastLoggingFixtureNames = [
    "fast-logging-daily",
    "fast-logging-weekly",
  ]

  private var fastLoggingFixtureNames: [String] {
    Self.fastLoggingFixtureNames
  }

  private func fastLoggingFixtureFactory(
    storeName: String,
    fixture: String,
    supportDirectory: URL,
    launchInstant: Date,
    timeZone: TimeZone
  ) throws -> ModelContainerFactory {
    try #require(
      TendUITestStore.containerFactory(
        arguments: [
          "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
          storeName, TendUITestStore.resetArgument,
          TendUITestStore.fixtureArgument, fixture,
          TendUITestStore.instantArgument,
          ISO8601DateFormatter().string(from: launchInstant),
        ],
        applicationSupportDirectory: supportDirectory,
        fixtureTimeZone: timeZone
      ))
  }

  private func todayFixtureFactory(
    storeName: String,
    fixture: String,
    supportDirectory: URL,
    launchInstant: Date,
    timeZone: TimeZone
  ) throws -> ModelContainerFactory {
    try #require(
      TendUITestStore.containerFactory(
        arguments: [
          "Tend", TendUITestStore.enabledArgument, TendUITestStore.nameArgument,
          storeName, TendUITestStore.resetArgument,
          TendUITestStore.fixtureArgument, fixture,
        ],
        applicationSupportDirectory: supportDirectory,
        now: { launchInstant },
        fixtureTimeZone: timeZone
      ))
  }

  private func expectUITestStoreError(
    _ expected: TendUITestStoreError,
    arguments: [String],
    supportDirectory: URL
  ) throws {
    let factory = try #require(
      TendUITestStore.containerFactory(
        arguments: arguments,
        applicationSupportDirectory: supportDirectory
      ))
    #expect(throws: expected) {
      _ = try factory()
    }
  }

  private func fixtureInstant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private struct StoreFingerprint: Equatable {
    let habits: [String]
    let buckets: [String]
    let entries: [String]
    let activityPeriods: [String]
  }

  private func storeFingerprint(of container: ModelContainer) throws -> StoreFingerprint {
    let context = container.mainContext
    return StoreFingerprint(
      habits: try context.fetch(FetchDescriptor<Habit>())
        .map { "\($0.id.uuidString)|\($0.name)" }
        .sorted(),
      buckets: try context.fetch(FetchDescriptor<HabitBucket>())
        .map { "\($0.id.uuidString)|\($0.periodKey)" }
        .sorted(),
      entries: try context.fetch(FetchDescriptor<LogEntry>())
        .map { "\($0.id.uuidString)|\($0.amount)" }
        .sorted(),
      activityPeriods: try context.fetch(FetchDescriptor<HabitActivityPeriod>())
        .map { $0.id.uuidString }
        .sorted()
    )
  }

  private enum TestStoreError: Error, Equatable {
    case unavailable
    case stillUnavailable
  }
}
