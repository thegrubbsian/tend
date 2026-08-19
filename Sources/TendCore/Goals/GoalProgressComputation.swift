import Foundation
import SwiftData

public struct AccumulateGoalProgress: Equatable, Sendable {
  public let kind: GoalKind = .accumulate
  public let total: Int
  public let target: Int
  public let unit: String
  public let normalizedProgress: Double

  public init(
    total: Int,
    target: Int,
    unit: String,
    normalizedProgress: Double
  ) {
    self.total = total
    self.target = target
    self.unit = unit
    self.normalizedProgress = normalizedProgress
  }
}

public struct MeasureGoalProgress: Equatable, Sendable {
  public let kind: GoalKind = .measure
  public let baseline: Int
  public let target: Int
  public let currentValue: Int
  public let effectiveReadingID: UUID?
  public let completedDistance: Int
  public let totalDistance: Int
  public let unit: String
  public let normalizedProgress: Double

  public init(
    baseline: Int,
    target: Int,
    currentValue: Int,
    effectiveReadingID: UUID?,
    completedDistance: Int,
    totalDistance: Int,
    unit: String,
    normalizedProgress: Double
  ) {
    self.baseline = baseline
    self.target = target
    self.currentValue = currentValue
    self.effectiveReadingID = effectiveReadingID
    self.completedDistance = completedDistance
    self.totalDistance = totalDistance
    self.unit = unit
    self.normalizedProgress = normalizedProgress
  }
}

public enum GoalProgressSnapshot: Equatable, Sendable {
  case accumulate(AccumulateGoalProgress)
  case measure(MeasureGoalProgress)
}

public enum GoalProgressComputationError: Error, Equatable, Sendable {
  case detachedGoal
  case foreignGoal
  case invalidGoalKind(String)
  case invalidName(String)
  case invalidTarget(Int)
  case invalidUnit(String)
  case invalidAccumulateBaseline(Int)
  case missingMeasureBaseline
  case measureBaselineEqualsTarget(Int)
  case invalidDeadline(String)
  case missingEntries
  case missingReadings
  case invalidGoalGraph
  case invalidAssignedDate(String)
  case invalidEntryAmount(Int)
  case invalidSequence(Int)
  case duplicateSequence(Int)
  case accumulateTotalOverflow
  case measureSpanOverflow
  case measureTraveledDistanceOverflow
}

@MainActor
public final class GoalProgressComputation {
  private let context: ModelContext

  public init(context: ModelContext) {
    self.context = context
  }

  public func snapshot(for goal: Goal) throws -> GoalProgressSnapshot {
    let graph = try validatedGraph(for: goal)

    switch graph.kind {
    case .accumulate:
      return .accumulate(try accumulateSnapshot(for: goal, entries: graph.entries))
    case .measure:
      return .measure(
        try measureSnapshot(for: goal, effectiveReading: graph.effectiveReading)
      )
    }
  }

  private func accumulateSnapshot(
    for goal: Goal,
    entries: [GoalEntry]
  ) throws -> AccumulateGoalProgress {
    var total = 0
    for entry in entries {
      let result = total.addingReportingOverflow(entry.amount)
      guard !result.overflow else {
        throw GoalProgressComputationError.accumulateTotalOverflow
      }
      total = result.partialValue
    }

    let normalizedProgress = Double(total) / Double(goal.target)
    return AccumulateGoalProgress(
      total: total,
      target: goal.target,
      unit: goal.unit,
      normalizedProgress: normalizedProgress
    )
  }

  private func measureSnapshot(
    for goal: Goal,
    effectiveReading: GoalReading?
  ) throws -> MeasureGoalProgress {
    guard let baseline = goal.baseline else {
      throw GoalProgressComputationError.missingMeasureBaseline
    }
    let isIncreasing = goal.target > baseline
    let span =
      isIncreasing
      ? goal.target.subtractingReportingOverflow(baseline)
      : baseline.subtractingReportingOverflow(goal.target)
    guard !span.overflow else {
      throw GoalProgressComputationError.measureSpanOverflow
    }
    let totalDistance = span.partialValue

    guard let effectiveReading else {
      return MeasureGoalProgress(
        baseline: baseline,
        target: goal.target,
        currentValue: baseline,
        effectiveReadingID: nil,
        completedDistance: 0,
        totalDistance: totalDistance,
        unit: goal.unit,
        normalizedProgress: 0
      )
    }

    let traveled =
      isIncreasing
      ? effectiveReading.value.subtractingReportingOverflow(baseline)
      : baseline.subtractingReportingOverflow(effectiveReading.value)
    guard !traveled.overflow else {
      throw GoalProgressComputationError.measureTraveledDistanceOverflow
    }
    let completedDistance = min(max(traveled.partialValue, 0), totalDistance)
    let normalizedProgress = Double(completedDistance) / Double(totalDistance)

    return MeasureGoalProgress(
      baseline: baseline,
      target: goal.target,
      currentValue: effectiveReading.value,
      effectiveReadingID: effectiveReading.id,
      completedDistance: completedDistance,
      totalDistance: totalDistance,
      unit: goal.unit,
      normalizedProgress: normalizedProgress
    )
  }

  private func validatedGraph(for goal: Goal) throws -> GoalProgressGraph {
    try requirePersisted(goal)
    let kind = try validatedConfiguration(goal)
    guard let entries = goal.entries else {
      throw GoalProgressComputationError.missingEntries
    }
    guard let readings = goal.readings else {
      throw GoalProgressComputationError.missingReadings
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
      throw GoalProgressComputationError.invalidGoalGraph
    }

    for entry in entries {
      guard isPersisted(entry), entry.goal === goal else {
        throw GoalProgressComputationError.invalidGoalGraph
      }
      guard entry.amount > 0 else {
        throw GoalProgressComputationError.invalidEntryAmount(entry.amount)
      }
      _ = try parsedDate(entry.assignedDateKey)
    }

    var effective: (reading: GoalReading, date: LocalDate)?
    for reading in readings {
      guard isPersisted(reading), reading.goal === goal else {
        throw GoalProgressComputationError.invalidGoalGraph
      }
      let assignedDate = try parsedDate(reading.assignedDateKey)
      guard let current = effective else {
        effective = (reading, assignedDate)
        continue
      }
      if assignedDate > current.date
        || (assignedDate == current.date
          && reading.appendSequence > current.reading.appendSequence)
      {
        effective = (reading, assignedDate)
      }
    }

    switch kind {
    case .accumulate where !readings.isEmpty:
      throw GoalProgressComputationError.invalidGoalGraph
    case .measure where !entries.isEmpty:
      throw GoalProgressComputationError.invalidGoalGraph
    case .accumulate, .measure:
      break
    }

    let relevantSequences =
      kind == .accumulate
      ? entries.map(\.appendSequence)
      : readings.map(\.appendSequence)
    try validateSequences(relevantSequences)

    return GoalProgressGraph(
      kind: kind,
      entries: entries,
      effectiveReading: effective?.reading
    )
  }

  private func validatedConfiguration(_ goal: Goal) throws -> GoalKind {
    let name = normalized(goal.name)
    guard !name.isEmpty, name == goal.name else {
      throw GoalProgressComputationError.invalidName(goal.name)
    }
    guard goal.target > 0 else {
      throw GoalProgressComputationError.invalidTarget(goal.target)
    }
    let unit = normalized(goal.unit)
    guard !unit.isEmpty, unit == goal.unit else {
      throw GoalProgressComputationError.invalidUnit(goal.unit)
    }
    guard let kind = GoalKind(rawValue: goal.kindRawValue) else {
      throw GoalProgressComputationError.invalidGoalKind(goal.kindRawValue)
    }

    switch kind {
    case .accumulate:
      if let baseline = goal.baseline {
        throw GoalProgressComputationError.invalidAccumulateBaseline(baseline)
      }
    case .measure:
      guard let baseline = goal.baseline else {
        throw GoalProgressComputationError.missingMeasureBaseline
      }
      guard baseline != goal.target else {
        throw GoalProgressComputationError.measureBaselineEqualsTarget(baseline)
      }
    }

    if let deadlineKey = goal.deadlineKey, LocalDate(rawValue: deadlineKey) == nil {
      throw GoalProgressComputationError.invalidDeadline(deadlineKey)
    }
    return kind
  }

  private func parsedDate(_ key: String) throws -> LocalDate {
    guard let date = LocalDate(rawValue: key) else {
      throw GoalProgressComputationError.invalidAssignedDate(key)
    }
    return date
  }

  private func validateSequences(_ sequences: [Int]) throws {
    var observed = Set<Int>()
    observed.reserveCapacity(sequences.count)
    for sequence in sequences {
      guard sequence >= 0 else {
        throw GoalProgressComputationError.invalidSequence(sequence)
      }
      guard observed.insert(sequence).inserted else {
        throw GoalProgressComputationError.duplicateSequence(sequence)
      }
    }
  }

  private func requirePersisted(_ goal: Goal) throws {
    guard let modelContext = goal.modelContext else {
      throw GoalProgressComputationError.detachedGoal
    }
    guard modelContext === context else {
      throw GoalProgressComputationError.foreignGoal
    }
    guard goal.persistentModelID.storeIdentifier != nil, !goal.isDeleted else {
      throw GoalProgressComputationError.detachedGoal
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

private struct GoalProgressGraph {
  let kind: GoalKind
  let entries: [GoalEntry]
  let effectiveReading: GoalReading?
}
