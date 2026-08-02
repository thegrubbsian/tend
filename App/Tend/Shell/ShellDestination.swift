enum ShellDestination: String, CaseIterable, Identifiable {
  case today = "Today"
  case habits = "Habits"

  var id: Self { self }

  var tabAccessibilityIdentifier: String {
    switch self {
    case .today:
      "shell.tab.today"
    case .habits:
      "shell.tab.habits"
    }
  }
}
