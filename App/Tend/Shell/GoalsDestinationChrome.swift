import SwiftData
import SwiftUI

struct GoalsDestinationChrome: View {
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    GoalRosterView(context: modelContext)
      .accessibilityIdentifier("shell.destination.goals")
  }
}
