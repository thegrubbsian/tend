import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Goal lifecycle operations")
struct GoalLifecycleOperationsTests {
  @Test("closing is explicit across both kinds, dispositions, standings, and progress levels")
  func closeChangesOnlyClosureAcrossEveryGoalState() throws {
    let cases: [LifecycleCase] = [
      .init(kind: .accumulate, progressValues: [], closure: .harvested, expectedProgress: 0, expectedStanding: .onPace),
      .init(kind: .accumulate, progressValues: [2], deadline: "2024-07-04", closure: .letGo, expectedProgress: 0.2, expectedStanding: .behind),
      .init(kind: .accumulate, progressValues: [10], deadline: "2024-07-04", closure: .harvested, expectedProgress: 1, expectedStanding: .onPace, evaluation: "2024-07-02T00:00:00Z"),
      .init(kind: .accumulate, progressValues: [12], deadline: "2024-07-03", closure: .letGo, expectedProgress: 1.2, expectedStanding: .pastDue, evaluation: "2024-07-05T00:00:00Z"),
      .init(kind: .measure, progressValues: [], closure: .letGo, expectedProgress: 0, expectedStanding: .onPace),
      .init(kind: .measure, progressValues: [95], deadline: "2024-07-04", closure: .harvested, expectedProgress: 0.25, expectedStanding: .behind),
      .init(kind: .measure, progressValues: [80], deadline: "2024-07-04", closure: .letGo, expectedProgress: 1, expectedStanding: .onPace, evaluation: "2024-07-02T00:00:00Z"),
      .init(kind: .measure, progressValues: [70], deadline: "2024-07-03", closure: .harvested, expectedProgress: 1, expectedStanding: .pastDue, evaluation: "2024-07-05T00:00:00Z"),
    ]

    for testCase in cases {
      let context = try makeContext()
      let goal = try persistedGoal(in: context, testCase: testCase)
      let facts = goalFacts(of: goal)
      let history = historyFacts(of: goal)
      let progress = try GoalProgressComputation(context: context).snapshot(for: goal)
      #expect(normalizedProgress(of: progress) == testCase.expectedProgress)
      let standing = try standingSnapshot(for: goal, progress: progress, at: testCase.evaluation)
      #expect(standing?.standing == testCase.expectedStanding)
      var saveCount = 0
      let operations = GoalLifecycleOperations(context: context) {
        saveCount += 1
        #expect(goal.closureRawValue == testCase.closure.rawValue)
        try context.save()
      }

      try operations.close(goal, as: testCase.closure)

      #expect(saveCount == 1)
      #expect(goal.closureRawValue == testCase.closure.rawValue)
      expectGoal(goal, equals: facts)
      expectHistory(goal, equals: history)
      #expect(try standingSnapshot(for: goal, progress: progress, at: testCase.evaluation) == nil)
      #expect(!context.hasChanges)
    }
  }

  @Test("reopening both dispositions changes only closure and recomputes every open standing")
  func reopenChangesOnlyClosureAndRestoresDerivedStanding() throws {
    let cases: [LifecycleCase] = [
      .init(kind: .accumulate, progressValues: [6], closure: .harvested, expectedProgress: 0.6, expectedStanding: .onPace, evaluation: "2024-07-02T00:00:00Z"),
      .init(kind: .accumulate, progressValues: [2], deadline: "2024-07-04", closure: .letGo, expectedProgress: 0.2, expectedStanding: .behind),
      .init(kind: .accumulate, progressValues: [12], deadline: "2024-07-03", closure: .harvested, expectedProgress: 1.2, expectedStanding: .pastDue, evaluation: "2024-07-05T00:00:00Z"),
      .init(kind: .measure, progressValues: [80], closure: .letGo, expectedProgress: 1, expectedStanding: .onPace, evaluation: "2024-07-02T00:00:00Z"),
      .init(kind: .measure, progressValues: [95], deadline: "2024-07-04", closure: .harvested, expectedProgress: 0.25, expectedStanding: .behind),
      .init(kind: .measure, progressValues: [70], deadline: "2024-07-03", closure: .letGo, expectedProgress: 1, expectedStanding: .pastDue, evaluation: "2024-07-05T00:00:00Z"),
    ]

    for testCase in cases {
      let context = try makeContext()
      let goal = try persistedGoal(in: context, testCase: testCase, initialClosure: testCase.closure)
      let facts = goalFacts(of: goal)
      let history = historyFacts(of: goal)
      let progress = try GoalProgressComputation(context: context).snapshot(for: goal)
      #expect(try standingSnapshot(for: goal, progress: progress, at: testCase.evaluation) == nil)
      var saveCount = 0
      let operations = GoalLifecycleOperations(context: context) {
        saveCount += 1
        #expect(goal.closureRawValue == nil)
        try context.save()
      }

      try operations.reopen(goal)

      #expect(saveCount == 1)
      #expect(goal.closureRawValue == nil)
      expectGoal(goal, equals: facts)
      expectHistory(goal, equals: history)
      let reopenedSnapshot = try standingSnapshot(
        for: goal,
        progress: progress,
        at: testCase.evaluation
      )
      let standing = try #require(reopenedSnapshot)
      #expect(standing.standing == testCase.expectedStanding)
      #expect(standing.actualNormalizedProgress == testCase.expectedProgress)
      #expect(!context.hasChanges)
    }
  }

  @Test("lifecycle validation owns only persistence and closure")
  func lifecycleTransitionsIgnoreKindAndScalarConfiguration() throws {
    let context = try makeContext()
    let goal = try persistedGoal(
      in: context,
      testCase: .init(
        kind: .accumulate,
        progressValues: [],
        closure: .harvested,
        expectedProgress: 0,
        expectedStanding: .onPace
      )
    )
    goal.name = " \n "
    goal.kindRawValue = "future-kind"
    goal.target = -10
    goal.unit = ""
    goal.baseline = 10
    goal.deadlineKey = "not-a-date"
    var saveCount = 0
    let operations = GoalLifecycleOperations(context: context) {
      saveCount += 1
      try context.save()
    }

    try operations.close(goal, as: .harvested)
    try operations.reopen(goal)

    #expect(saveCount == 2)
    #expect(goal.closureRawValue == nil)
    #expect(goal.name == " \n ")
    #expect(goal.kindRawValue == "future-kind")
    #expect(goal.target == -10)
    #expect(goal.unit == "")
    #expect(goal.baseline == 10)
    #expect(goal.deadlineKey == "not-a-date")
  }

  @Test("repeated and corrupt transitions fail with typed errors and no save")
  func invalidTransitionsFailBeforeMutationOrSave() throws {
    let context = try makeContext()
    let open = try persistedGoal(
      in: context,
      testCase: .init(kind: .accumulate, progressValues: [], closure: .harvested, expectedProgress: 0, expectedStanding: .onPace)
    )
    let harvested = try persistedGoal(
      in: context,
      testCase: .init(kind: .measure, progressValues: [], closure: .harvested, expectedProgress: 0, expectedStanding: .onPace),
      initialClosure: .harvested
    )
    let letGo = try persistedGoal(
      in: context,
      testCase: .init(kind: .accumulate, progressValues: [], closure: .letGo, expectedProgress: 0, expectedStanding: .onPace),
      initialClosure: .letGo
    )
    let corrupt = try persistedGoal(
      in: context,
      testCase: .init(kind: .measure, progressValues: [], closure: .harvested, expectedProgress: 0, expectedStanding: .onPace)
    )
    corrupt.closureRawValue = "future-disposition"
    var saveCount = 0
    let operations = GoalLifecycleOperations(context: context) { saveCount += 1 }

    try expectLifecycleError(.alreadyOpen) {
      try operations.reopen(open)
    }
    try expectLifecycleError(.alreadyClosed(.harvested)) {
      try operations.close(harvested, as: .letGo)
    }
    try expectLifecycleError(.alreadyClosed(.letGo)) {
      try operations.close(letGo, as: .harvested)
    }
    try expectLifecycleError(.invalidClosure("future-disposition")) {
      try operations.close(corrupt, as: .harvested)
    }
    try expectLifecycleError(.invalidClosure("future-disposition")) {
      try operations.reopen(corrupt)
    }

    #expect(saveCount == 0)
    #expect(open.closureRawValue == nil)
    #expect(harvested.closureRawValue == GoalClosure.harvested.rawValue)
    #expect(letGo.closureRawValue == GoalClosure.letGo.rawValue)
    #expect(corrupt.closureRawValue == "future-disposition")
  }

  @Test("detached, unsaved, deleted, and foreign goals fail with distinct ownership errors")
  func invalidOwnershipFailsBeforeMutationOrSave() throws {
    let context = try makeContext()
    var saveCount = 0
    let operations = GoalLifecycleOperations(context: context) { saveCount += 1 }

    let detached = Goal(name: "Detached", kind: .accumulate, target: 1)
    try expectOwnershipError(.detachedGoal, goal: detached, operations: operations)

    let unsaved = Goal(name: "Unsaved", kind: .measure, target: 1, baseline: 0)
    context.insert(unsaved)
    try expectOwnershipError(.detachedGoal, goal: unsaved, operations: operations)
    context.delete(unsaved)
    context.processPendingChanges()

    let deleted = try persistedGoal(
      in: context,
      testCase: .init(kind: .accumulate, progressValues: [], closure: .harvested, expectedProgress: 0, expectedStanding: .onPace)
    )
    context.delete(deleted)
    try expectOwnershipError(.deletedGoal, goal: deleted, operations: operations)
    context.rollback()

    let foreignContext = try makeContext()
    let foreign = try persistedGoal(
      in: foreignContext,
      testCase: .init(kind: .measure, progressValues: [], closure: .letGo, expectedProgress: 0, expectedStanding: .onPace),
      initialClosure: .letGo
    )
    try expectOwnershipError(.foreignGoal, goal: foreign, operations: operations)

    #expect(saveCount == 0)
  }

  @Test("save failures restore only closure and preserve unrelated pending insert, change, and delete")
  func saveFailureRecoveryIsOperationLocal() throws {
    let recoveryCases: [(initial: GoalClosure?, requested: GoalClosure?)] = [
      (nil, .letGo),
      (.harvested, nil),
    ]

    for recoveryCase in recoveryCases {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        testCase: .init(
          kind: recoveryCase.initial == nil ? .accumulate : .measure,
          progressValues: recoveryCase.initial == nil ? [3, 4] : [95, 90],
          deadline: "2024-07-04",
          closure: .harvested,
          expectedProgress: recoveryCase.initial == nil ? 0.7 : 0.5,
          expectedStanding: .onPace
        ),
        initialClosure: recoveryCase.initial
      )
      let changed = Habit(name: "Original", cadence: .daily, target: 1)
      let deleted = Goal(name: "Delete pending", kind: .accumulate, target: 1)
      context.insert(changed)
      context.insert(deleted)
      try context.save()
      goal.name = "Caller changed goal"
      changed.name = "Caller changed habit"
      context.delete(deleted)
      let inserted = Habit(name: "Caller inserted", cadence: .daily, target: 1)
      context.insert(inserted)
      let priorFacts = goalFacts(of: goal)
      let priorHistory = historyFacts(of: goal)
      let deletedIdentifier = deleted.persistentModelID
      var saveCount = 0
      let operations = GoalLifecycleOperations(context: context) {
        saveCount += 1
        #expect(goal.closureRawValue == recoveryCase.requested?.rawValue)
        goal.closureRawValue = "save-hook-mutation"
        throw GoalLifecycleSaveFailure.expected
      }

      do {
        if let requested = recoveryCase.requested {
          try operations.close(goal, as: requested)
        } else {
          try operations.reopen(goal)
        }
        Issue.record("Expected lifecycle save failure")
      } catch let error as GoalLifecycleSaveFailure {
        #expect(error == .expected)
      }

      #expect(saveCount == 1)
      #expect(goal.closureRawValue == recoveryCase.initial?.rawValue)
      expectGoal(goal, equals: priorFacts)
      expectHistory(goal, equals: priorHistory)
      #expect(changed.name == "Caller changed habit")
      #expect(context.insertedModelsArray.map(\.persistentModelID).contains(inserted.persistentModelID))
      #expect(context.deletedModelsArray.map(\.persistentModelID).contains(deletedIdentifier))
      #expect(context.hasChanges)

      try context.save()
      let verification = ModelContext(context.container)
      let verifiedGoal = try #require(
        verification.fetch(FetchDescriptor<Goal>()).first { $0.id == goal.id }
      )
      #expect(verifiedGoal.name == "Caller changed goal")
      #expect(verifiedGoal.closureRawValue == recoveryCase.initial?.rawValue)
      expectPersistedHistory(verifiedGoal, equals: priorHistory)
      #expect(
        try verification.fetch(FetchDescriptor<Habit>()).first { $0.id == changed.id }?.name
          == "Caller changed habit"
      )
      #expect(try verification.fetch(FetchDescriptor<Habit>()).contains { $0.id == inserted.id })
      #expect(try !verification.fetch(FetchDescriptor<Goal>()).contains { $0.id == deleted.id })
    }
  }

  @Test("progress, progress computation, standing, and management never close a goal")
  func noOperationImplicitlyClosesGoals() throws {
    for kind in GoalKind.allCases {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        testCase: .init(
          kind: kind,
          progressValues: [],
          deadline: "2024-07-03",
          closure: .harvested,
          expectedProgress: 0,
          expectedStanding: .onPace
        )
      )
      let progressOperations = GoalProgressOperations(context: context)
      let evaluation = try instant("2024-07-05T00:00:00Z")
      let zone = try timeZone("UTC")

      switch kind {
      case .accumulate:
        let exact = try progressOperations.append(
          amount: 10,
          to: goal,
          destination: .today,
          at: evaluation,
          timeZone: zone
        )
        #expect(goal.closureRawValue == nil)
        let over = try progressOperations.append(
          amount: 2,
          to: goal,
          destination: .yesterday,
          at: evaluation,
          timeZone: zone
        )
        #expect(goal.closureRawValue == nil)
        let progress = try GoalProgressComputation(context: context).snapshot(for: goal)
        #expect(normalizedProgress(of: progress) == 1.2)
        #expect(goal.closureRawValue == nil)
        #expect(try standingSnapshot(for: goal, progress: progress, at: "2024-07-05T00:00:00Z")?.standing == .pastDue)
        #expect(goal.closureRawValue == nil)
        try progressOperations.delete(exact, from: goal, at: evaluation, timeZone: zone)
        #expect(goal.closureRawValue == nil)
        #expect(over.goal === goal)
      case .measure:
        let exact = try progressOperations.append(
          value: 80,
          to: goal,
          destination: .today,
          at: evaluation,
          timeZone: zone
        )
        #expect(goal.closureRawValue == nil)
        let over = try progressOperations.append(
          value: 70,
          to: goal,
          destination: .yesterday,
          at: evaluation,
          timeZone: zone
        )
        #expect(goal.closureRawValue == nil)
        let progress = try GoalProgressComputation(context: context).snapshot(for: goal)
        #expect(normalizedProgress(of: progress) == 1)
        #expect(goal.closureRawValue == nil)
        #expect(try standingSnapshot(for: goal, progress: progress, at: "2024-07-05T00:00:00Z")?.standing == .pastDue)
        #expect(goal.closureRawValue == nil)
        try progressOperations.delete(exact, from: goal, at: evaluation, timeZone: zone)
        #expect(goal.closureRawValue == nil)
        #expect(over.goal === goal)
      }

      try GoalManagementOperations(context: context).update(
        goal,
        fields: GoalEditableFields(
          name: " Rescoped ",
          target: kind == .accumulate ? 20 : 75,
          unit: " units ",
          baseline: kind == .measure ? 100 : nil,
          deadline: try goalDate("2024-07-06")
        ),
        calendar: calendar(in: zone),
        timeZone: zone
      )
      #expect(goal.closureRawValue == nil)
    }
  }

  private func persistedGoal(
    in context: ModelContext,
    testCase: LifecycleCase,
    initialClosure: GoalClosure? = nil
  ) throws -> Goal {
    let createdAt = try instant("2024-07-01T00:00:00Z")
    let goal = Goal(
      name: testCase.kind == .accumulate ? "Read" : "Weight",
      kind: testCase.kind,
      target: testCase.kind == .accumulate ? 10 : 80,
      unit: testCase.kind == .accumulate ? "pages" : "kg",
      baseline: testCase.kind == .measure ? 100 : nil,
      deadline: try testCase.deadline.map(goalDate),
      createdAt: createdAt
    )
    goal.closureRawValue = initialClosure?.rawValue
    switch testCase.kind {
    case .accumulate:
      goal.entries = testCase.progressValues.enumerated().map { index, amount in
        GoalEntry(
          amount: amount,
          assignedDate: GoalDate(rawValue: "2024-07-01")!,
          appendedAt: createdAt.addingTimeInterval(TimeInterval(index)),
          appendSequence: index * 3
        )
      }
    case .measure:
      goal.readings = testCase.progressValues.enumerated().map { index, value in
        GoalReading(
          value: value,
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

  private func expectOwnershipError(
    _ expected: GoalLifecycleOperationError,
    goal: Goal,
    operations: GoalLifecycleOperations
  ) throws {
    try expectLifecycleError(expected) {
      try operations.close(goal, as: .harvested)
    }
    try expectLifecycleError(expected) {
      try operations.reopen(goal)
    }
  }

  private func expectLifecycleError(
    _ expected: GoalLifecycleOperationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected GoalLifecycleOperationError: \(expected)")
    } catch let error as GoalLifecycleOperationError {
      #expect(error == expected)
    }
  }

  private func standingSnapshot(
    for goal: Goal,
    progress: GoalProgressSnapshot,
    at evaluation: String
  ) throws -> GoalStandingSnapshot? {
    let zone = try timeZone("UTC")
    return try GoalStandingComputation().snapshot(
      for: goal,
      progress: progress,
      at: instant(evaluation),
      calendar: calendar(in: zone),
      timeZone: zone
    )
  }

  private func normalizedProgress(of snapshot: GoalProgressSnapshot) -> Double {
    switch snapshot {
    case .accumulate(let progress):
      progress.normalizedProgress
    case .measure(let progress):
      progress.normalizedProgress
    }
  }

  private func goalFacts(of goal: Goal) -> LifecycleGoalFacts {
    LifecycleGoalFacts(
      id: goal.id,
      persistentIdentifier: goal.persistentModelID,
      name: goal.name,
      kindRawValue: goal.kindRawValue,
      target: goal.target,
      unit: goal.unit,
      baseline: goal.baseline,
      deadlineKey: goal.deadlineKey,
      createdAt: goal.createdAt
    )
  }

  private func historyFacts(of goal: Goal) -> LifecycleHistoryFacts {
    LifecycleHistoryFacts(
      entryIdentifiers: (goal.entries ?? []).map(\.persistentModelID),
      entries: (goal.entries ?? []).map {
        LifecycleEntryFacts(
          id: $0.id,
          amount: $0.amount,
          assignedDateKey: $0.assignedDateKey,
          appendedAt: $0.appendedAt,
          appendSequence: $0.appendSequence
        )
      },
      readingIdentifiers: (goal.readings ?? []).map(\.persistentModelID),
      readings: (goal.readings ?? []).map {
        LifecycleReadingFacts(
          id: $0.id,
          value: $0.value,
          assignedDateKey: $0.assignedDateKey,
          appendedAt: $0.appendedAt,
          appendSequence: $0.appendSequence
        )
      }
    )
  }

  private func expectGoal(_ goal: Goal, equals facts: LifecycleGoalFacts) {
    #expect(goal.id == facts.id)
    #expect(goal.persistentModelID == facts.persistentIdentifier)
    #expect(goal.name == facts.name)
    #expect(goal.kindRawValue == facts.kindRawValue)
    #expect(goal.target == facts.target)
    #expect(goal.unit == facts.unit)
    #expect(goal.baseline == facts.baseline)
    #expect(goal.deadlineKey == facts.deadlineKey)
    #expect(goal.createdAt == facts.createdAt)
  }

  private func expectHistory(_ goal: Goal, equals facts: LifecycleHistoryFacts) {
    #expect((goal.entries ?? []).map(\.persistentModelID) == facts.entryIdentifiers)
    #expect(
      (goal.entries ?? []).map {
        LifecycleEntryFacts(
          id: $0.id,
          amount: $0.amount,
          assignedDateKey: $0.assignedDateKey,
          appendedAt: $0.appendedAt,
          appendSequence: $0.appendSequence
        )
      } == facts.entries
    )
    #expect((goal.readings ?? []).map(\.persistentModelID) == facts.readingIdentifiers)
    #expect(
      (goal.readings ?? []).map {
        LifecycleReadingFacts(
          id: $0.id,
          value: $0.value,
          assignedDateKey: $0.assignedDateKey,
          appendedAt: $0.appendedAt,
          appendSequence: $0.appendSequence
        )
      } == facts.readings
    )
    for entry in goal.entries ?? [] {
      #expect(entry.goal === goal)
    }
    for reading in goal.readings ?? [] {
      #expect(reading.goal === goal)
    }
  }

  private func expectPersistedHistory(_ goal: Goal, equals facts: LifecycleHistoryFacts) {
    #expect(Set((goal.entries ?? []).map(\.persistentModelID)) == Set(facts.entryIdentifiers))
    #expect(Set((goal.readings ?? []).map(\.persistentModelID)) == Set(facts.readingIdentifiers))
    #expect(Set((goal.entries ?? []).map(\.id)) == Set(facts.entries.map(\.id)))
    #expect(Set((goal.readings ?? []).map(\.id)) == Set(facts.readings.map(\.id)))
    for entry in goal.entries ?? [] {
      #expect(entry.goal === goal)
    }
    for reading in goal.readings ?? [] {
      #expect(reading.goal === goal)
    }
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private func goalDate(_ value: String) throws -> GoalDate {
    try #require(GoalDate(rawValue: value))
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
}

private struct LifecycleCase {
  let kind: GoalKind
  let progressValues: [Int]
  var deadline: String? = nil
  let closure: GoalClosure
  let expectedProgress: Double
  let expectedStanding: GoalStanding
  var evaluation = "2024-07-03T00:00:00Z"
}

private struct LifecycleGoalFacts {
  let id: UUID
  let persistentIdentifier: PersistentIdentifier
  let name: String
  let kindRawValue: String
  let target: Int
  let unit: String
  let baseline: Int?
  let deadlineKey: String?
  let createdAt: Date
}

private struct LifecycleHistoryFacts {
  let entryIdentifiers: [PersistentIdentifier]
  let entries: [LifecycleEntryFacts]
  let readingIdentifiers: [PersistentIdentifier]
  let readings: [LifecycleReadingFacts]
}

private struct LifecycleEntryFacts: Equatable {
  let id: UUID
  let amount: Int
  let assignedDateKey: String
  let appendedAt: Date
  let appendSequence: Int
}

private struct LifecycleReadingFacts: Equatable {
  let id: UUID
  let value: Int
  let assignedDateKey: String
  let appendedAt: Date
  let appendSequence: Int
}

private enum GoalLifecycleSaveFailure: Error, Equatable {
  case expected
}
