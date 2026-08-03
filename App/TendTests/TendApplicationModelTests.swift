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
    guard case .ready(let actualContainer) = model.state else {
      Issue.record("Expected successful startup to enter the ready state")
      return
    }
    #expect(actualContainer === expectedContainer)
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
    guard case .ready(let actualContainer) = model.state else {
      Issue.record("Expected retry success to enter the ready state")
      return
    }
    #expect(actualContainer === recoveredContainer)
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
      guard case .ready(let observedContainer) = model.state else {
        Issue.record("Expected state observation to remain ready")
        return
      }
      #expect(observedContainer === container)
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

  private enum TestStoreError: Error, Equatable {
    case unavailable
    case stillUnavailable
  }
}
