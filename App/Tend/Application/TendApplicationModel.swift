import Observation
import SwiftData
import TendCore

typealias ModelContainerFactory = @MainActor () throws -> ModelContainer

enum TendApplicationState {
  case ready(ModelContainer)
  case failed
}

@MainActor
@Observable
final class TendApplicationModel {
  private let makeContainer: ModelContainerFactory

  private(set) var state: TendApplicationState = .failed
  private(set) var diagnosticError: (any Error)?

  init(
    makeContainer: @escaping ModelContainerFactory = TendModelContainer.production
  ) {
    self.makeContainer = makeContainer
    openStore()
  }

  func retry() {
    openStore()
  }

  private func openStore() {
    do {
      let container = try makeContainer()
      diagnosticError = nil
      state = .ready(container)
    } catch {
      diagnosticError = error
      state = .failed
    }
  }
}
