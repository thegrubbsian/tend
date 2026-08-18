import SwiftData
import SwiftUI

#if DEBUG
  import Foundation
#endif

struct GoalsDestinationChrome: View {
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    Group {
      #if DEBUG
        GoalRosterView(
          context: modelContext,
          fixedInstant: TendUITestStore.fixedInstant(
            arguments: ProcessInfo.processInfo.arguments
          )
        )
      #else
        GoalRosterView(context: modelContext)
      #endif
    }
    .accessibilityIdentifier("shell.destination.goals")
  }
}
