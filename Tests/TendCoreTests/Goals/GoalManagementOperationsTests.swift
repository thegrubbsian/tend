import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Goal management operations")
struct GoalManagementOperationsTests {
  @Test("updates normalize every editable field across lifecycle states and goal directions")
  func updatesAllSupportedGoalConfigurationsWithoutRewritingHistory() throws {
    let cases: [UpdateCase] = [
      UpdateCase(
        kind: .accumulate,
        closure: nil,
        originalTarget: 10,
        originalBaseline: nil,
        fields: GoalEditableFields(
          name: "  Open accumulation  ",
          target: 20,
          unit: "  pages  ",
          deadline: try goalDate("2024-07-10")
        )
      ),
      UpdateCase(
        kind: .accumulate,
        closure: .harvested,
        originalTarget: 10,
        originalBaseline: nil,
        originalDeadline: try goalDate("2024-07-08"),
        fields: GoalEditableFields(
          name: "  Harvested accumulation\n",
          target: 30,
          unit: " repetitions ",
          deadline: nil
        )
      ),
      UpdateCase(
        kind: .accumulate,
        closure: .letGo,
        originalTarget: 10,
        originalBaseline: nil,
        fields: GoalEditableFields(
          name: " Let-go accumulation ",
          target: 40,
          unit: " minutes ",
          deadline: try goalDate("2024-07-11")
        )
      ),
      UpdateCase(
        kind: .measure,
        closure: nil,
        originalTarget: 100,
        originalBaseline: 10,
        fields: GoalEditableFields(
          name: " Reversed to decreasing ",
          target: 50,
          unit: " kg ",
          baseline: 200,
          deadline: try goalDate("2024-07-12")
        )
      ),
      UpdateCase(
        kind: .measure,
        closure: .harvested,
        originalTarget: 80,
        originalBaseline: 100,
        originalDeadline: try goalDate("2024-07-09"),
        fields: GoalEditableFields(
          name: " Reversed to increasing ",
          target: 60,
          unit: " percent ",
          baseline: 0,
          deadline: nil
        )
      ),
      UpdateCase(
        kind: .measure,
        closure: .letGo,
        originalTarget: 75,
        originalBaseline: 90,
        fields: GoalEditableFields(
          name: " Closed decreasing ",
          target: 70,
          unit: " kg ",
          baseline: 95,
          deadline: try goalDate("2024-07-13")
        )
      ),
    ]

    for value in cases {
      let context = try makeContext()
      let createdAt = try instant("2024-07-01T12:00:00Z")
      let goal = try persistedGoal(
        in: context,
        kind: value.kind,
        target: value.originalTarget,
        baseline: value.originalBaseline,
        deadline: value.originalDeadline,
        createdAt: createdAt,
        closure: value.closure,
        childCount: 3
      )
      let history = historyFacts(of: goal)
      let originalKind = goal.kindRawValue
      let originalCreation = goal.createdAt
      let originalClosure = goal.closureRawValue
      var saveCount = 0
      let operations = GoalManagementOperations(context: context) {
        saveCount += 1
        try context.save()
      }

      try operations.update(
        goal,
        fields: value.fields,
        calendar: calendar(in: timeZone("UTC")),
        timeZone: timeZone("UTC")
      )

      #expect(goal.name == value.fields.name.trimmingCharacters(in: .whitespacesAndNewlines))
      #expect(goal.target == value.fields.target)
      #expect(goal.unit == value.fields.unit.trimmingCharacters(in: .whitespacesAndNewlines))
      #expect(goal.baseline == value.fields.baseline)
      #expect(goal.deadlineKey == value.fields.deadline?.rawValue)
      #expect(goal.kindRawValue == originalKind)
      #expect(goal.createdAt == originalCreation)
      #expect(goal.closureRawValue == originalClosure)
      expectPersistedHistory(goal, equals: history)
      #expect(saveCount == 1)
      #expect(!context.hasChanges)
    }
  }

  @Test("updating current normalized values still performs one requested save")
  func unchangedUpdateStillSavesOnce() throws {
    let context = try makeContext()
    let deadline = try goalDate("2024-07-10")
    let goal = try persistedGoal(
      in: context,
      kind: .measure,
      target: 80,
      baseline: 100,
      deadline: deadline,
      closure: .letGo,
      childCount: 2
    )
    let history = historyFacts(of: goal)
    var saveCount = 0
    let operations = GoalManagementOperations(context: context) {
      saveCount += 1
      try context.save()
    }

    try operations.update(
      goal,
      fields: GoalEditableFields(
        name: "  Goal  ",
        target: 80,
        unit: "  unit  ",
        baseline: 100,
        deadline: deadline
      ),
      calendar: calendar(in: timeZone("UTC")),
      timeZone: timeZone("UTC")
    )

    #expect(saveCount == 1)
    #expect(goal.name == "Goal")
    #expect(goal.unit == "unit")
    #expect(goal.closureRawValue == GoalClosure.letGo.rawValue)
    expectPersistedHistory(goal, equals: history)
    #expect(!context.hasChanges)
  }

  @Test("updated scope immediately reinterprets accumulate and measure history and standing")
  func updateReinterpretsHistoryWithoutChangingIt() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let calendar = calendar(in: zone)
    let createdAt = try instant("2024-07-01T00:00:00Z")
    let evaluation = try instant("2024-07-02T00:00:00Z")
    let accumulate = try persistedGoal(
      in: context,
      kind: .accumulate,
      target: 10,
      createdAt: createdAt,
      childCount: 2
    )
    let accumulateHistory = historyFacts(of: accumulate)
    let progress = GoalProgressComputation(context: context)
    let standing = GoalStandingComputation()

    let beforeAccumulate = try progress.snapshot(for: accumulate)
    #expect(beforeAccumulate == .accumulate(
      AccumulateGoalProgress(
        total: 3,
        target: 10,
        unit: "unit",
        normalizedProgress: 0.3
      )
    ))

    try GoalManagementOperations(context: context).update(
      accumulate,
      fields: GoalEditableFields(
        name: "Rescoped accumulation",
        target: 6,
        unit: "sessions",
        deadline: try goalDate("2024-07-01")
      ),
      calendar: calendar,
      timeZone: zone
    )

    let afterAccumulate = try progress.snapshot(for: accumulate)
    #expect(afterAccumulate == .accumulate(
      AccumulateGoalProgress(
        total: 3,
        target: 6,
        unit: "sessions",
        normalizedProgress: 0.5
      )
    ))
    #expect(
      try standing.snapshot(
        for: accumulate,
        progress: afterAccumulate,
        at: evaluation,
        calendar: calendar,
        timeZone: zone
      )?.standing == .pastDue
    )
    expectPersistedHistory(accumulate, equals: accumulateHistory)

    let measure = try persistedGoal(
      in: context,
      kind: .measure,
      target: 80,
      baseline: 100,
      createdAt: createdAt,
      childCount: 2
    )
    let measureHistory = historyFacts(of: measure)
    let effectiveReadingID = try #require(
      measure.readings?.max { $0.appendSequence < $1.appendSequence }?.id
    )
    #expect(try progress.snapshot(for: measure) == .measure(
      MeasureGoalProgress(
        baseline: 100,
        target: 80,
        currentValue: 90,
        effectiveReadingID: effectiveReadingID,
        completedDistance: 10,
        totalDistance: 20,
        unit: "unit",
        normalizedProgress: 0.5
      )
    ))

    try GoalManagementOperations(context: context).update(
      measure,
      fields: GoalEditableFields(
        name: "Reversed measure",
        target: 120,
        unit: "points",
        baseline: 80
      ),
      calendar: calendar,
      timeZone: zone
    )

    #expect(try progress.snapshot(for: measure) == .measure(
      MeasureGoalProgress(
        baseline: 80,
        target: 120,
        currentValue: 90,
        effectiveReadingID: effectiveReadingID,
        completedDistance: 10,
        totalDistance: 40,
        unit: "points",
        normalizedProgress: 0.25
      )
    ))
    expectPersistedHistory(measure, equals: measureHistory)
  }

  @Test("invalid complete proposals fail before mutation or save")
  func invalidProposalsAreNoOps() throws {
    let invalidDeadline = try goalDate("2024-06-30")
    let maximumDeadline = try goalDate("9999-12-31")
    let cases: [InvalidUpdateCase] = [
      InvalidUpdateCase(
        kind: .accumulate,
        fields: GoalEditableFields(name: " \n\t ", target: 1),
        error: .emptyName
      ),
      InvalidUpdateCase(
        kind: .accumulate,
        fields: GoalEditableFields(name: "Goal", target: 0),
        error: .invalidTarget(0)
      ),
      InvalidUpdateCase(
        kind: .accumulate,
        fields: GoalEditableFields(name: "Goal", target: -1),
        error: .invalidTarget(-1)
      ),
      InvalidUpdateCase(
        kind: .accumulate,
        fields: GoalEditableFields(name: "Goal", target: 1, unit: " \t"),
        error: .emptyUnit
      ),
      InvalidUpdateCase(
        kind: .accumulate,
        fields: GoalEditableFields(name: "Goal", target: 1, baseline: 0),
        error: .accumulateBaseline(0)
      ),
      InvalidUpdateCase(
        kind: .measure,
        fields: GoalEditableFields(name: "Goal", target: 80, baseline: nil),
        error: .missingMeasureBaseline
      ),
      InvalidUpdateCase(
        kind: .measure,
        fields: GoalEditableFields(name: "Goal", target: 80, baseline: 80),
        error: .measureBaselineEqualsTarget(80)
      ),
      InvalidUpdateCase(
        kind: .accumulate,
        fields: GoalEditableFields(name: "Goal", target: 1, deadline: invalidDeadline),
        error: .deadlineNotAfterCreation(invalidDeadline)
      ),
      InvalidUpdateCase(
        kind: .accumulate,
        fields: GoalEditableFields(name: "Goal", target: 1, deadline: maximumDeadline),
        error: .invalidDeadlineBoundary(.unrepresentableDate)
      ),
    ]

    for value in cases {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: value.kind,
        target: value.kind == .accumulate ? 10 : 80,
        baseline: value.kind == .accumulate ? nil : 100,
        createdAt: instant("2024-07-01T00:00:00Z"),
        childCount: 2
      )
      let before = goalFacts(of: goal)
      let history = historyFacts(of: goal)
      var saveCount = 0
      let operations = GoalManagementOperations(context: context) { saveCount += 1 }

      try expectManagementError(value.error) {
        try operations.update(
          goal,
          fields: value.fields,
          calendar: calendar(in: timeZone("UTC")),
          timeZone: timeZone("UTC")
        )
      }

      expectGoal(goal, equals: before)
      expectHistory(goal, equals: history)
      #expect(saveCount == 0)
      #expect(!context.hasChanges)
    }
  }

  @Test("an unsupported persisted kind fails before update mutation or save")
  func unsupportedKindIsRejected() throws {
    let context = try makeContext()
    let goal = try persistedGoal(in: context, kind: .accumulate)
    goal.kindRawValue = "future-kind"
    try context.save()
    let before = goalFacts(of: goal)
    var saveCount = 0
    let operations = GoalManagementOperations(context: context) { saveCount += 1 }

    try expectManagementError(.invalidGoalKind("future-kind")) {
      try operations.update(
        goal,
        fields: GoalEditableFields(name: "Valid", target: 10),
        calendar: calendar(in: timeZone("UTC")),
        timeZone: timeZone("UTC")
      )
    }

    expectGoal(goal, equals: before)
    #expect(saveCount == 0)
    #expect(!context.hasChanges)
  }

  @Test("an unsupported persisted closure fails before update mutation or save")
  func unsupportedClosureIsRejectedByUpdate() throws {
    let context = try makeContext()
    let goal = try persistedGoal(in: context, kind: .accumulate, childCount: 2)
    goal.closureRawValue = "completed"
    try context.save()
    let before = goalFacts(of: goal)
    let history = historyFacts(of: goal)
    var saveCount = 0
    let operations = GoalManagementOperations(context: context) { saveCount += 1 }

    try expectManagementError(.invalidClosure("completed")) {
      try operations.update(
        goal,
        fields: GoalEditableFields(name: "Valid", target: 20),
        calendar: calendar(in: timeZone("UTC")),
        timeZone: timeZone("UTC")
      )
    }

    expectGoal(goal, equals: before)
    expectHistory(goal, equals: history)
    #expect(saveCount == 0)
    #expect(!context.hasChanges)
  }

  @Test("unsupported persisted kind or closure fails before delete mutation or save")
  func unsupportedEnumsAreRejectedByDelete() throws {
    let cases: [(mutate: (Goal) -> Void, error: GoalManagementOperationError)] = [
      ({ $0.kindRawValue = "future-kind" }, .invalidGoalKind("future-kind")),
      ({ $0.closureRawValue = "completed" }, .invalidClosure("completed")),
    ]

    for value in cases {
      let context = try makeContext()
      let goal = try persistedGoal(in: context, kind: .measure, childCount: 3)
      value.mutate(goal)
      try context.save()
      let before = goalFacts(of: goal)
      let history = historyFacts(of: goal)
      let originalIdentifier = goal.persistentModelID
      var saveCount = 0
      let operations = GoalManagementOperations(context: context) { saveCount += 1 }

      try expectManagementError(value.error) {
        try operations.delete(goal)
      }

      #expect(goal.modelContext === context)
      #expect(!goal.isDeleted)
      #expect(goal.persistentModelID == originalIdentifier)
      expectGoal(goal, equals: before)
      expectHistory(goal, equals: history)
      #expect(saveCount == 0)
      #expect(!context.hasChanges)
    }
  }

  @Test("deadline updates use the supplied calendar and following local-day boundary")
  func updateDeadlineUsesFollowingLocalDayBoundary() throws {
    let cases = [
      (key: "2024-03-10", zone: "America/Los_Angeles", boundary: "2024-03-11T07:00:00Z"),
      (key: "2024-11-03", zone: "America/Los_Angeles", boundary: "2024-11-04T08:00:00Z"),
      (key: "2024-07-04", zone: "Asia/Tokyo", boundary: "2024-07-04T15:00:00Z"),
    ]

    for value in cases {
      let context = try makeContext()
      let deadline = try goalDate(value.key)
      let boundary = try instant(value.boundary)
      let zone = try timeZone(value.zone)
      let goal = try persistedGoal(
        in: context,
        kind: .accumulate,
        createdAt: boundary.addingTimeInterval(-1)
      )
      var saveCount = 0
      let operations = GoalManagementOperations(context: context) {
        saveCount += 1
        try context.save()
      }

      try operations.update(
        goal,
        fields: GoalEditableFields(name: "Valid boundary", target: 10, deadline: deadline),
        calendar: calendar(in: zone),
        timeZone: zone
      )
      #expect(goal.deadlineKey == deadline.rawValue)
      #expect(saveCount == 1)

      let invalidContext = try makeContext()
      let invalidGoal = try persistedGoal(
        in: invalidContext,
        kind: .accumulate,
        createdAt: boundary
      )
      var invalidSaveCount = 0
      let invalidOperations = GoalManagementOperations(context: invalidContext) {
        invalidSaveCount += 1
      }
      try expectManagementError(.deadlineNotAfterCreation(deadline)) {
        try invalidOperations.update(
          invalidGoal,
          fields: GoalEditableFields(name: "Invalid boundary", target: 10, deadline: deadline),
          calendar: calendar(in: zone),
          timeZone: zone
        )
      }
      #expect(invalidSaveCount == 0)
      #expect(invalidGoal.deadlineKey == nil)
    }
  }

  @Test("detached, unsaved, deleted, and foreign goals fail before update or delete saves")
  func invalidOwnershipIsRejected() throws {
    let context = try makeContext()
    var saveCount = 0
    let operations = GoalManagementOperations(context: context) { saveCount += 1 }
    let detached = Goal(name: "Detached", kind: .accumulate, target: 1)
    try expectOwnershipError(.detachedGoal, for: detached, operations: operations)

    let unsaved = Goal(name: "Unsaved", kind: .accumulate, target: 1)
    context.insert(unsaved)
    try expectOwnershipError(.detachedGoal, for: unsaved, operations: operations)
    context.delete(unsaved)
    context.processPendingChanges()

    let deleted = try persistedGoal(in: context, kind: .accumulate)
    context.delete(deleted)
    try expectOwnershipError(.deletedGoal, for: deleted, operations: operations)
    context.rollback()

    let foreignContext = try makeContext()
    let foreign = try persistedGoal(in: foreignContext, kind: .measure)
    try expectOwnershipError(.foreignGoal, for: foreign, operations: operations)

    #expect(saveCount == 0)
  }

  @Test("update save failure restores only the goal fields and preserves caller pending work")
  func updateSaveFailureRestoresExactlyAndLocally() throws {
    let context = try makeContext()
    let goal = try persistedGoal(
      in: context,
      kind: .measure,
      target: 80,
      baseline: 100,
      deadline: try goalDate("2024-07-10"),
      closure: .harvested,
      childCount: 3
    )
    let unrelatedChanged = Habit(name: "Original", cadence: .daily, target: 1)
    let unrelatedDeleted = Goal(name: "Delete pending", kind: .accumulate, target: 1)
    context.insert(unrelatedChanged)
    context.insert(unrelatedDeleted)
    try context.save()
    unrelatedChanged.name = "Caller changed"
    context.delete(unrelatedDeleted)
    let unrelatedInserted = Habit(name: "Caller inserted", cadence: .daily, target: 1)
    context.insert(unrelatedInserted)

    let priorGoal = goalFacts(of: goal)
    let priorHistory = historyFacts(of: goal)
    let pendingDeletedID = unrelatedDeleted.persistentModelID
    var saveCount = 0
    let operations = GoalManagementOperations(context: context) {
      saveCount += 1
      #expect(goal.name == "Changed")
      #expect(goal.target == 120)
      #expect(goal.baseline == 80)
      #expect(goal.deadlineKey == nil)
      goal.closureRawValue = GoalClosure.letGo.rawValue
      throw GoalManagementSaveFailure.expected
    }

    do {
      try operations.update(
        goal,
        fields: GoalEditableFields(
          name: " Changed ",
          target: 120,
          unit: " points ",
          baseline: 80
        ),
        calendar: calendar(in: timeZone("UTC")),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected update save failure")
    } catch let error as GoalManagementSaveFailure {
      #expect(error == .expected)
    }

    #expect(saveCount == 1)
    #expect(goal.id == priorGoal.id)
    #expect(goal.name == priorGoal.name)
    #expect(goal.kindRawValue == priorGoal.kindRawValue)
    #expect(goal.target == priorGoal.target)
    #expect(goal.unit == priorGoal.unit)
    #expect(goal.baseline == priorGoal.baseline)
    #expect(goal.deadlineKey == priorGoal.deadlineKey)
    #expect(goal.createdAt == priorGoal.createdAt)
    #expect(goal.closureRawValue == GoalClosure.letGo.rawValue)
    expectHistory(goal, equals: priorHistory)
    #expect(unrelatedChanged.name == "Caller changed")
    #expect(unrelatedInserted.modelContext === context)
    #expect(context.insertedModelsArray.map(\.persistentModelID).contains(unrelatedInserted.persistentModelID))
    #expect(context.deletedModelsArray.map(\.persistentModelID).contains(pendingDeletedID))
    #expect(context.hasChanges)
    let recoveredGoal = goalFacts(of: goal)

    try context.save()
    let verification = ModelContext(context.container)
    let verifiedGoal = try #require(
      verification.fetch(FetchDescriptor<Goal>()).first { $0.id == priorGoal.id }
    )
    expectGoal(verifiedGoal, equals: recoveredGoal)
    expectPersistedHistory(verifiedGoal, equals: priorHistory)
    #expect(
      try verification.fetch(FetchDescriptor<Habit>()).first { $0.id == unrelatedChanged.id }?.name
        == "Caller changed"
    )
    #expect(
      try verification.fetch(FetchDescriptor<Habit>()).contains { $0.id == unrelatedInserted.id }
    )
    #expect(
      try !verification.fetch(FetchDescriptor<Goal>()).contains { $0.id == unrelatedDeleted.id }
    )
  }

  @Test("delete saves once and cascades zero, one, or many children for open and closed goals")
  func deleteCascadesEverySupportedAggregate() throws {
    let cases: [(GoalKind, GoalClosure?, Int)] = [
      (.accumulate, nil, 0),
      (.accumulate, .harvested, 1),
      (.accumulate, .letGo, 3),
      (.measure, nil, 3),
      (.measure, .harvested, 0),
      (.measure, .letGo, 1),
    ]

    for value in cases {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: value.0,
        target: value.0 == .accumulate ? 10 : 80,
        baseline: value.0 == .accumulate ? nil : 100,
        closure: value.1,
        childCount: value.2
      )
      let childIDs = Set(
        (goal.entries ?? []).map(\.persistentModelID)
          + (goal.readings ?? []).map(\.persistentModelID)
      )
      let unrelated = Habit(name: "Keep", cadence: .daily, target: 1)
      context.insert(unrelated)
      try context.save()
      var saveCount = 0
      let operations = GoalManagementOperations(context: context) {
        saveCount += 1
        try context.save()
      }

      try operations.delete(goal)

      #expect(saveCount == 1)
      #expect(try !context.fetch(FetchDescriptor<Goal>()).contains { $0.id == goal.id })
      #expect(
        Set(try context.fetch(FetchDescriptor<GoalEntry>()).map(\.persistentModelID))
          .isDisjoint(with: childIDs)
      )
      #expect(
        Set(try context.fetch(FetchDescriptor<GoalReading>()).map(\.persistentModelID))
          .isDisjoint(with: childIDs)
      )
      #expect(try context.fetch(FetchDescriptor<Habit>()).map(\.id) == [unrelated.id])
      #expect(!context.hasChanges)
    }
  }

  @Test("file-backed deletion removes every child after reopen and preserves unrelated records")
  func fileBackedDeleteCascadeSurvivesReopen() throws {
    let location = try makeTemporaryStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let deletedGoalIDs: Set<UUID>
    let deletedEntryIDs: Set<UUID>
    let deletedReadingIDs: Set<UUID>
    let keptGoalID: UUID
    let keptHabitID: UUID

    do {
      let container = try TendModelContainer.fileBacked(at: location.store)
      let context = container.mainContext
      let accumulate = try persistedGoal(
        in: context,
        kind: .accumulate,
        closure: .harvested,
        childCount: 3
      )
      let measure = try persistedGoal(
        in: context,
        kind: .measure,
        target: 80,
        baseline: 100,
        closure: .letGo,
        childCount: 2
      )
      let kept = try persistedGoal(in: context, kind: .accumulate, childCount: 1)
      let habit = Habit(name: "Keep habit", cadence: .daily, target: 1)
      context.insert(habit)
      try context.save()

      deletedGoalIDs = [accumulate.id, measure.id]
      deletedEntryIDs = Set((accumulate.entries ?? []).map(\.id))
      deletedReadingIDs = Set((measure.readings ?? []).map(\.id))
      keptGoalID = kept.id
      keptHabitID = habit.id
      let operations = GoalManagementOperations(context: context)
      try operations.delete(accumulate)
      try operations.delete(measure)
    }

    let reopened = try TendModelContainer.fileBacked(at: location.store)
    let verification = ModelContext(reopened)
    #expect(
      Set(try verification.fetch(FetchDescriptor<Goal>()).map(\.id)).isDisjoint(with: deletedGoalIDs)
    )
    #expect(
      Set(try verification.fetch(FetchDescriptor<GoalEntry>()).map(\.id))
        .isDisjoint(with: deletedEntryIDs)
    )
    #expect(
      Set(try verification.fetch(FetchDescriptor<GoalReading>()).map(\.id))
        .isDisjoint(with: deletedReadingIDs)
    )
    #expect(try verification.fetch(FetchDescriptor<Goal>()).contains { $0.id == keptGoalID })
    #expect(try verification.fetch(FetchDescriptor<Habit>()).contains { $0.id == keptHabitID })
  }

  @Test("delete save failure restores exact aggregate identity, facts, inverses, order, and caller work")
  func deleteSaveFailureRestoresExactlyAndLocally() throws {
    for kind in GoalKind.allCases {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: kind,
        target: kind == .accumulate ? 10 : 80,
        baseline: kind == .accumulate ? nil : 100,
        deadline: try goalDate("2024-07-10"),
        closure: .letGo,
        childCount: 3
      )
      let priorGoal = goalFacts(of: goal)
      let priorHistory = historyFacts(of: goal)
      let originalGoalIdentifier = goal.persistentModelID
      let unrelatedChanged = Habit(name: "Original", cadence: .daily, target: 1)
      let unrelatedDeleted = Goal(name: "Pending delete", kind: .accumulate, target: 1)
      context.insert(unrelatedChanged)
      context.insert(unrelatedDeleted)
      try context.save()
      unrelatedChanged.name = "Caller changed"
      context.delete(unrelatedDeleted)
      let unrelatedInserted = Habit(name: "Caller inserted", cadence: .daily, target: 1)
      context.insert(unrelatedInserted)
      let unrelatedDeletedIdentifier = unrelatedDeleted.persistentModelID
      var saveCount = 0
      let operations = GoalManagementOperations(context: context) {
        saveCount += 1
        #expect(goal.isDeleted)
        throw GoalManagementSaveFailure.expected
      }

      do {
        try operations.delete(goal)
        Issue.record("Expected delete save failure")
      } catch let error as GoalManagementSaveFailure {
        #expect(error == .expected)
      }

      #expect(saveCount == 1)
      #expect(goal.modelContext === context)
      #expect(!goal.isDeleted)
      #expect(goal.persistentModelID == originalGoalIdentifier)
      expectGoal(goal, equals: priorGoal)
      expectHistory(goal, equals: priorHistory)
      for entry in goal.entries ?? [] {
        #expect(entry.modelContext === context)
        #expect(!entry.isDeleted)
        #expect(entry.goal === goal)
      }
      for reading in goal.readings ?? [] {
        #expect(reading.modelContext === context)
        #expect(!reading.isDeleted)
        #expect(reading.goal === goal)
      }
      #expect(unrelatedChanged.name == "Caller changed")
      #expect(context.insertedModelsArray.map(\.persistentModelID).contains(unrelatedInserted.persistentModelID))
      #expect(context.deletedModelsArray.map(\.persistentModelID).contains(unrelatedDeletedIdentifier))
      #expect(!context.deletedModelsArray.map(\.persistentModelID).contains(originalGoalIdentifier))
      #expect(context.hasChanges)

      try context.save()
      let verification = ModelContext(context.container)
      let verifiedGoal = try #require(
        verification.fetch(FetchDescriptor<Goal>()).first { $0.id == priorGoal.id }
      )
      expectGoal(verifiedGoal, equals: priorGoal)
      expectPersistedHistory(verifiedGoal, equals: priorHistory)
      #expect(
        try verification.fetch(FetchDescriptor<Habit>()).first { $0.id == unrelatedChanged.id }?.name
          == "Caller changed"
      )
      #expect(
        try verification.fetch(FetchDescriptor<Habit>()).contains { $0.id == unrelatedInserted.id }
      )
      #expect(
        try !verification.fetch(FetchDescriptor<Goal>()).contains { $0.id == unrelatedDeleted.id }
      )
    }
  }

  private func expectOwnershipError(
    _ error: GoalManagementOperationError,
    for goal: Goal,
    operations: GoalManagementOperations
  ) throws {
    let fields = GoalEditableFields(name: "Valid", target: 1)
    try expectManagementError(error) {
      try operations.update(
        goal,
        fields: fields,
        calendar: calendar(in: timeZone("UTC")),
        timeZone: timeZone("UTC")
      )
    }
    try expectManagementError(error) {
      try operations.delete(goal)
    }
  }

  private func persistedGoal(
    in context: ModelContext,
    kind: GoalKind,
    target: Int = 10,
    baseline: Int? = nil,
    deadline: GoalDate? = nil,
    createdAt: Date = Date(timeIntervalSince1970: 1_719_792_000),
    closure: GoalClosure? = nil,
    childCount: Int = 0
  ) throws -> Goal {
    let goal = Goal(
      name: "Goal",
      kind: kind,
      target: target,
      unit: "unit",
      baseline: baseline,
      deadline: deadline,
      createdAt: createdAt
    )
    goal.closureRawValue = closure?.rawValue
    switch kind {
    case .accumulate:
      goal.entries = (0..<childCount).map { index in
        GoalEntry(
          amount: index + 1,
          assignedDate: GoalDate(rawValue: "2024-07-01")!,
          appendedAt: createdAt.addingTimeInterval(TimeInterval(index)),
          appendSequence: index * 3
        )
      }
    case .measure:
      goal.readings = (0..<childCount).map { index in
        GoalReading(
          value: 100 - (index * 10),
          assignedDate: GoalDate(rawValue: "2024-07-01")!,
          appendedAt: createdAt.addingTimeInterval(TimeInterval(index)),
          appendSequence: index * 3
        )
      }
    }
    context.insert(goal)
    try context.save()
    return goal
  }

  private func goalFacts(of goal: Goal) -> GoalFacts {
    GoalFacts(
      id: goal.id,
      name: goal.name,
      kindRawValue: goal.kindRawValue,
      target: goal.target,
      unit: goal.unit,
      baseline: goal.baseline,
      deadlineKey: goal.deadlineKey,
      createdAt: goal.createdAt,
      closureRawValue: goal.closureRawValue
    )
  }

  private func historyFacts(of goal: Goal) -> HistoryFacts {
    HistoryFacts(
      entryIdentifiers: (goal.entries ?? []).map(\.persistentModelID),
      entries: (goal.entries ?? []).map {
        EntryFacts(
          id: $0.id,
          amount: $0.amount,
          assignedDateKey: $0.assignedDateKey,
          appendedAt: $0.appendedAt,
          appendSequence: $0.appendSequence
        )
      },
      readingIdentifiers: (goal.readings ?? []).map(\.persistentModelID),
      readings: (goal.readings ?? []).map {
        ReadingFacts(
          id: $0.id,
          value: $0.value,
          assignedDateKey: $0.assignedDateKey,
          appendedAt: $0.appendedAt,
          appendSequence: $0.appendSequence
        )
      }
    )
  }

  private func expectGoal(_ goal: Goal, equals facts: GoalFacts) {
    #expect(goal.id == facts.id)
    #expect(goal.name == facts.name)
    #expect(goal.kindRawValue == facts.kindRawValue)
    #expect(goal.target == facts.target)
    #expect(goal.unit == facts.unit)
    #expect(goal.baseline == facts.baseline)
    #expect(goal.deadlineKey == facts.deadlineKey)
    #expect(goal.createdAt == facts.createdAt)
    #expect(goal.closureRawValue == facts.closureRawValue)
  }

  private func expectHistory(_ goal: Goal, equals facts: HistoryFacts) {
    #expect((goal.entries ?? []).map(\.persistentModelID) == facts.entryIdentifiers)
    #expect((goal.entries ?? []).map {
      EntryFacts(
        id: $0.id,
        amount: $0.amount,
        assignedDateKey: $0.assignedDateKey,
        appendedAt: $0.appendedAt,
        appendSequence: $0.appendSequence
      )
    } == facts.entries)
    #expect((goal.readings ?? []).map(\.persistentModelID) == facts.readingIdentifiers)
    #expect((goal.readings ?? []).map {
      ReadingFacts(
        id: $0.id,
        value: $0.value,
        assignedDateKey: $0.assignedDateKey,
        appendedAt: $0.appendedAt,
        appendSequence: $0.appendSequence
      )
    } == facts.readings)
  }

  private func expectPersistedHistory(_ goal: Goal, equals facts: HistoryFacts) {
    #expect(
      Set((goal.entries ?? []).map(\.persistentModelID)) == Set(facts.entryIdentifiers)
    )
    #expect(
      Set((goal.readings ?? []).map(\.persistentModelID)) == Set(facts.readingIdentifiers)
    )
    #expect(Set((goal.entries ?? []).map(\.id)) == Set(facts.entries.map(\.id)))
    #expect(Set((goal.readings ?? []).map(\.id)) == Set(facts.readings.map(\.id)))
    for entry in goal.entries ?? [] {
      #expect(entry.goal === goal)
    }
    for reading in goal.readings ?? [] {
      #expect(reading.goal === goal)
    }
    let entries = (goal.entries ?? []).sorted { $0.appendSequence < $1.appendSequence }
    let expectedEntries = facts.entries.sorted { $0.appendSequence < $1.appendSequence }
    #expect(entries.map {
      EntryFacts(
        id: $0.id,
        amount: $0.amount,
        assignedDateKey: $0.assignedDateKey,
        appendedAt: $0.appendedAt,
        appendSequence: $0.appendSequence
      )
    } == expectedEntries)
    let readings = (goal.readings ?? []).sorted { $0.appendSequence < $1.appendSequence }
    let expectedReadings = facts.readings.sorted { $0.appendSequence < $1.appendSequence }
    #expect(readings.map {
      ReadingFacts(
        id: $0.id,
        value: $0.value,
        assignedDateKey: $0.assignedDateKey,
        appendedAt: $0.appendedAt,
        appendSequence: $0.appendSequence
      )
    } == expectedReadings)
  }

  private func expectManagementError(
    _ expected: GoalManagementOperationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected GoalManagementOperationError: \(expected)")
    } catch let error as GoalManagementOperationError {
      #expect(error == expected)
    }
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private func timeZone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }

  private func calendar(in timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    return calendar
  }

  private func goalDate(_ value: String) throws -> GoalDate {
    try #require(GoalDate(rawValue: value))
  }

  private func makeTemporaryStoreLocation() throws -> (directory: URL, store: URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("GoalManagementOperationsTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false
    )
    return (directory, directory.appendingPathComponent("Tend.store"))
  }
}

private struct UpdateCase {
  let kind: GoalKind
  let closure: GoalClosure?
  let originalTarget: Int
  let originalBaseline: Int?
  var originalDeadline: GoalDate? = nil
  let fields: GoalEditableFields
}

private struct InvalidUpdateCase {
  let kind: GoalKind
  let fields: GoalEditableFields
  let error: GoalManagementOperationError
}

private struct GoalFacts {
  let id: UUID
  let name: String
  let kindRawValue: String
  let target: Int
  let unit: String
  let baseline: Int?
  let deadlineKey: String?
  let createdAt: Date
  let closureRawValue: String?
}

private struct HistoryFacts {
  let entryIdentifiers: [PersistentIdentifier]
  let entries: [EntryFacts]
  let readingIdentifiers: [PersistentIdentifier]
  let readings: [ReadingFacts]
}

private struct EntryFacts: Equatable {
  let id: UUID
  let amount: Int
  let assignedDateKey: String
  let appendedAt: Date
  let appendSequence: Int
}

private struct ReadingFacts: Equatable {
  let id: UUID
  let value: Int
  let assignedDateKey: String
  let appendedAt: Date
  let appendSequence: Int
}

private enum GoalManagementSaveFailure: Error, Equatable {
  case expected
}
