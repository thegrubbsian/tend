import SwiftUI

struct TendRootView: View {
  let reminders: any ReminderRuntimeClient
  let routing: ReminderRoutingModel

  var body: some View {
    AlmanacShellView(reminders: reminders, routing: routing)
  }
}
