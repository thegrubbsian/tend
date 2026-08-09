import Observation

@MainActor
@Observable
final class ReminderRoutingModel {
  var selection: ShellDestination = .today
}
