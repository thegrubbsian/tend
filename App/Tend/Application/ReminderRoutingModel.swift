import Observation

@MainActor
@Observable
final class ReminderRoutingModel {
  var selection: ShellDestination

  init(selection: ShellDestination = .today) {
    self.selection = selection
  }

  func showToday() {
    selection = .today
  }
}
