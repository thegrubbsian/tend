enum ShellDestination: String, CaseIterable, Identifiable {
  case today = "Today"
  case goals = "Goals"
  case habits = "Habits"
  case journal = "Journal"

  var id: Self { self }

  var tabAccessibilityIdentifier: String {
    switch self {
    case .today:
      "shell.tab.today"
    case .goals:
      "shell.tab.goals"
    case .habits:
      "shell.tab.habits"
    case .journal:
      "shell.tab.journal"
    }
  }
}
