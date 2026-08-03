import Foundation

public struct HabitDetailMonthRange: Equatable, Sendable {
  public let earliest: Date
  public let selected: Date
  public let latest: Date

  public init(earliest: Date, selected: Date, latest: Date) {
    self.earliest = earliest
    self.selected = selected
    self.latest = latest
  }
}

public enum HabitHistoryState: Equatable, Sendable {
  case met
  case missed
  case open
  case grace
  case inactive
  case beforeCreation
  case future
}

public struct HabitHistoryPeriod: Equatable, Sendable {
  public let key: String
  public let start: Date
  public let end: Date
  public let state: HabitHistoryState
  public let progress: Int?
  public let target: Int?
  public let unit: String?
  public let isRequirementMet: Bool?

  public init(
    key: String,
    start: Date,
    end: Date,
    state: HabitHistoryState,
    progress: Int? = nil,
    target: Int? = nil,
    unit: String? = nil,
    isRequirementMet: Bool? = nil
  ) {
    self.key = key
    self.start = start
    self.end = end
    self.state = state
    self.progress = progress
    self.target = target
    self.unit = unit
    self.isRequirementMet = isRequirementMet
  }
}

public struct HabitEditableEntry: Equatable, Sendable {
  public let id: UUID
  public let timestamp: Date
  public let amount: Int
  public let bucketKey: String
  public let unit: String
  public let bucketStart: Date
  public let bucketEnd: Date

  public init(
    id: UUID,
    timestamp: Date,
    amount: Int,
    bucketKey: String,
    unit: String,
    bucketStart: Date,
    bucketEnd: Date
  ) {
    self.id = id
    self.timestamp = timestamp
    self.amount = amount
    self.bucketKey = bucketKey
    self.unit = unit
    self.bucketStart = bucketStart
    self.bucketEnd = bucketEnd
  }
}

public struct HabitDetailSnapshot: Equatable, Sendable {
  public let habitID: UUID
  public let cadence: HabitCadence
  public let monthRange: HabitDetailMonthRange
  public let streak: HabitStreakState
  public let history: [HabitHistoryPeriod]
  public let editableEntries: [HabitEditableEntry]

  public init(
    habitID: UUID,
    cadence: HabitCadence,
    monthRange: HabitDetailMonthRange,
    streak: HabitStreakState,
    history: [HabitHistoryPeriod],
    editableEntries: [HabitEditableEntry]
  ) {
    self.habitID = habitID
    self.cadence = cadence
    self.monthRange = monthRange
    self.streak = streak
    self.history = history
    self.editableEntries = editableEntries
  }
}
