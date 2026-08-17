import Foundation
import SwiftData

public enum GoalProgressDestination: Equatable, Sendable {
  case today
  case yesterday
}

public enum GoalProgressOperationError: Error, Equatable, Sendable {
  case invalidAmount(Int)
  case detachedGoal
  case foreignGoal
  case closedGoal(GoalClosure)
  case invalidClosure(String)
  case detachedEntry
  case foreignEntry
  case detachedReading
  case foreignReading
  case wrongGoalKind(required: GoalKind, actualRawValue: String)
  case invalidGoalConfiguration
  case invalidDeadline(String)
  case missingEntries
  case missingReadings
  case invalidGoalGraph
  case invalidAssignedDate(String)
  case invalidExistingAmount(Int)
  case invalidSequence(Int)
  case duplicateSequence(Int)
  case sequenceOverflow
  case destinationBeforeCreation(GoalDate)
  case childNotFound
  case destinationNotEditable(GoalDate)
}

@MainActor
public final class GoalProgressOperations {
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

  @discardableResult
  public func append(
    amount: Int,
    to goal: Goal,
    destination: GoalProgressDestination,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> GoalEntry {
    guard amount > 0 else {
      throw GoalProgressOperationError.invalidAmount(amount)
    }
    let graph = try validatedGraph(for: goal, requiredKind: .accumulate)
    let sequence = try nextSequence(graph.entries.map(\.appendSequence))
    let assignedDate = try resolvedDestination(
      destination,
      for: goal,
      at: instant,
      timeZone: timeZone
    )
    let priorEntries = graph.entries
    let entry = GoalEntry(
      amount: amount,
      assignedDate: assignedDate,
      appendedAt: instant,
      appendSequence: sequence,
      goal: goal
    )
    context.insert(entry)
    goal.entries = priorEntries + [entry]

    do {
      try saveContext()
      return entry
    } catch {
      goal.entries = priorEntries
      entry.goal = nil
      context.delete(entry)
      context.processPendingChanges()
      throw error
    }
  }

  @discardableResult
  public func append(
    value: Int,
    to goal: Goal,
    destination: GoalProgressDestination,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> GoalReading {
    let graph = try validatedGraph(for: goal, requiredKind: .measure)
    let sequence = try nextSequence(graph.readings.map(\.appendSequence))
    let assignedDate = try resolvedDestination(
      destination,
      for: goal,
      at: instant,
      timeZone: timeZone
    )
    let priorReadings = graph.readings
    let reading = GoalReading(
      value: value,
      assignedDate: assignedDate,
      appendedAt: instant,
      appendSequence: sequence,
      goal: goal
    )
    context.insert(reading)
    goal.readings = priorReadings + [reading]

    do {
      try saveContext()
      return reading
    } catch {
      goal.readings = priorReadings
      reading.goal = nil
      context.delete(reading)
      context.processPendingChanges()
      throw error
    }
  }

  public func delete(
    _ entry: GoalEntry,
    from goal: Goal,
    at instant: Date,
    timeZone: TimeZone
  ) throws {
    let graph = try validatedGraph(for: goal, requiredKind: .accumulate)
    try requirePersisted(entry)
    guard let index = graph.entries.firstIndex(where: { $0 === entry }) else {
      throw GoalProgressOperationError.childNotFound
    }
    guard entry.goal === goal else {
      throw GoalProgressOperationError.invalidGoalGraph
    }
    let assignedDate = try parsedDate(entry.assignedDateKey)
    try authorizeDeletion(of: assignedDate, at: instant, timeZone: timeZone)

    let priorEntries = graph.entries
    let facts = EntryFacts(entry)
    var remaining = priorEntries
    remaining.remove(at: index)
    goal.entries = remaining
    entry.goal = nil
    context.delete(entry)
    context.processPendingChanges()

    do {
      try saveContext()
    } catch {
      context.insert(entry)
      facts.restore(entry)
      entry.goal = goal
      goal.entries = priorEntries
      context.processPendingChanges()
      throw error
    }
  }

  public func delete(
    _ reading: GoalReading,
    from goal: Goal,
    at instant: Date,
    timeZone: TimeZone
  ) throws {
    let graph = try validatedGraph(for: goal, requiredKind: .measure)
    try requirePersisted(reading)
    guard let index = graph.readings.firstIndex(where: { $0 === reading }) else {
      throw GoalProgressOperationError.childNotFound
    }
    guard reading.goal === goal else {
      throw GoalProgressOperationError.invalidGoalGraph
    }
    let assignedDate = try parsedDate(reading.assignedDateKey)
    try authorizeDeletion(of: assignedDate, at: instant, timeZone: timeZone)

    let priorReadings = graph.readings
    let facts = ReadingFacts(reading)
    var remaining = priorReadings
    remaining.remove(at: index)
    goal.readings = remaining
    reading.goal = nil
    context.delete(reading)
    context.processPendingChanges()

    do {
      try saveContext()
    } catch {
      context.insert(reading)
      facts.restore(reading)
      reading.goal = goal
      goal.readings = priorReadings
      context.processPendingChanges()
      throw error
    }
  }

  private func validatedGraph(
    for goal: Goal,
    requiredKind: GoalKind
  ) throws -> GoalGraph {
    try requirePersisted(goal)
    try requireOpen(goal)
    let kind = try validatedConfiguration(goal)
    guard kind == requiredKind else {
      throw GoalProgressOperationError.wrongGoalKind(
        required: requiredKind,
        actualRawValue: goal.kindRawValue
      )
    }
    guard let entries = goal.entries else {
      throw GoalProgressOperationError.missingEntries
    }
    guard let readings = goal.readings else {
      throw GoalProgressOperationError.missingReadings
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
      throw GoalProgressOperationError.invalidGoalGraph
    }

    for entry in entries {
      guard isPersisted(entry), entry.goal === goal else {
        throw GoalProgressOperationError.invalidGoalGraph
      }
      guard entry.amount > 0 else {
        throw GoalProgressOperationError.invalidExistingAmount(entry.amount)
      }
      _ = try parsedDate(entry.assignedDateKey)
    }
    for reading in readings {
      guard isPersisted(reading), reading.goal === goal else {
        throw GoalProgressOperationError.invalidGoalGraph
      }
      _ = try parsedDate(reading.assignedDateKey)
    }

    switch kind {
    case .accumulate where !readings.isEmpty:
      throw GoalProgressOperationError.invalidGoalGraph
    case .measure where !entries.isEmpty:
      throw GoalProgressOperationError.invalidGoalGraph
    case .accumulate, .measure:
      break
    }

    let relevantSequences =
      kind == .accumulate
      ? entries.map(\.appendSequence)
      : readings.map(\.appendSequence)
    try validateSequences(relevantSequences)
    return GoalGraph(entries: entries, readings: readings)
  }

  private func requireOpen(_ goal: Goal) throws {
    let closure: GoalClosure?
    do {
      closure = try goal.checkedClosure
    } catch GoalClosureError.unsupportedRawValue(let rawValue) {
      throw GoalProgressOperationError.invalidClosure(rawValue)
    }
    if let closure {
      throw GoalProgressOperationError.closedGoal(closure)
    }
  }

  private func validatedConfiguration(_ goal: Goal) throws -> GoalKind {
    let normalizedName = normalized(goal.name)
    let normalizedUnit = normalized(goal.unit)
    guard
      !normalizedName.isEmpty,
      normalizedName == goal.name,
      goal.target > 0,
      !normalizedUnit.isEmpty,
      normalizedUnit == goal.unit,
      let kind = GoalKind(rawValue: goal.kindRawValue)
    else {
      throw GoalProgressOperationError.invalidGoalConfiguration
    }

    switch kind {
    case .accumulate:
      guard goal.baseline == nil else {
        throw GoalProgressOperationError.invalidGoalConfiguration
      }
    case .measure:
      guard let baseline = goal.baseline, baseline != goal.target else {
        throw GoalProgressOperationError.invalidGoalConfiguration
      }
    }
    if let deadlineKey = goal.deadlineKey, GoalDate(rawValue: deadlineKey) == nil {
      throw GoalProgressOperationError.invalidDeadline(deadlineKey)
    }
    return kind
  }

  private func resolvedDestination(
    _ destination: GoalProgressDestination,
    for goal: Goal,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> GoalDate {
    let window: GoalProgressLocalDayWindow
    do {
      window = try GoalProgressLocalDayEligibility.window(
        createdAt: goal.createdAt,
        at: instant,
        timeZone: timeZone
      )
    } catch {
      throw GoalProgressOperationError.invalidGoalConfiguration
    }
    let assignedDate = try window.assignedDate(for: destination)
    guard assignedDate >= window.creationDate else {
      throw GoalProgressOperationError.destinationBeforeCreation(assignedDate)
    }
    return assignedDate
  }

  private func authorizeDeletion(
    of assignedDate: GoalDate,
    at instant: Date,
    timeZone: TimeZone
  ) throws {
    let editableDays: GoalProgressEditableDays
    do {
      editableDays = try GoalProgressLocalDayEligibility.editableDays(
        at: instant,
        timeZone: timeZone
      )
    } catch {
      throw GoalProgressOperationError.invalidGoalConfiguration
    }
    guard try editableDays.contains(assignedDate) else {
      throw GoalProgressOperationError.destinationNotEditable(assignedDate)
    }
  }


  private func parsedDate(_ key: String) throws -> GoalDate {
    guard let date = GoalDate(rawValue: key) else {
      throw GoalProgressOperationError.invalidAssignedDate(key)
    }
    return date
  }

  private func validateSequences(_ sequences: [Int]) throws {
    var observed = Set<Int>()
    observed.reserveCapacity(sequences.count)
    for sequence in sequences {
      guard sequence >= 0 else {
        throw GoalProgressOperationError.invalidSequence(sequence)
      }
      guard observed.insert(sequence).inserted else {
        throw GoalProgressOperationError.duplicateSequence(sequence)
      }
    }
  }

  private func nextSequence(_ sequences: [Int]) throws -> Int {
    try validateSequences(sequences)
    guard let maximum = sequences.max() else {
      return 0
    }
    let next = maximum.addingReportingOverflow(1)
    guard !next.overflow else {
      throw GoalProgressOperationError.sequenceOverflow
    }
    return next.partialValue
  }

  private func requirePersisted(_ goal: Goal) throws {
    guard let modelContext = goal.modelContext else {
      throw GoalProgressOperationError.detachedGoal
    }
    guard modelContext === context else {
      throw GoalProgressOperationError.foreignGoal
    }
    guard goal.persistentModelID.storeIdentifier != nil, !goal.isDeleted else {
      throw GoalProgressOperationError.detachedGoal
    }
  }

  private func requirePersisted(_ entry: GoalEntry) throws {
    guard let modelContext = entry.modelContext else {
      throw GoalProgressOperationError.detachedEntry
    }
    guard modelContext === context else {
      throw GoalProgressOperationError.foreignEntry
    }
    guard entry.persistentModelID.storeIdentifier != nil, !entry.isDeleted else {
      throw GoalProgressOperationError.detachedEntry
    }
  }

  private func requirePersisted(_ reading: GoalReading) throws {
    guard let modelContext = reading.modelContext else {
      throw GoalProgressOperationError.detachedReading
    }
    guard modelContext === context else {
      throw GoalProgressOperationError.foreignReading
    }
    guard reading.persistentModelID.storeIdentifier != nil, !reading.isDeleted else {
      throw GoalProgressOperationError.detachedReading
    }
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

private struct GoalGraph {
  let entries: [GoalEntry]
  let readings: [GoalReading]
}

private struct EntryFacts {
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

private struct ReadingFacts {
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

enum GoalProgressLocalDayEligibility {
  static func editableDays(
    at instant: Date,
    timeZone: TimeZone
  ) throws -> GoalProgressEditableDays {
    GoalProgressEditableDays(today: try localDate(containing: instant, in: timeZone))
  }

  static func window(
    createdAt: Date,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> GoalProgressLocalDayWindow {
    let editableDays = try editableDays(at: instant, timeZone: timeZone)
    let creationDate = try localDate(containing: createdAt, in: timeZone)
    return GoalProgressLocalDayWindow(
      creationDate: creationDate,
      editableDays: editableDays
    )
  }

  private static func localDate(
    containing instant: Date,
    in timeZone: TimeZone
  ) throws -> GoalDate {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.era, .year, .month, .day], from: instant)
    guard
      components.era == 1,
      let year = components.year,
      let month = components.month,
      let day = components.day,
      let date = GoalDate(year: year, month: month, day: day)
    else {
      throw GoalProgressLocalDayEligibilityError.invalidDate
    }
    return date
  }
}

struct GoalProgressEditableDays {
  let today: GoalDate

  func contains(_ date: GoalDate) throws -> Bool {
    let yesterday = try today.previous()
    return date == today || date == yesterday
  }
}

struct GoalProgressLocalDayWindow {
  let creationDate: GoalDate
  let editableDays: GoalProgressEditableDays

  var today: GoalDate {
    editableDays.today
  }

  var availableAppendDestinations: [GoalProgressDestination] {
    guard let yesterday = try? editableDays.today.previous(), yesterday >= creationDate else {
      return [.today]
    }
    return [.today, .yesterday]
  }

  func assignedDate(for destination: GoalProgressDestination) throws -> GoalDate {
    switch destination {
    case .today:
      return today
    case .yesterday:
      return try editableDays.today.previous()
    }
  }

  func isDeleteEligible(_ date: GoalDate) -> Bool {
    (try? editableDays.contains(date)) ?? false
  }
}

private enum GoalProgressLocalDayEligibilityError: Error {
  case invalidDate
}
