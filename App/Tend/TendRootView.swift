import Foundation
import SwiftUI

struct TendRootView: View {
  let reminders: any ReminderRuntimeClient
  let routing: ShellRoutingModel

  @ViewBuilder
  var body: some View {
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      if JournalEditorUITestHarnessArguments.isEnabled(arguments) {
        JournalEditorUITestHarness(
          routing: routing,
          instant: TendUITestStore.fixedInstant(arguments: arguments) ?? .now,
          failsSaves: arguments.contains(JournalEditorUITestHarnessArguments.failSave)
        )
      } else {
        AlmanacShellView(reminders: reminders, routing: routing)
      }
    #else
      AlmanacShellView(reminders: reminders, routing: routing)
    #endif
  }
}
