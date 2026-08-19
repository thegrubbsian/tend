import Foundation
import SwiftData

public struct GoalEditableFields: Equatable, Sendable {
  public let name: String
  public let target: Int
  public let unit: String
  public let baseline: Int?
  public let deadline: LocalDate?

  public init(
    name: String,
    target: Int,
    unit: String = "times",
    baseline: Int? = nil,
    deadline: LocalDate? = nil
  ) {
    self.name = name
    self.target = target
    self.unit = unit
    self.baseline = baseline
    self.deadline = deadline
  }
}

public enum GoalManagementOperationError: Error, Equatable, Sendable {
  case emptyName
  case invalidTarget(Int)
  case emptyUnit
  case accumulateBaseline(Int)
  case missingMeasureBaseline
  case measureBaselineEqualsTarget(Int)
  case invalidGoalKind(String)
  case invalidClosure(String)
  case invalidDeadlineBoundary(LocalDateError)
  case deadlineNotAfterCreation(LocalDate)
  case detachedGoal
  case deletedGoal
  case foreignGoal
  case missingEntries
  case missingReadings
  case invalidGoalGraph
}

@MainActor
public final class GoalManagementOperations {
  private let context: ModelContext
  private let saveContext: () throws -> Void

  public init(context: ModelContext) {
    self.context = context
    saveContext = { try context.save() }
  }

  init(context: ModelContext, save: @escaping () throws -> Void) {
    self.context = context
    saveContext = save
  }

  public func update(
    _ goal: Goal,
    fields: GoalEditableFields,
    calendar: Calendar,
    timeZone: TimeZone
  ) throws {
    try requirePersisted(goal)
    let kind = try validatedEnums(of: goal)
    let fields = try validated(
      fields,
      for: kind,
      createdAt: goal.createdAt,
      calendar: calendar,
      timeZone: timeZone
    )
    let prior = GoalManagementEditableFacts(goal)

    goal.name = fields.name
    goal.target = fields.target
    goal.unit = fields.unit
    goal.baseline = fields.baseline
    goal.deadlineKey = fields.deadline?.rawValue

    do {
      try saveContext()
    } catch {
      prior.restore(goal)
      context.processPendingChanges()
      throw error
    }
  }

  public func delete(_ goal: Goal) throws {
    let graph = try validatedGraph(for: goal)
    context.delete(goal)
    context.processPendingChanges()

    do {
      try saveContext()
    } catch {
      restore(graph, to: goal)
      throw error
    }
  }

  private func validated(
    _ fields: GoalEditableFields,
    for kind: GoalKind,
    createdAt: Date,
    calendar: Calendar,
    timeZone: TimeZone
  ) throws -> GoalEditableFields {
    let name = normalized(fields.name)
    guard !name.isEmpty else {
      throw GoalManagementOperationError.emptyName
    }
    guard fields.target > 0 else {
      throw GoalManagementOperationError.invalidTarget(fields.target)
    }
    let unit = normalized(fields.unit)
    guard !unit.isEmpty else {
      throw GoalManagementOperationError.emptyUnit
    }

    switch kind {
    case .accumulate:
      if let baseline = fields.baseline {
        throw GoalManagementOperationError.accumulateBaseline(baseline)
      }
    case .measure:
      guard let baseline = fields.baseline else {
        throw GoalManagementOperationError.missingMeasureBaseline
      }
      guard baseline != fields.target else {
        throw GoalManagementOperationError.measureBaselineEqualsTarget(baseline)
      }
    }

    if let deadline = fields.deadline {
      let followingDayStart: Date
      do {
        followingDayStart = try deadline.next().start(in: timeZone)
      } catch let error as LocalDateError {
        throw GoalManagementOperationError.invalidDeadlineBoundary(error)
      }
      var localCalendar = calendar
      localCalendar.timeZone = timeZone
      let boundary = localCalendar.startOfDay(for: followingDayStart)
      guard boundary.timeIntervalSinceReferenceDate.isFinite else {
        throw GoalManagementOperationError.invalidDeadlineBoundary(.calendarCalculationFailed)
      }
      guard boundary > createdAt else {
        throw GoalManagementOperationError.deadlineNotAfterCreation(deadline)
      }
    }

    return GoalEditableFields(
      name: name,
      target: fields.target,
      unit: unit,
      baseline: fields.baseline,
      deadline: fields.deadline
    )
  }

  private func validatedGraph(for goal: Goal) throws -> GoalManagementGraph {
    try requirePersisted(goal)
    _ = try validatedEnums(of: goal)
    guard let entries = goal.entries else {
      throw GoalManagementOperationError.missingEntries
    }
    guard let readings = goal.readings else {
      throw GoalManagementOperationError.missingReadings
    }

    let goalIdentifier = goal.persistentModelID
    let fetchedEntries = try context.fetch(
      FetchDescriptor<GoalEntry>(
        predicate: #Predicate<GoalEntry> { entry in
          entry.goal?.persistentModelID == goalIdentifier
        }
      )
    )
    let fetchedReadings = try context.fetch(
      FetchDescriptor<GoalReading>(
        predicate: #Predicate<GoalReading> { reading in
          reading.goal?.persistentModelID == goalIdentifier
        }
      )
    )

    guard
      identities(entries) == identities(fetchedEntries),
      identities(readings) == identities(fetchedReadings),
      Set(entries.map(\.persistentModelID)).count == entries.count,
      Set(readings.map(\.persistentModelID)).count == readings.count
    else {
      throw GoalManagementOperationError.invalidGoalGraph
    }
    for entry in entries {
      guard isPersisted(entry), entry.goal === goal else {
        throw GoalManagementOperationError.invalidGoalGraph
      }
    }
    for reading in readings {
      guard isPersisted(reading), reading.goal === goal else {
        throw GoalManagementOperationError.invalidGoalGraph
      }
    }

    return GoalManagementGraph(
      goal: GoalManagementGoalFacts(goal),
      entries: entries.map { GoalManagementEntryRecord(model: $0) },
      readings: readings.map { GoalManagementReadingRecord(model: $0) }
    )
  }

  private func restore(_ graph: GoalManagementGraph, to goal: Goal) {
    context.insert(goal)
    graph.goal.restore(goal)

    for record in graph.entries {
      context.insert(record.model)
      record.facts.restore(record.model)
      record.model.goal = goal
    }
    for record in graph.readings {
      context.insert(record.model)
      record.facts.restore(record.model)
      record.model.goal = goal
    }
    goal.entries = graph.entries.map(\.model)
    goal.readings = graph.readings.map(\.model)
    context.processPendingChanges()
  }

  private func requirePersisted(_ goal: Goal) throws {
    if goal.modelContext === context {
      guard !goal.isDeleted else {
        throw GoalManagementOperationError.deletedGoal
      }
      guard goal.persistentModelID.storeIdentifier != nil else {
        throw GoalManagementOperationError.detachedGoal
      }
      return
    }
    if goal.modelContext != nil {
      throw GoalManagementOperationError.foreignGoal
    }
    if goal.persistentModelID.storeIdentifier != nil {
      throw GoalManagementOperationError.deletedGoal
    }
    throw GoalManagementOperationError.detachedGoal
  }

  private func validatedEnums(of goal: Goal) throws -> GoalKind {
    guard let kind = GoalKind(rawValue: goal.kindRawValue) else {
      throw GoalManagementOperationError.invalidGoalKind(goal.kindRawValue)
    }
    do {
      _ = try goal.checkedClosure
    } catch GoalClosureError.unsupportedRawValue(let rawValue) {
      throw GoalManagementOperationError.invalidClosure(rawValue)
    }
    return kind
  }

  private func isPersisted<T>(_ model: T) -> Bool where T: PersistentModel {
    model.modelContext === context && model.persistentModelID.storeIdentifier != nil
      && !model.isDeleted
  }

  private func identities<T>(_ models: [T]) -> Set<PersistentIdentifier>
  where T: PersistentModel {
    Set(models.map(\.persistentModelID))
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private struct GoalManagementEditableFacts {
  let name: String
  let target: Int
  let unit: String
  let baseline: Int?
  let deadlineKey: String?

  init(_ goal: Goal) {
    name = goal.name
    target = goal.target
    unit = goal.unit
    baseline = goal.baseline
    deadlineKey = goal.deadlineKey
  }

  func restore(_ goal: Goal) {
    goal.name = name
    goal.target = target
    goal.unit = unit
    goal.baseline = baseline
    goal.deadlineKey = deadlineKey
  }
}

private struct GoalManagementGraph {
  let goal: GoalManagementGoalFacts
  let entries: [GoalManagementEntryRecord]
  let readings: [GoalManagementReadingRecord]
}

private struct GoalManagementGoalFacts {
  let id: UUID
  let name: String
  let kindRawValue: String
  let target: Int
  let unit: String
  let baseline: Int?
  let deadlineKey: String?
  let createdAt: Date
  let closureRawValue: String?

  init(_ goal: Goal) {
    id = goal.id
    name = goal.name
    kindRawValue = goal.kindRawValue
    target = goal.target
    unit = goal.unit
    baseline = goal.baseline
    deadlineKey = goal.deadlineKey
    createdAt = goal.createdAt
    closureRawValue = goal.closureRawValue
  }

  func restore(_ goal: Goal) {
    goal.id = id
    goal.name = name
    goal.kindRawValue = kindRawValue
    goal.target = target
    goal.unit = unit
    goal.baseline = baseline
    goal.deadlineKey = deadlineKey
    goal.createdAt = createdAt
    goal.closureRawValue = closureRawValue
  }
}

private struct GoalManagementEntryRecord {
  let model: GoalEntry
  let facts: GoalManagementEntryFacts

  init(model: GoalEntry) {
    self.model = model
    facts = GoalManagementEntryFacts(model)
  }
}

private struct GoalManagementEntryFacts {
  let id: UUID
  let amount: Int
  let assignedDateKey: String
  let appendedAt: Date
  let appendSequence: Int

  init(_ entry: GoalEntry) {
    id = entry.id
    amount = entry.amount
    assignedDateKey = entry.assignedDateKey
    appendedAt = entry.appendedAt
    appendSequence = entry.appendSequence
  }

  func restore(_ entry: GoalEntry) {
    entry.id = id
    entry.amount = amount
    entry.assignedDateKey = assignedDateKey
    entry.appendedAt = appendedAt
    entry.appendSequence = appendSequence
  }
}

private struct GoalManagementReadingRecord {
  let model: GoalReading
  let facts: GoalManagementReadingFacts

  init(model: GoalReading) {
    self.model = model
    facts = GoalManagementReadingFacts(model)
  }
}

private struct GoalManagementReadingFacts {
  let id: UUID
  let value: Int
  let assignedDateKey: String
  let appendedAt: Date
  let appendSequence: Int

  init(_ reading: GoalReading) {
    id = reading.id
    value = reading.value
    assignedDateKey = reading.assignedDateKey
    appendedAt = reading.appendedAt
    appendSequence = reading.appendSequence
  }

  func restore(_ reading: GoalReading) {
    reading.id = id
    reading.value = value
    reading.assignedDateKey = assignedDateKey
    reading.appendedAt = appendedAt
    reading.appendSequence = appendSequence
  }
}
