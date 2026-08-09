import SwiftData
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Reminder app integration")
struct ReminderAppIntegrationTests {
  @Test("eligible reminder gesture requests alert and sound once then refreshes")
  func eligibleGestureRequestsPermissionOnce() async {
    let center = IntegrationNotificationCenter(
      authorizationStatus: .notDetermined,
      requestAuthorizationResult: false
    )
    let refreshes = IntegrationRefreshSpy()
    let controller = ReminderAuthorizationController(
      notificationCenter: center,
      reminderRefresh: refreshes.signal
    )

    await controller.requestIfNeeded()
    await controller.requestIfNeeded()

    #expect(center.requestedAuthorizationOptions == [[.alert, .sound]])
    #expect(center.requestAuthorizationCallCount == 1)
    #expect(refreshes.count == 1)
  }

  @Test("determined authorization never requests permission or reconciliation")
  func determinedAuthorizationDoesNotPrompt() async {
    for status in [
      ReminderAuthorizationStatus.denied,
      .authorized,
      .unavailable,
    ] {
      let center = IntegrationNotificationCenter(authorizationStatus: status)
      let refreshes = IntegrationRefreshSpy()
      let controller = ReminderAuthorizationController(
        notificationCenter: center,
        reminderRefresh: refreshes.signal
      )

      await controller.requestIfNeeded()

      #expect(center.requestAuthorizationCallCount == 0)
      #expect(refreshes.count == 0)
    }
  }

  @Test("authorization failure remains isolated from the reminder gesture")
  func authorizationFailureIsIsolated() async {
    let center = IntegrationNotificationCenter(authorizationStatus: .notDetermined)
    center.requestAuthorizationError = IntegrationFailure.expected
    let refreshes = IntegrationRefreshSpy()
    let controller = ReminderAuthorizationController(
      notificationCenter: center,
      reminderRefresh: refreshes.signal
    )

    await controller.requestIfNeeded()

    #expect(center.requestAuthorizationCallCount == 1)
    #expect(refreshes.count == 0)
  }

  @Test("ready store creates one runtime and starts one refresh")
  func readyStoreCreatesAndStartsRuntime() throws {
    let container = try TendModelContainer.inMemory()
    let runtime = IntegrationReminderRuntime()
    var receivedContainers: [ModelContainer] = []

    let model = TendApplicationModel(
      makeContainer: { container },
      makeReminderRuntime: { receivedContainer in
        receivedContainers.append(receivedContainer)
        return runtime
      }
    )

    let ready = try #require(model.readyState)
    #expect(ready.container === container)
    #expect(ready.reminders === runtime)
    #expect(receivedContainers.count == 1)
    #expect(receivedContainers.first === container)
    #expect(runtime.refreshCount == 1)
  }

  @Test("failed store creates no reminder runtime")
  func failedStoreCreatesNoRuntime() {
    var runtimeFactoryCallCount = 0

    let model = TendApplicationModel(
      makeContainer: { throw IntegrationFailure.expected },
      makeReminderRuntime: { _ in
        runtimeFactoryCallCount += 1
        return IntegrationReminderRuntime()
      }
    )

    #expect(model.readyState == nil)
    #expect(runtimeFactoryCallCount == 0)
  }

  @Test("store recovery replaces the runtime and active scenes refresh only ready state")
  func storeRecoveryReplacesRuntime() throws {
    let firstContainer = try TendModelContainer.inMemory()
    let replacementContainer = try TendModelContainer.inMemory()
    let firstRuntime = IntegrationReminderRuntime()
    let replacementRuntime = IntegrationReminderRuntime()
    var containerAttempt = 0
    var runtimeAttempt = 0

    let model = TendApplicationModel(
      makeContainer: {
        containerAttempt += 1
        switch containerAttempt {
        case 1: return firstContainer
        case 2: throw IntegrationFailure.expected
        default: return replacementContainer
        }
      },
      makeReminderRuntime: { _ in
        runtimeAttempt += 1
        return runtimeAttempt == 1 ? firstRuntime : replacementRuntime
      }
    )

    model.sceneDidBecomeActive()
    #expect(firstRuntime.refreshCount == 2)

    model.retry()
    #expect(model.readyState == nil)
    model.sceneDidBecomeActive()
    #expect(firstRuntime.refreshCount == 2)
    #expect(runtimeAttempt == 1)

    model.retry()
    let ready = try #require(model.readyState)
    #expect(ready.container === replacementContainer)
    #expect(ready.reminders === replacementRuntime)
    #expect(replacementRuntime.refreshCount == 1)

    model.sceneDidBecomeActive()
    model.sceneDidBecomeActive()
    #expect(replacementRuntime.refreshCount == 3)
  }
}

@MainActor
private final class IntegrationReminderRuntime: ReminderRuntimeClient {
  let routing = ReminderRoutingModel()
  private(set) var refreshCount = 0
  private(set) var authorizationRequestCount = 0

  func refresh() {
    refreshCount += 1
  }

  func requestAuthorizationIfNeeded() async {
    authorizationRequestCount += 1
  }
}

@MainActor
private final class IntegrationRefreshSpy {
  private(set) var count = 0

  lazy var signal: ReminderRefreshSignal = { [weak self] in
    self?.count += 1
  }
}

@MainActor
private final class IntegrationNotificationCenter: ReminderNotificationCenterClient {
  private(set) var authorizationStatusCallCount = 0
  private(set) var requestAuthorizationCallCount = 0
  private(set) var requestedAuthorizationOptions: [ReminderAuthorizationOptions] = []
  var requestAuthorizationError: (any Error)?

  private var status: ReminderAuthorizationStatus
  private let requestAuthorizationResult: Bool

  init(
    authorizationStatus: ReminderAuthorizationStatus,
    requestAuthorizationResult: Bool = false
  ) {
    status = authorizationStatus
    self.requestAuthorizationResult = requestAuthorizationResult
  }

  func authorizationStatus() async throws -> ReminderAuthorizationStatus {
    authorizationStatusCallCount += 1
    return status
  }

  func requestAuthorization(
    options: ReminderAuthorizationOptions
  ) async throws -> Bool {
    requestAuthorizationCallCount += 1
    requestedAuthorizationOptions.append(options)
    if let requestAuthorizationError {
      throw requestAuthorizationError
    }
    status = requestAuthorizationResult ? .authorized : .denied
    return requestAuthorizationResult
  }

  func tendPendingRequests() async throws -> [ReminderPendingRequest] {
    []
  }

  func removePendingRequest(withIdentifier identifier: String) async throws {}

  func addOrReplace(_ occurrence: ReminderOccurrence) async throws {}
}

private enum IntegrationFailure: Error {
  case expected
}
