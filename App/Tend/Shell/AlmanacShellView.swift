import SwiftUI

struct AlmanacShellView: View {
  let reminders: any ReminderRuntimeClient
  let routing: ReminderRoutingModel
  @AccessibilityFocusState private var accessibilityFocus: ShellDestination?

  var body: some View {
    @Bindable var routing = routing
    destination
      .safeAreaInset(edge: .bottom, spacing: 0) {
        FloatingTabPill(selection: $routing.selection)
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
