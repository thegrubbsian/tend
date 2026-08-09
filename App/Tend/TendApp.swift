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
    let routing = ReminderRoutingModel()
    let notificationCenter = LiveReminderNotificationCenter()
    _applicationModel = State(
      initialValue: TendApplicationModel(
        makeContainer: makeContainer,
        makeReminderRuntime: { container in
          ReminderAppRuntime(
            container: container,
            notificationCenter: notificationCenter,
            routing: routing
          )
        }
      )
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
  @Environment(\.scenePhase) private var scenePhase
  let model: TendApplicationModel

  var body: some View {
    Group {
      switch model.state {
      case .ready(let ready):
        TendRootView()
          .modelContainer(ready.container)
      case .failed:
        StoreFailureView(retry: model.retry)
      }
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      model.sceneDidBecomeActive()
    }
  }
}
