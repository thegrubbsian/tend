import SwiftData
import SwiftUI

@main
struct TendApp: App {
  @State private var applicationModel = TendApplicationModel()

  var body: some Scene {
    WindowGroup {
      TendApplicationRoot(model: applicationModel)
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
