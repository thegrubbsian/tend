import SwiftUI

struct AlmanacShellView: View {
  let reminders: any ReminderRuntimeClient
  let routing: ShellRoutingModel
  @AccessibilityFocusState private var accessibilityFocus: ShellDestination?

  var body: some View {
    destination
      .safeAreaInset(edge: .bottom, spacing: 0) {
        FloatingTabPill(selection: routing.selection) { destination in
          let request = routing.beginSelectionRequest(destination)
          Task { _ = await routing.completeSelectionRequest(request) }
        }
        .frame(maxWidth: AlmanacMetrics.tabPillMaximumWidth)
        .padding(.horizontal, AlmanacMetrics.tabPillEdgeInset)
        .padding(.bottom, AlmanacMetrics.tabPillEdgeInset)
      }
      .onChange(of: routing.selection) { _, newSelection in
        accessibilityFocus = newSelection
      }
  }

  @ViewBuilder
  private var destination: some View {
    switch routing.selection {
    case .today:
      TodayDestinationChrome(reminders: reminders)
        .accessibilityFocused($accessibilityFocus, equals: .today)
    case .goals:
      GoalsDestinationChrome()
        .accessibilityFocused($accessibilityFocus, equals: .goals)
    case .habits:
      HabitsDestinationChrome(reminders: reminders)
        .accessibilityFocused($accessibilityFocus, equals: .habits)
    }
  }
}
