import SwiftData
import SwiftUI

struct HabitsDestinationChrome: View {
  @Environment(\.modelContext) private var modelContext
  let reminders: any ReminderRuntimeClient

  var body: some View {
    HabitRosterView(
      context: modelContext,
      reminders: reminders
    )
    .accessibilityIdentifier("shell.destination.habits")
  }
}
