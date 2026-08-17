public enum GoalClosure: String, Equatable, Sendable {
  case harvested
  case letGo
}

public enum GoalClosureError: Error, Equatable, Sendable {
  case unsupportedRawValue(String)
}
