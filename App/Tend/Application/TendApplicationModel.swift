import Observation
import SwiftData
import TendCore

typealias ModelContainerFactory = @MainActor () throws -> ModelContainer
typealias ReminderRuntimeFactory =
  @MainActor (ModelContainer) -> any ReminderRuntimeClient

struct TendApplicationReadyState {
  let container: ModelContainer
  let reminders: any ReminderRuntimeClient
}

enum TendApplicationState {
  case ready(TendApplicationReadyState)
  case failed
}

@MainActor
@Observable
final class TendApplicationModel {
  private let makeContainer: ModelContainerFactory
  private let makeReminderRuntime: ReminderRuntimeFactory

  private(set) var state: TendApplicationState = .failed
  private(set) var diagnosticError: (any Error)?

  var readyState: TendApplicationReadyState? {
    guard case .ready(let ready) = state else { return nil }
    return ready
  }

  init(
    makeContainer: @escaping ModelContainerFactory,
    makeReminderRuntime: @escaping ReminderRuntimeFactory
  ) {
    self.makeContainer = makeContainer
    self.makeReminderRuntime = makeReminderRuntime
    openStore()
  }

  convenience init(
    makeContainer: @escaping ModelContainerFactory = TendModelContainer.production
  ) {
    self.init(
      makeContainer: makeContainer,
      makeReminderRuntime: { _ in DisabledReminderRuntime() }
    )
  }

  func retry() {
    openStore()
  }

  func sceneDidBecomeActive() {
    readyState?.reminders.refresh()
  }

  private func openStore() {
    do {
      let container = try makeContainer()
      let reminders = makeReminderRuntime(container)
      diagnosticError = nil
      state = .ready(
        TendApplicationReadyState(
          container: container,
          reminders: reminders
        )
      )
      reminders.refresh()
    } catch {
      diagnosticError = error
      state = .failed
    }
  }
}
