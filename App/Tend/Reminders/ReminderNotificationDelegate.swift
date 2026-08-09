import UserNotifications

@MainActor
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate,
  @unchecked Sendable
{
  private let routing: ReminderRoutingModel

  init(routing: ReminderRoutingModel) {
    self.routing = routing
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    guard Self.isTendOwned(response.notification.request) else { return }
    await showToday()
  }

  func route(_ request: UNNotificationRequest) {
    guard Self.isTendOwned(request) else { return }
    showToday()
  }

  nonisolated private static func isTendOwned(
    _ request: UNNotificationRequest
  ) -> Bool {
    request.identifier.hasPrefix(ReminderPlanner.identifierPrefix)
      && request.content.categoryIdentifier
        == ReminderPendingRequest.requiredCategoryIdentifier
      && request.content.userInfo[ReminderPendingRequest.ownershipKey] as? Bool == true
  }

  private func showToday() {
    routing.showToday()
  }
}
