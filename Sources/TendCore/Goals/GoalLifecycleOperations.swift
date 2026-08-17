import SwiftData

public enum GoalLifecycleOperationError: Error, Equatable, Sendable {
  case alreadyOpen
  case alreadyClosed(GoalClosure)
  case invalidClosure(String)
  case detachedGoal
  case deletedGoal
  case foreignGoal
}

@MainActor
public final class GoalLifecycleOperations {
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

  public func close(_ goal: Goal, as closure: GoalClosure) throws {
    try requirePersisted(goal)
    if let current = try validatedClosure(of: goal) {
      throw GoalLifecycleOperationError.alreadyClosed(current)
    }
    try setClosure(closure.rawValue, on: goal)
  }

  public func reopen(_ goal: Goal) throws {
    try requirePersisted(goal)
    guard try validatedClosure(of: goal) != nil else {
      throw GoalLifecycleOperationError.alreadyOpen
    }
    try setClosure(nil, on: goal)
  }

  private func setClosure(_ closureRawValue: String?, on goal: Goal) throws {
    let priorClosureRawValue = goal.closureRawValue
    goal.closureRawValue = closureRawValue

    do {
      try saveContext()
    } catch {
      goal.closureRawValue = priorClosureRawValue
      context.processPendingChanges()
      throw error
    }
  }

  private func validatedClosure(of goal: Goal) throws -> GoalClosure? {
    do {
      return try goal.checkedClosure
    } catch GoalClosureError.unsupportedRawValue(let rawValue) {
      throw GoalLifecycleOperationError.invalidClosure(rawValue)
    }
  }

  private func requirePersisted(_ goal: Goal) throws {
    if goal.modelContext === context {
      guard !goal.isDeleted else {
        throw GoalLifecycleOperationError.deletedGoal
      }
      guard goal.persistentModelID.storeIdentifier != nil else {
        throw GoalLifecycleOperationError.detachedGoal
      }
      return
    }
    if goal.modelContext != nil {
      throw GoalLifecycleOperationError.foreignGoal
    }
    if goal.persistentModelID.storeIdentifier != nil {
      throw GoalLifecycleOperationError.deletedGoal
    }
    throw GoalLifecycleOperationError.detachedGoal
  }
}
