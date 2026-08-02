import SwiftUI

struct HabitsDestinationChrome: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Habits")
        .almanacTextStyle(.screenTitle)

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Habits")
    .accessibilityIdentifier("shell.destination.habits")
  }
}
