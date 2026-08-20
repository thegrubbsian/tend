import SwiftUI

struct TendRootView: View {
  let reminders: any ReminderRuntimeClient
  let routing: ShellRoutingModel

  var body: some View {
    AlmanacShellView(reminders: reminders, routing: routing)
  }
}
