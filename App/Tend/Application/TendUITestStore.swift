#if DEBUG
  import Foundation
  import TendCore

  enum TendUITestStoreError: Error, Equatable, LocalizedError {
    case missingEnabledArgument
    case duplicateEnabledArgument
    case missingName
    case duplicateNameArgument
    case invalidName(String)
    case duplicateResetArgument
    case missingFixture
    case duplicateFixtureArgument
    case unsupportedFixture(String)
    case duplicateInstantArgument
    case invalidInstant(String)
    case fixtureRequiresReset

    var errorDescription: String? {
      switch self {
      case .missingEnabledArgument:
        "UI-test storage arguments require the UI-test launch flag."
      case .duplicateEnabledArgument:
        "The UI-test launch flag was provided more than once."
      case .missingName:
        "A named UI-test store is required."
      case .duplicateNameArgument:
        "Only one UI-test store name may be provided."
      case .invalidName(let name):
        "The UI-test store name \(name) is invalid."
      case .duplicateResetArgument:
        "The UI-test reset flag was provided more than once."
      case .missingFixture:
        "A UI-test fixture name is required."
      case .duplicateFixtureArgument:
        "Only one UI-test fixture may be provided."
      case .unsupportedFixture(let fixture):
        "The UI-test fixture \(fixture) is unsupported."
      case .duplicateInstantArgument:
        "Only one UI-test instant may be provided."
      case .invalidInstant(let instant):
        "The UI-test instant \(instant) is invalid."
      case .fixtureRequiresReset:
        "A UI-test fixture requires exactly one reset flag."
      }
    }
  }

  enum TendUITestStore {
    static let enabledArgument = "-tend-ui-testing"
    static let nameArgument = "-tend-ui-test-store"
    static let resetArgument = "-tend-ui-test-reset"
    static let fixtureArgument = "-tend-ui-test-fixture"
    static let instantArgument = "-tend-ui-test-instant"

    enum Fixture: String {
      case habitDetail = "habit-detail"
      case todayMixed = "today-mixed"
      case todayAllTended = "today-all-tended"
      case todayInactive = "today-inactive"
      case todayFailure = "today-failure"
      case fastLoggingDaily = "fast-logging-daily"
      case fastLoggingWeekly = "fast-logging-weekly"
    }

    static func containerFactory(
      arguments: [String],
      fileManager: FileManager = .default,
      applicationSupportDirectory: URL? = nil,
      now: () -> Date = Date.init,
      fixtureTimeZone: TimeZone = .autoupdatingCurrent
    ) -> ModelContainerFactory? {
      let enabledCount = arguments.count { $0 == enabledArgument }
      guard enabledCount > 0 else {
        if arguments.contains(nameArgument)
          || arguments.contains(resetArgument)
          || arguments.contains(fixtureArgument)
          || arguments.contains(instantArgument)
        {
          return { throw TendUITestStoreError.missingEnabledArgument }
        }
        return nil
      }

      let configuration: Configuration
      do {
        configuration = try Configuration(arguments: arguments)
      } catch {
        return { throw error }
      }
      let launchInstant = configuration.instant ?? now()

      return {
        let supportDirectory: URL
        if let applicationSupportDirectory {
          supportDirectory = applicationSupportDirectory
        } else {
          supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
          )
        }
        let testRoot =
          supportDirectory
          .appending(path: "TendUITests", directoryHint: .isDirectory)
        let storeDirectory =
          testRoot
          .appending(path: configuration.name, directoryHint: .isDirectory)

        if configuration.resetsStore,
          fileManager.fileExists(atPath: storeDirectory.path)
        {
          try fileManager.removeItem(at: storeDirectory)
        }
        try fileManager.createDirectory(
          at: storeDirectory,
          withIntermediateDirectories: true
        )
        let container = try TendModelContainer.fileBacked(
          at: storeDirectory.appending(path: "Tend.store", directoryHint: .notDirectory)
        )
        switch configuration.fixture {
        case .habitDetail:
          try HabitDetailUITestFixture.seed(
            context: container.mainContext,
            at: launchInstant,
            timeZone: fixtureTimeZone
          )
        case .todayMixed:
          try TodayDashboardUITestFixture.seed(
            .mixed,
            context: container.mainContext,
            at: launchInstant,
            timeZone: fixtureTimeZone
          )
        case .todayAllTended:
          try TodayDashboardUITestFixture.seed(
            .allTended,
            context: container.mainContext,
            at: launchInstant,
            timeZone: fixtureTimeZone
          )
        case .todayInactive:
          try TodayDashboardUITestFixture.seed(
            .inactive,
            context: container.mainContext,
            at: launchInstant,
            timeZone: fixtureTimeZone
          )
        case .todayFailure:
          try TodayDashboardUITestFixture.seed(
            .failure,
            context: container.mainContext,
            at: launchInstant,
            timeZone: fixtureTimeZone
          )
        case .fastLoggingDaily:
          try FastLoggingUITestFixture.seed(
            .daily,
            context: container.mainContext,
            at: launchInstant,
            timeZone: fixtureTimeZone
          )
        case .fastLoggingWeekly:
          try FastLoggingUITestFixture.seed(
            .weekly,
            context: container.mainContext,
            at: launchInstant,
            timeZone: fixtureTimeZone
          )
        case nil:
          break
        }
        return container
      }
    }

    static func fixedInstant(arguments: [String]) -> Date? {
      (try? Configuration(arguments: arguments))?.instant
    }

    private struct Configuration {
      let name: String
      let resetsStore: Bool
      let fixture: Fixture?
      let instant: Date?

      init(arguments: [String]) throws {
        guard arguments.count(where: { $0 == enabledArgument }) == 1 else {
          throw TendUITestStoreError.duplicateEnabledArgument
        }
        let nameIndices = arguments.indices.filter { arguments[$0] == nameArgument }
        guard !nameIndices.isEmpty else {
          throw TendUITestStoreError.missingName
        }
        guard nameIndices.count == 1 else {
          throw TendUITestStoreError.duplicateNameArgument
        }
        let valueIndex = arguments.index(after: nameIndices[0])
        guard valueIndex < arguments.endIndex else {
          throw TendUITestStoreError.missingName
        }
        let name = arguments[valueIndex]
        guard !Self.optionArguments.contains(name) else {
          throw TendUITestStoreError.missingName
        }
        guard Self.isValid(name: name) else {
          throw TendUITestStoreError.invalidName(name)
        }

        let resetCount = arguments.count { $0 == resetArgument }
        guard resetCount <= 1 else {
          throw TendUITestStoreError.duplicateResetArgument
        }

        let fixtureIndices = arguments.indices.filter { arguments[$0] == fixtureArgument }
        guard fixtureIndices.count <= 1 else {
          throw TendUITestStoreError.duplicateFixtureArgument
        }
        let fixture: Fixture?
        if let fixtureIndex = fixtureIndices.first {
          let fixtureValueIndex = arguments.index(after: fixtureIndex)
          guard fixtureValueIndex < arguments.endIndex else {
            throw TendUITestStoreError.missingFixture
          }
          let fixtureValue = arguments[fixtureValueIndex]
          guard !Self.optionArguments.contains(fixtureValue) else {
            throw TendUITestStoreError.missingFixture
          }
          guard let parsedFixture = Fixture(rawValue: fixtureValue) else {
            throw TendUITestStoreError.unsupportedFixture(fixtureValue)
          }
          guard resetCount == 1 else {
            throw TendUITestStoreError.fixtureRequiresReset
          }
          fixture = parsedFixture
        } else {
          fixture = nil
        }

        let instantIndices = arguments.indices.filter { arguments[$0] == instantArgument }
        guard instantIndices.count <= 1 else {
          throw TendUITestStoreError.duplicateInstantArgument
        }
        let instant: Date?
        if let instantIndex = instantIndices.first {
          let instantValueIndex = arguments.index(after: instantIndex)
          guard instantValueIndex < arguments.endIndex else {
            throw TendUITestStoreError.invalidInstant("")
          }
          let instantValue = arguments[instantValueIndex]
          guard !Self.optionArguments.contains(instantValue),
            let parsedInstant = ISO8601DateFormatter().date(from: instantValue)
          else {
            throw TendUITestStoreError.invalidInstant(instantValue)
          }
          instant = parsedInstant
        } else {
          instant = nil
        }

        self.name = name
        resetsStore = resetCount == 1
        self.fixture = fixture
        self.instant = instant
      }

      private static let optionArguments = [
        enabledArgument,
        nameArgument,
        resetArgument,
        fixtureArgument,
        instantArgument,
      ]

      private static func isValid(name: String) -> Bool {
        guard !name.isEmpty else {
          return false
        }
        return name.unicodeScalars.allSatisfy { scalar in
          switch scalar.value {
          case 45, 48...57, 65...90, 95, 97...122:
            true
          default:
            false
          }
        }
      }
    }
  }
#endif
