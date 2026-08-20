import Observation
import TendCore

struct ShellNavigationGuardToken: Equatable, Sendable {
  fileprivate let rawValue: UInt64
}

@MainActor
@Observable
final class ShellRoutingModel {
  private(set) var selection: ShellDestination
  private(set) var journalRoute: JournalRoute

  @ObservationIgnored private var navigationGuard: NavigationGuard?
  @ObservationIgnored private var nextGuardID: UInt64 = 0
  @ObservationIgnored private var requestGeneration: UInt64 = 0

  init(
    selection: ShellDestination = .today,
    journalRoute: JournalRoute = .overview
  ) {
    self.selection = selection
    self.journalRoute = journalRoute
  }

  @discardableResult
  func requestSelection(_ destination: ShellDestination) async -> Bool {
    requestGeneration &+= 1
    let generation = requestGeneration
    guard destination != selection else { return true }

    if let navigationGuard {
      guard await navigationGuard.operation() else { return false }
      guard generation == requestGeneration else { return false }
    }
    guard generation == requestGeneration else { return false }
    selection = destination
    return true
  }

  func prepareJournalRoute(_ route: JournalRoute) {
    guard route != journalRoute else { return }
    journalRoute = route
  }

  func resolveJournalEntry(using query: JournalEntryQuery) throws -> JournalEntry? {
    guard case .entry(let id) = journalRoute else { return nil }
    let entry = try query.entries().first { $0.id == id }
    if entry == nil {
      journalRoute = .overview
    }
    return entry
  }

  func installNavigationGuard(
    _ operation: @escaping @MainActor () async -> Bool
  ) -> ShellNavigationGuardToken {
    nextGuardID &+= 1
    let token = ShellNavigationGuardToken(rawValue: nextGuardID)
    navigationGuard = NavigationGuard(token: token, operation: operation)
    return token
  }

  func removeNavigationGuard(_ token: ShellNavigationGuardToken) {
    guard navigationGuard?.token == token else { return }
    navigationGuard = nil
  }

  @discardableResult
  func showToday() async -> Bool {
    await requestSelection(.today)
  }
}

private struct NavigationGuard {
  let token: ShellNavigationGuardToken
  let operation: @MainActor () async -> Bool
}
