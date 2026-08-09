import Foundation
import UserNotifications

nonisolated enum ReminderAuthorizationStatus: Equatable, Sendable {
  case notDetermined
  case denied
  case authorized
  case unavailable
}
nonisolated struct ReminderAuthorizationOptions: OptionSet, Equatable, Sendable {
  let rawValue: Int

  static let alert = Self(rawValue: 1 << 0)
  static let sound = Self(rawValue: 1 << 1)
}

nonisolated struct ReminderPendingRequest: Equatable, Sendable {
  let identifier: String
  let title: String
  let body: String
  let usesDefaultSound: Bool
  let dateComponents: DateComponents?
  let categoryIdentifier: String
  let hasOwnershipMarker: Bool
  let badge: Int?
  static let requiredCategoryIdentifier = "tend.reminder"
  static let ownershipKey = "tend.reminder"

  init(
    identifier: String,
    title: String,
    body: String,
    usesDefaultSound: Bool = true,
    categoryIdentifier: String = Self.requiredCategoryIdentifier,
    hasOwnershipMarker: Bool = true,
    badge: Int? = nil,
    dateComponents: DateComponents?
  ) {
    self.identifier = identifier
    self.title = title
    self.body = body
    self.usesDefaultSound = usesDefaultSound
    self.categoryIdentifier = categoryIdentifier
    self.hasOwnershipMarker = hasOwnershipMarker
    self.badge = badge
    self.dateComponents = dateComponents
  }

  init(occurrence: ReminderOccurrence) {
    self.init(
      identifier: occurrence.identifier,
      title: occurrence.title,
      body: occurrence.body,
      dateComponents: occurrence.dateComponents
    )
  }
}

@MainActor
protocol ReminderNotificationCenterClient: AnyObject {
  func authorizationStatus() async throws -> ReminderAuthorizationStatus
  func requestAuthorization(options: ReminderAuthorizationOptions) async throws -> Bool
  func tendPendingRequests() async throws -> [ReminderPendingRequest]
  func removePendingRequest(withIdentifier identifier: String) async throws
  func addOrReplace(_ occurrence: ReminderOccurrence) async throws
}

@MainActor
final class LiveReminderNotificationCenter: ReminderNotificationCenterClient {
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func authorizationStatus() async throws -> ReminderAuthorizationStatus {
    let settings = await center.notificationSettings()
    return Self.projectAuthorizationStatus(
      settings.authorizationStatus,
      alertSetting: settings.alertSetting,
      notificationCenterSetting: settings.notificationCenterSetting,
      lockScreenSetting: settings.lockScreenSetting
    )
  }
  func requestAuthorization(
    options: ReminderAuthorizationOptions
  ) async throws -> Bool {
    var userNotificationOptions: UNAuthorizationOptions = []
    if options.contains(.alert) {
      userNotificationOptions.insert(.alert)
    }
    if options.contains(.sound) {
      userNotificationOptions.insert(.sound)
    }
    return try await center.requestAuthorization(options: userNotificationOptions)
  }

  func tendPendingRequests() async throws -> [ReminderPendingRequest] {
    await center.pendingNotificationRequests()
      .compactMap(Self.projectPendingRequest)
  }

  func removePendingRequest(withIdentifier identifier: String) async throws {
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
  }

  func addOrReplace(_ occurrence: ReminderOccurrence) async throws {
    try await center.add(Self.notificationRequest(for: occurrence))
  }

  nonisolated static func notificationRequest(
    for occurrence: ReminderOccurrence
  ) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = occurrence.title
    content.body = occurrence.body
    content.sound = .default
    content.categoryIdentifier = ReminderPendingRequest.requiredCategoryIdentifier
    content.userInfo = [ReminderPendingRequest.ownershipKey: true]
    let trigger = UNCalendarNotificationTrigger(
      dateMatching: occurrence.dateComponents,
      repeats: false
    )
    return UNNotificationRequest(
      identifier: occurrence.identifier,
      content: content,
      trigger: trigger
    )
  }

  nonisolated static func projectAuthorizationStatus(
    _ authorizationStatus: UNAuthorizationStatus,
    alertSetting: UNNotificationSetting,
    notificationCenterSetting: UNNotificationSetting,
    lockScreenSetting: UNNotificationSetting
  ) -> ReminderAuthorizationStatus {
    switch authorizationStatus {
    case .notDetermined:
      return .notDetermined
    case .denied:
      return .denied
    case .authorized, .provisional, .ephemeral:
      let deliverySettings = [
        alertSetting,
        notificationCenterSetting,
        lockScreenSetting,
      ]
      return deliverySettings.contains(.enabled) ? .authorized : .unavailable
    @unknown default:
      return .unavailable
    }
  }

  nonisolated static func projectPendingRequest(
    _ request: UNNotificationRequest
  ) -> ReminderPendingRequest? {
    guard request.identifier.hasPrefix(ReminderPlanner.identifierPrefix) else {
      return nil
    }
    let trigger = request.trigger as? UNCalendarNotificationTrigger
    let dateComponents =
      trigger?.repeats == false
      ? trigger?.dateComponents
      : nil
    return ReminderPendingRequest(
      identifier: request.identifier,
      title: request.content.title,
      body: request.content.body,
      usesDefaultSound: request.content.sound == .default,
      categoryIdentifier: request.content.categoryIdentifier,
      hasOwnershipMarker:
        request.content.userInfo[ReminderPendingRequest.ownershipKey] as? Bool
        == true,
      badge: request.content.badge?.intValue,
      dateComponents: dateComponents
    )
  }
}
