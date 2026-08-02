import SwiftUI

struct AlmanacShellView: View {
  @State private var selection: ShellDestination = .today
  @AccessibilityFocusState private var accessibilityFocus: ShellDestination?

  var body: some View {
    destination
      .safeAreaInset(edge: .bottom, spacing: 0) {
        FloatingTabPill(selection: $selection)
          .frame(maxWidth: AlmanacMetrics.tabPillMaximumWidth)
          .padding(.horizontal, AlmanacMetrics.tabPillEdgeInset)
          .padding(.bottom, AlmanacMetrics.tabPillEdgeInset)
      }
      .onChange(of: selection) { _, newSelection in
        accessibilityFocus = newSelection
      }
  }

  @ViewBuilder
  private var destination: some View {
    switch selection {
    case .today:
      TodayDestinationChrome()
        .accessibilityFocused($accessibilityFocus, equals: .today)
    case .habits:
      HabitsDestinationChrome()
        .accessibilityFocused($accessibilityFocus, equals: .habits)
    }
  }
}
