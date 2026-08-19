import Foundation
import SwiftData

public struct GoalCreationFields: Equatable, Sendable {
  public let name: String
  public let kind: GoalKind
  public let target: Int
  public let unit: String
  public let baseline: Int?
  public let deadline: LocalDate?

  public init(
    name: String,
    kind: GoalKind,
    target: Int,
    unit: String = "times",
    baseline: Int? = nil,
    deadline: LocalDate? = nil
  ) {
    self.name = name
    self.kind = kind
    self.target = target
    self.unit = unit
    self.baseline = baseline
    self.deadline = deadline
  }
}

public enum GoalCreationOperationError: Error, Equatable, Sendable {
  case emptyName
  case invalidTarget(Int)
  case emptyUnit
  case accumulateBaseline(Int)
  case missingMeasureBaseline
  case measureBaselineEqualsTarget(Int)
  case invalidDeadlineBoundary(LocalDateError)
  case deadlineExpired(LocalDate)
}

@MainActor
public final class GoalCreationOperations {
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

  public func create(
    fields: GoalCreationFields,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> Goal {
    let fields = try validated(fields, at: instant, timeZone: timeZone)
    let goal = Goal(
      name: fields.name,
      kind: fields.kind,
      target: fields.target,
      unit: fields.unit,
      baseline: fields.baseline,
      deadline: fields.deadline,
      createdAt: instant
    )
    context.insert(goal)

    do {
      try saveContext()
      return goal
    } catch {
      goal.entries = []
      goal.readings = []
      context.delete(goal)
      context.processPendingChanges()
      throw error
    }
  }

  private func validated(
    _ fields: GoalCreationFields,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> GoalCreationFields {
    let name = normalized(fields.name)
    guard !name.isEmpty else {
      throw GoalCreationOperationError.emptyName
    }
    guard fields.target > 0 else {
      throw GoalCreationOperationError.invalidTarget(fields.target)
    }
    let unit = normalized(fields.unit)
    guard !unit.isEmpty else {
      throw GoalCreationOperationError.emptyUnit
    }

    switch fields.kind {
    case .accumulate:
      if let baseline = fields.baseline {
        throw GoalCreationOperationError.accumulateBaseline(baseline)
      }
    case .measure:
      guard let baseline = fields.baseline else {
        throw GoalCreationOperationError.missingMeasureBaseline
      }
      guard baseline != fields.target else {
        throw GoalCreationOperationError.measureBaselineEqualsTarget(baseline)
      }
    }

    if let deadline = fields.deadline {
      let boundary: Date
      do {
        boundary = try deadline.next().start(in: timeZone)
      } catch let error as LocalDateError {
        throw GoalCreationOperationError.invalidDeadlineBoundary(error)
      }
      guard boundary > instant else {
        throw GoalCreationOperationError.deadlineExpired(deadline)
      }
    }

    return GoalCreationFields(
      name: name,
      kind: fields.kind,
      target: fields.target,
      unit: unit,
      baseline: fields.baseline,
      deadline: fields.deadline
    )
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
