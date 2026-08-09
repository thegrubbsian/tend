import SwiftData

typealias ReminderRefreshSignal = @MainActor () -> Void

typealias ReminderAuthorizationRequest = @MainActor () async -> Void

@MainActor
protocol ReminderRuntimeClient: AnyObject {
  var routing: ReminderRoutingModel { get }

  func refresh()
  func requestAuthorizationIfNeeded() async
}

@MainActor
final class ReminderAuthorizationController {
  private let notificationCenter: any ReminderNotificationCenterClient
  private let reminderRefresh: ReminderRefreshSignal
  private var isRequesting = false

  init(
    notificationCenter: any ReminderNotificationCenterClient,
    reminderRefresh: @escaping ReminderRefreshSignal
  ) {
    self.notificationCenter = notificationCenter
    self.reminderRefresh = reminderRefresh
  }

  func requestIfNeeded() async {
    guard !isRequesting else { return }
    isRequesting = true
    defer { isRequesting = false }

    do {
      guard try await notificationCenter.authorizationStatus() == .notDetermined else {
        return
      }
      _ = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
      reminderRefresh()
    } catch {
      return
    }
  }
}

@MainActor
final class ReminderAppRuntime: ReminderRuntimeClient {
  let routing: ReminderRoutingModel

  private let coordinator: ReminderCoordinator
  private let notificationCenter: any ReminderNotificationCenterClient
  private lazy var authorizationController = ReminderAuthorizationController(
    notificationCenter: notificationCenter,
    reminderRefresh: refresh
  )

  init(
    container: ModelContainer,
    notificationCenter: any ReminderNotificationCenterClient,
    routing: ReminderRoutingModel
  ) {
    coordinator = ReminderCoordinator(
      context: container.mainContext,
      notificationCenter: notificationCenter
    )
    self.notificationCenter = notificationCenter
    self.routing = routing
  }

  func refresh() {
    Task { await coordinator.refresh() }
  }

  func requestAuthorizationIfNeeded() async {
    await authorizationController.requestIfNeeded()
  }
}

@MainActor
final class DisabledReminderRuntime: ReminderRuntimeClient {
  let routing = ReminderRoutingModel()

  func refresh() {}

  func requestAuthorizationIfNeeded() async {}
}
