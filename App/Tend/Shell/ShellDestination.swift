enum ShellDestination: String, CaseIterable, Identifiable {
  case today = "Today"
  case goals = "Goals"
  case habits = "Habits"

  var id: Self { self }

  var tabAccessibilityIdentifier: String {
    switch self {
    case .today:
      "shell.tab.today"
    case .goals:
      "shell.tab.goals"
    case .habits:
      "shell.tab.habits"
    }
  }
}
