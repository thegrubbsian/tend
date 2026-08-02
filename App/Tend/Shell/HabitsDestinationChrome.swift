import SwiftData
import SwiftUI

struct HabitsDestinationChrome: View {
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    HabitRosterView(context: modelContext)
      .accessibilityIdentifier("shell.destination.habits")
  }
}
