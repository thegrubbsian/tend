import Foundation
import SwiftData
import SwiftUI
import TendCore

@main
struct TendApp: App {
  @State private var applicationModel: TendApplicationModel

  init() {
    #if DEBUG
      let makeContainer =
        TendUITestStore.containerFactory(
          arguments: ProcessInfo.processInfo.arguments
        ) ?? TendModelContainer.production
    #else
      let makeContainer: ModelContainerFactory = TendModelContainer.production
    #endif
    _applicationModel = State(
      initialValue: TendApplicationModel(makeContainer: makeContainer)
    )
  }

  var body: some Scene {
    WindowGroup {
      TendApplicationRoot(model: applicationModel)
        .tint(AlmanacPalette.moss)
    }
  }
}

private struct TendApplicationRoot: View {
  let model: TendApplicationModel

  var body: some View {
    switch model.state {
    case .ready(let container):
      TendRootView()
        .modelContainer(container)
    case .failed:
      StoreFailureView(retry: model.retry)
    }
  }
}
