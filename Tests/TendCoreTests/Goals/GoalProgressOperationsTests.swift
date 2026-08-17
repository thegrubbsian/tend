import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Goal progress operations")
struct GoalProgressOperationsTests {
  @Test("accumulate appends Today and Yesterday as distinct ordered facts")
  func accumulateAppendsTodayAndYesterdayAsOrderedFacts() throws {
    let context = try makeContext()
    let goal = try persistedGoal(
      in: context,
      kind: .accumulate,
      target: 2,
      createdAt: instant("2024-07-03T12:00:00Z")
    )
    var saveCount = 0
    let operations = GoalProgressOperations(context: context) {
      saveCount += 1
      try context.save()
    }
    let appendedAt = try instant("2024-07-04T12:34:56Z")

    let first = try operations.append(
      amount: 2,
      to: goal,
      destination: .today,
      at: appendedAt,
      timeZone: timeZone("UTC")
    )
    let second = try operations.append(
      amount: 2,
      to: goal,
      destination: .yesterday,
      at: appendedAt,
      timeZone: timeZone("UTC")
    )
    let third = try operations.append(
      amount: 2,
      to: goal,
      destination: .today,
      at: appendedAt,
      timeZone: timeZone("UTC")
    )

    #expect(first.assignedDateKey == "2024-07-04")
    #expect(second.assignedDateKey == "2024-07-03")
    #expect(third.assignedDateKey == "2024-07-04")
    #expect([first, second, third].map(\.amount) == [2, 2, 2])
    #expect([first, second, third].map(\.appendedAt) == [appendedAt, appendedAt, appendedAt])
    #expect([first, second, third].map(\.appendSequence) == [0, 1, 2])
    #expect(Set([first.id, second.id, third.id]).count == 3)
    #expect(
      Set(goal.entries?.map(\.persistentModelID) ?? [])
        == Set([first, second, third].map(\.persistentModelID)))
    #expect(goal.readings?.isEmpty == true)
    #expect([first, second, third].allSatisfy { $0.goal === goal })
    #expect(try context.fetch(FetchDescriptor<GoalEntry>()).count == 3)
    #expect(saveCount == 3)
    #expect(!context.hasChanges)
  }

  @Test("measure appends every representable signed value in append order")
  func measureAppendsAllRepresentableValuesInOrder() throws {
    let context = try makeContext()
    let goal = try persistedGoal(
      in: context,
      kind: .measure,
      target: 80,
      baseline: 100,
      createdAt: instant("2024-01-01T00:00:00Z")
    )
    let operations = GoalProgressOperations(context: context)
    let appendedAt = try instant("2024-01-02T08:00:00Z")

    let minimum = try operations.append(
      value: Int.min,
      to: goal,
      destination: .today,
      at: appendedAt,
      timeZone: timeZone("UTC")
    )
    let maximum = try operations.append(
      value: Int.max,
      to: goal,
      destination: .yesterday,
      at: appendedAt,
      timeZone: timeZone("UTC")
    )
    let duplicate = try operations.append(
      value: Int.min,
      to: goal,
      destination: .today,
      at: appendedAt,
      timeZone: timeZone("UTC")
    )

    #expect([minimum, maximum, duplicate].map(\.value) == [Int.min, Int.max, Int.min])
    #expect([minimum, maximum, duplicate].map(\.appendSequence) == [0, 1, 2])
    #expect(
      [minimum, maximum, duplicate].map(\.assignedDateKey) == [
        "2024-01-02", "2024-01-01", "2024-01-02",
      ])
    #expect(goal.entries?.isEmpty == true)
    #expect(goal.readings?.count == 3)
    #expect(!context.hasChanges)
  }

  @Test("destination dates follow the explicit zone across DST, midnight, and zone changes")
  func destinationsUseExplicitLocalGoalDates() throws {
    let cases = [
      (
        instant: "2024-03-10T10:30:00Z", zone: "America/Los_Angeles", today: "2024-03-10",
        yesterday: "2024-03-09"
      ),
      (
        instant: "2024-11-03T09:30:00Z", zone: "America/Los_Angeles", today: "2024-11-03",
        yesterday: "2024-11-02"
      ),
      (instant: "2024-07-05T00:00:00Z", zone: "UTC", today: "2024-07-05", yesterday: "2024-07-04"),
      (
        instant: "2024-07-04T23:30:00Z", zone: "America/Los_Angeles", today: "2024-07-04",
        yesterday: "2024-07-03"
      ),
      (
        instant: "2024-07-04T23:30:00Z", zone: "Asia/Tokyo", today: "2024-07-05",
        yesterday: "2024-07-04"
      ),
    ]

    for value in cases {
      let context = try makeContext()
      let goal = try persistedGoal(
        in: context,
        kind: .accumulate,
        createdAt: instant("2024-03-01T00:00:00Z")
      )
      let operations = GoalProgressOperations(context: context)
      let operationInstant = try instant(value.instant)
      let zone = try timeZone(value.zone)

      let today = try operations.append(
        amount: 1,
        to: goal,
        destination: .today,
        at: operationInstant,
        timeZone: zone
      )
      let yesterday = try operations.append(
        amount: 1,
        to: goal,
        destination: .yesterday,
        at: operationInstant,
        timeZone: zone
      )

      #expect(today.assignedDateKey == value.today)
      #expect(yesterday.assignedDateKey == value.yesterday)
    }
  }

  @Test("a destination before the local creation day is unavailable")
  func destinationBeforeCreationDayIsUnavailable() throws {
    let context = try makeContext()
    let createdToday = try persistedGoal(
      in: context,
      kind: .accumulate,
      createdAt: instant("2024-07-04T12:00:00Z")
    )
    let operations = GoalProgressOperations(context: context)

    try expectProgressError(.destinationBeforeCreation(try goalDate("2024-07-03"))) {
      _ = try operations.append(
        amount: 1,
        to: createdToday,
        destination: .yesterday,
        at: instant("2024-07-04T20:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let createdYesterday = try persistedGoal(
      in: context,
      kind: .accumulate,
      createdAt: instant("2024-07-03T23:59:59Z")
    )
    let entry = try operations.append(
      amount: 1,
      to: createdYesterday,
      destination: .yesterday,
      at: instant("2024-07-04T00:00:00Z"),
      timeZone: timeZone("UTC")
    )
    #expect(entry.assignedDateKey == "2024-07-03")
  }

  @Test("invalid amount and cross-kind append fail without save or mutation")
  func invalidAmountAndCrossKindAppendFailBeforeMutation() throws {
    let context = try makeContext()
    let accumulate = try persistedGoal(in: context, kind: .accumulate)
    let measure = try persistedGoal(in: context, kind: .measure, baseline: 0)
    var saveCount = 0
    let operations = GoalProgressOperations(context: context) { saveCount += 1 }

    for amount in [0, -1, Int.min] {
      try expectProgressError(.invalidAmount(amount)) {
        _ = try operations.append(
          amount: amount,
          to: accumulate,
          destination: .today,
          at: instant("2024-01-02T00:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }
    }
    try expectProgressError(
      .wrongGoalKind(required: .accumulate, actualRawValue: GoalKind.measure.rawValue)
    ) {
      _ = try operations.append(
        amount: 1,
        to: measure,
        destination: .today,
        at: instant("2024-01-02T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    try expectProgressError(
      .wrongGoalKind(required: .measure, actualRawValue: GoalKind.accumulate.rawValue)
    ) {
      _ = try operations.append(
        value: 1,
        to: accumulate,
        destination: .today,
        at: instant("2024-01-02T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    #expect(saveCount == 0)
    #expect(accumulate.entries?.isEmpty == true)
    #expect(measure.readings?.isEmpty == true)
    #expect(try context.fetch(FetchDescriptor<GoalEntry>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<GoalReading>()).isEmpty)
  }

  @Test("malformed creation-time scalar configuration is rejected structurally")
  func malformedGoalScalarConfigurationIsRejected() throws {
    let cases: [(mutate: (Goal) -> Void, error: GoalProgressOperationError)] = [
      ({ $0.name = " \n " }, .invalidGoalConfiguration),
      ({ $0.name = " padded " }, .invalidGoalConfiguration),
      ({ $0.target = 0 }, .invalidGoalConfiguration),
      ({ $0.unit = "\t" }, .invalidGoalConfiguration),
      ({ $0.unit = " padded " }, .invalidGoalConfiguration),
      ({ $0.kindRawValue = "count" }, .invalidGoalConfiguration),
      ({ $0.baseline = 0 }, .invalidGoalConfiguration),
      (
        { goal in
          goal.kindRawValue = GoalKind.measure.rawValue
          goal.baseline = nil
        }, .invalidGoalConfiguration
      ),
      (
        { goal in
          goal.kindRawValue = GoalKind.measure.rawValue
          goal.baseline = goal.target
        }, .invalidGoalConfiguration
      ),
      ({ $0.deadlineKey = "tomorrow" }, .invalidDeadline("tomorrow")),
    ]

    for value in cases {
      let context = try makeContext()
      let goal = try persistedGoal(in: context, kind: .accumulate)
      value.mutate(goal)
      var saveCount = 0
      let operations = GoalProgressOperations(context: context) { saveCount += 1 }

      try expectProgressError(value.error) {
        _ = try operations.append(
          amount: 1,
          to: goal,
          destination: .today,
          at: instant("2025-01-01T00:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }
      #expect(saveCount == 0)
      #expect(goal.entries?.isEmpty == true)
      #expect(try context.fetch(FetchDescriptor<GoalEntry>()).isEmpty)
    }
  }

  @Test("an elapsed but parseable deadline never blocks progress")
  func elapsedDeadlineDoesNotBlockProgress() throws {
    let context = try makeContext()
    let goal = try persistedGoal(
      in: context,
      kind: .accumulate,
      deadline: goalDate("2024-01-02"),
      createdAt: instant("2024-01-01T00:00:00Z")
    )

    let entry = try GoalProgressOperations(context: context).append(
      amount: 1,
      to: goal,
      destination: .today,
      at: instant("2025-01-01T00:00:00Z"),
      timeZone: timeZone("UTC")
    )

    #expect(entry.assignedDateKey == "2025-01-01")
  }

  @Test("both inverse collections must be persisted and kind-consistent")
  func completeInverseGraphsAreRequired() throws {

    do {
      let context = try makeContext()
      let goal = try persistedGoal(in: context, kind: .accumulate)
      let reading = GoalReading(
        value: 1,
        assignedDate: try goalDate("2024-01-01"),
        appendedAt: try instant("2024-01-01T00:00:00Z"),
        appendSequence: 0,
        goal: goal
      )
      context.insert(reading)
      try context.save()
      try expectProgressError(.invalidGoalGraph) {
        _ = try GoalProgressOperations(context: context).append(
          amount: 1,
          to: goal,
          destination: .today,
          at: instant("2024-01-02T00:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }
      #expect(goal.entries?.isEmpty == true)
      #expect(goal.readings?.map(\.persistentModelID) == [reading.persistentModelID])
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoal(in: context, kind: .accumulate)
      let detached = GoalEntry(
        amount: 1,
        assignedDate: try goalDate("2024-01-01"),
        appendedAt: try instant("2024-01-01T00:00:00Z"),
        appendSequence: 0
      )
      goal.entries = [detached]
      try expectProgressError(.invalidGoalGraph) {
        _ = try GoalProgressOperations(context: context).append(
          amount: 1,
          to: goal,
          destination: .today,
          at: instant("2024-01-02T00:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }
    }
  }

  @Test("fetched children must exactly reconcile with the relationship arrays")
  func fetchedAndArrayGraphMismatchIsRejected() throws {
    let container = try TendModelContainer.inMemory()
    let firstContext = ModelContext(container)
    let goal = try persistedGoal(in: firstContext, kind: .accumulate)
    _ = goal.entries

    let secondContext = ModelContext(container)
    let secondGoal = try #require(secondContext.fetch(FetchDescriptor<Goal>()).first)
    let hidden = GoalEntry(
      amount: 1,
      assignedDate: try goalDate("2024-01-01"),
      appendedAt: try instant("2024-01-01T00:00:00Z"),
      appendSequence: 0,
      goal: secondGoal
    )
    secondContext.insert(hidden)
    try secondContext.save()

    var saveCount = 0
    let operations = GoalProgressOperations(context: firstContext) { saveCount += 1 }
    try expectProgressError(.invalidGoalGraph) {
      _ = try operations.append(
        amount: 1,
        to: goal,
        destination: .today,
        at: instant("2024-01-02T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    #expect(saveCount == 0)
    #expect(goal.entries?.isEmpty == true)
  }

  @Test("malformed dates, amounts, and sequence histories fail before mutation")
  func invalidExistingProgressStateFailsBeforeMutation() throws {
    let cases: [(mutate: (GoalEntry) -> Void, error: GoalProgressOperationError)] = [
      ({ $0.assignedDateKey = "yesterday" }, .invalidAssignedDate("yesterday")),
      ({ $0.amount = 0 }, .invalidExistingAmount(0)),
      ({ $0.amount = -2 }, .invalidExistingAmount(-2)),
      ({ $0.appendSequence = -1 }, .invalidSequence(-1)),
      ({ $0.appendSequence = Int.max }, .sequenceOverflow),
    ]

    for value in cases {
      let context = try makeContext()
      let goal = try persistedGoalWithEntries(in: context, sequences: [0])
      let original = try #require(goal.entries?.first)
      value.mutate(original)
      var saveCount = 0
      let operations = GoalProgressOperations(context: context) { saveCount += 1 }

      try expectProgressError(value.error) {
        _ = try operations.append(
          amount: 1,
          to: goal,
          destination: .today,
          at: instant("2024-01-02T00:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }
      #expect(saveCount == 0)
      #expect(goal.entries?.count == 1)
      #expect(try context.fetch(FetchDescriptor<GoalEntry>()).count == 1)
    }

    let context = try makeContext()
    let goal = try persistedGoalWithEntries(in: context, sequences: [2, 2])
    var saveCount = 0
    let operations = GoalProgressOperations(context: context) { saveCount += 1 }
    try expectProgressError(.duplicateSequence(2)) {
      _ = try operations.append(
        amount: 1,
        to: goal,
        destination: .today,
        at: instant("2024-01-02T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
    #expect(saveCount == 0)
    #expect(goal.entries?.map(\.appendSequence) == [2, 2])
  }

  @Test("detached, deleted, and foreign-context goals are rejected")
  func invalidGoalOwnershipIsRejected() throws {
    let context = try makeContext()
    let operations = GoalProgressOperations(context: context)
    let detached = Goal(name: "Detached", kind: .accumulate, target: 1)
    try expectProgressError(.detachedGoal) {
      _ = try operations.append(
        amount: 1,
        to: detached,
        destination: .today,
        at: instant("2024-01-02T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let deleted = try persistedGoal(in: context, kind: .accumulate)
    context.delete(deleted)
    try expectProgressError(.detachedGoal) {
      _ = try operations.append(
        amount: 1,
        to: deleted,
        destination: .today,
        at: instant("2024-01-02T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let foreignContext = try makeContext()
    let foreign = try persistedGoal(in: foreignContext, kind: .accumulate)
    try expectProgressError(.foreignGoal) {
      _ = try operations.append(
        amount: 1,
        to: foreign,
        destination: .today,
        at: instant("2024-01-02T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }
  }

  @Test("append save failure removes only the new child and restores the exact prior graph")
  func appendSaveFailureIsOperationLocal() throws {
    let context = try makeContext()
    let goal = try persistedGoalWithEntries(in: context, sequences: [3, 8])
    let priorEntries = try #require(goal.entries)
    let priorIDs = priorEntries.map(\.persistentModelID)
    let priorSequences = priorEntries.map(\.appendSequence)
    let priorUUIDs = Set(priorEntries.map(\.id))
    let unrelated = Habit(name: "Pending", cadence: .daily, target: 1)
    context.insert(unrelated)
    var inserted: GoalEntry?
    var saveCount = 0
    let operations = GoalProgressOperations(context: context) {
      saveCount += 1
      inserted = context.insertedModelsArray.compactMap { $0 as? GoalEntry }.first
      throw GoalProgressSaveFailure.expected
    }

    do {
      _ = try operations.append(
        amount: 5,
        to: goal,
        destination: .today,
        at: instant("2024-01-02T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected save failure")
    } catch let error as GoalProgressSaveFailure {
      #expect(error == .expected)
    }

    #expect(saveCount == 1)
    #expect(inserted?.modelContext == nil)
    #expect(inserted?.goal == nil)
    #expect(goal.entries?.map(\.persistentModelID) == priorIDs)
    #expect(goal.entries?.map(\.appendSequence) == priorSequences)
    #expect(
      Set(try context.fetch(FetchDescriptor<GoalEntry>()).map(\.persistentModelID)) == Set(priorIDs)
    )
    #expect(context.insertedModelsArray.map(\.persistentModelID) == [unrelated.persistentModelID])
    #expect(context.deletedModelsArray.isEmpty)
    #expect(context.hasChanges)

    try context.save()
    let verification = ModelContext(context.container)
    let verifiedGoal = try #require(
      verification.fetch(FetchDescriptor<Goal>()).first { $0.id == goal.id }
    )
    let verifiedEntries = try #require(verifiedGoal.entries).sorted {
      $0.appendSequence < $1.appendSequence
    }
    #expect(verifiedEntries.count == 2)
    #expect(Set(verifiedEntries.map(\.id)) == priorUUIDs)
    #expect(verifiedEntries.map(\.amount) == [1, 2])
    #expect(verifiedEntries.map(\.assignedDateKey) == ["2024-01-01", "2024-01-01"])
    #expect(verifiedEntries.map(\.appendSequence) == [3, 8])
    #expect(try verification.fetch(FetchDescriptor<Habit>()).map(\.id) == [unrelated.id])
  }

  @Test("delete supports first, middle, last, and only without renumbering survivors")
  func deleteEveryPositionWithoutRenumbering() throws {
    for index in 0..<4 {
      let context = try makeContext()
      let goal = try persistedGoalWithEntries(in: context, sequences: [0, 4, 9, 15])
      let entries = try #require(goal.entries)
      let removed = entries[index]
      let expected = Array(entries[..<index] + entries[(index + 1)...])
      var saveCount = 0
      let operations = GoalProgressOperations(context: context) {
        saveCount += 1
        try context.save()
      }

      try operations.delete(
        removed,
        from: goal,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )

      #expect(
        Set(goal.entries?.map(\.persistentModelID) ?? []) == Set(expected.map(\.persistentModelID)))
      #expect(Set(goal.entries?.map(\.appendSequence) ?? []) == Set(expected.map(\.appendSequence)))
      #expect(removed.modelContext == nil)
      #expect(removed.goal == nil)
      #expect(
        Set(try context.fetch(FetchDescriptor<GoalEntry>()).map(\.persistentModelID))
          == Set(expected.map(\.persistentModelID)))
      #expect(saveCount == 1)
      #expect(!context.hasChanges)
    }

    let context = try makeContext()
    let goal = try persistedGoalWithReadings(in: context, sequences: [7])
    let reading = try #require(goal.readings?.first)
    try GoalProgressOperations(context: context).delete(
      reading,
      from: goal,
      at: instant("2024-01-02T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    #expect(goal.readings?.isEmpty == true)
    #expect(try context.fetch(FetchDescriptor<GoalReading>()).isEmpty)

    let maximumContext = try makeContext()
    let maximumGoal = try persistedGoalWithEntries(in: maximumContext, sequences: [Int.max])
    let maximumEntry = try #require(maximumGoal.entries?.first)
    try GoalProgressOperations(context: maximumContext).delete(
      maximumEntry,
      from: maximumGoal,
      at: instant("2024-01-02T12:00:00Z"),
      timeZone: timeZone("UTC")
    )
    #expect(maximumGoal.entries?.isEmpty == true)
  }

  @Test("delete eligibility uses assigned GoalDate at exact local day boundaries")
  func deleteEligibilityUsesAssignedDateNotAppendTimestamp() throws {
    let cases = [
      (
        zone: "UTC", assigned: "2024-07-04", allowedAt: "2024-07-05T00:00:00Z",
        rejectedAt: "2024-07-06T00:00:00Z"
      ),
      (
        zone: "America/Los_Angeles", assigned: "2024-03-09", allowedAt: "2024-03-11T06:59:59Z",
        rejectedAt: "2024-03-11T07:00:00Z"
      ),
      (
        zone: "America/Los_Angeles", assigned: "2024-11-02", allowedAt: "2024-11-04T07:59:59Z",
        rejectedAt: "2024-11-04T08:00:00Z"
      ),
    ]

    for value in cases {
      let allowedContext = try makeContext()
      let allowedGoal = try persistedGoalWithEntries(
        in: allowedContext,
        sequences: [0],
        assignedDate: goalDate(value.assigned),
        appendedAt: instant("2030-01-01T00:00:00Z")
      )
      try GoalProgressOperations(context: allowedContext).delete(
        try #require(allowedGoal.entries?.first),
        from: allowedGoal,
        at: instant(value.allowedAt),
        timeZone: timeZone(value.zone)
      )
      #expect(allowedGoal.entries?.isEmpty == true)

      let rejectedContext = try makeContext()
      let rejectedGoal = try persistedGoalWithEntries(
        in: rejectedContext,
        sequences: [0],
        assignedDate: goalDate(value.assigned),
        appendedAt: instant("2030-01-01T00:00:00Z")
      )
      let rejected = try #require(rejectedGoal.entries?.first)
      try expectProgressError(.destinationNotEditable(try goalDate(value.assigned))) {
        try GoalProgressOperations(context: rejectedContext).delete(
          rejected,
          from: rejectedGoal,
          at: instant(value.rejectedAt),
          timeZone: timeZone(value.zone)
        )
      }
      #expect(rejectedGoal.entries?.map(\.persistentModelID) == [rejected.persistentModelID])
    }

  }

  @Test("a time-zone change can make the same stored date eligible or immutable")
  func timeZoneChangeReevaluatesStoredDate() throws {
    let operationInstant = try instant("2024-07-04T23:30:00Z")

    let losAngelesContext = try makeContext()
    let losAngelesGoal = try persistedGoalWithEntries(
      in: losAngelesContext,
      sequences: [0],
      assignedDate: goalDate("2024-07-03")
    )
    try GoalProgressOperations(context: losAngelesContext).delete(
      try #require(losAngelesGoal.entries?.first),
      from: losAngelesGoal,
      at: operationInstant,
      timeZone: timeZone("America/Los_Angeles")
    )

    let tokyoContext = try makeContext()
    let tokyoGoal = try persistedGoalWithEntries(
      in: tokyoContext,
      sequences: [0],
      assignedDate: goalDate("2024-07-03")
    )
    let tokyoEntry = try #require(tokyoGoal.entries?.first)
    try expectProgressError(.destinationNotEditable(try goalDate("2024-07-03"))) {
      try GoalProgressOperations(context: tokyoContext).delete(
        tokyoEntry,
        from: tokyoGoal,
        at: operationInstant,
        timeZone: timeZone("Asia/Tokyo")
      )
    }
  }

  @Test("delete rejects detached, foreign, cross-kind, old, future, and inconsistent children")
  func deleteRejectsInvalidChildrenWithoutSaving() throws {
    let context = try makeContext()
    let goal = try persistedGoalWithEntries(in: context, sequences: [0])
    var saveCount = 0
    let operations = GoalProgressOperations(context: context) { saveCount += 1 }
    let detached = GoalEntry(
      amount: 1,
      assignedDate: try goalDate("2024-01-02"),
      appendedAt: try instant("2024-01-02T00:00:00Z"),
      appendSequence: 1
    )
    try expectProgressError(.detachedEntry) {
      try operations.delete(
        detached,
        from: goal,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let foreignContext = try makeContext()
    let foreignContextGoal = try persistedGoalWithEntries(in: foreignContext, sequences: [0])
    let foreignContextEntry = try #require(foreignContextGoal.entries?.first)
    try expectProgressError(.foreignEntry) {
      try operations.delete(
        foreignContextEntry,
        from: goal,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let deletedGoal = try persistedGoalWithEntries(in: context, sequences: [0])
    let deletedEntry = try #require(deletedGoal.entries?.first)
    context.delete(deletedEntry)
    try expectProgressError(.detachedEntry) {
      try operations.delete(
        deletedEntry,
        from: goal,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let other = try persistedGoalWithEntries(in: context, sequences: [0])
    let foreignEntry = try #require(other.entries?.first)
    try expectProgressError(.childNotFound) {
      try operations.delete(
        foreignEntry,
        from: goal,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let readingGoal = try persistedGoalWithReadings(in: context, sequences: [0])
    let reading = try #require(readingGoal.readings?.first)
    try expectProgressError(
      .wrongGoalKind(required: .measure, actualRawValue: GoalKind.accumulate.rawValue)
    ) {
      try operations.delete(
        reading,
        from: goal,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    let measureContext = try makeContext()
    let measureGoal = try persistedGoalWithReadings(in: measureContext, sequences: [0])
    let measureOperations = GoalProgressOperations(context: measureContext)
    let foreignReadingContext = try makeContext()
    let foreignReadingGoal = try persistedGoalWithReadings(
      in: foreignReadingContext,
      sequences: [0]
    )
    let foreignReading = try #require(foreignReadingGoal.readings?.first)
    try expectProgressError(.foreignReading) {
      try measureOperations.delete(
        foreignReading,
        from: measureGoal,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    for key in ["2023-12-31", "2024-01-03"] {
      let invalidContext = try makeContext()
      let invalidGoal = try persistedGoalWithEntries(
        in: invalidContext,
        sequences: [0],
        assignedDate: goalDate(key)
      )
      let invalidEntry = try #require(invalidGoal.entries?.first)
      var invalidSaveCount = 0
      let invalidOperations = GoalProgressOperations(context: invalidContext) {
        invalidSaveCount += 1
      }
      try expectProgressError(.destinationNotEditable(try goalDate(key))) {
        try invalidOperations.delete(
          invalidEntry,
          from: invalidGoal,
          at: instant("2024-01-02T12:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }
      #expect(invalidSaveCount == 0)
      #expect(invalidGoal.entries?.count == 1)
    }
    #expect(saveCount == 0)
    #expect(goal.entries?.count == 1)
  }

  @Test("delete save failure restores the same model, facts, index, and unrelated pending work")
  func deleteSaveFailureRestoresExactlyAndLocally() throws {
    let context = try makeContext()
    let goal = try persistedGoalWithEntries(in: context, sequences: [2, 7, 11])
    let original = try #require(goal.entries)
    let originalIDs = original.map(\.persistentModelID)
    let originalUUIDs = Set(original.map(\.id))
    let deleted = original[1]
    let originalFacts = (
      id: deleted.id,
      amount: deleted.amount,
      date: deleted.assignedDateKey,
      appendedAt: deleted.appendedAt,
      sequence: deleted.appendSequence
    )
    let unrelated = Habit(name: "Pending", cadence: .daily, target: 1)
    context.insert(unrelated)
    var saveCount = 0
    let operations = GoalProgressOperations(context: context) {
      saveCount += 1
      #expect(deleted.isDeleted)
      throw GoalProgressSaveFailure.expected
    }

    do {
      try operations.delete(
        deleted,
        from: goal,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected save failure")
    } catch let error as GoalProgressSaveFailure {
      #expect(error == .expected)
    }

    #expect(saveCount == 1)
    #expect(deleted.modelContext === context)
    #expect(!deleted.isDeleted)
    #expect(deleted.goal === goal)
    #expect(deleted.id == originalFacts.id)
    #expect(deleted.amount == originalFacts.amount)
    #expect(deleted.assignedDateKey == originalFacts.date)
    #expect(deleted.appendedAt == originalFacts.appendedAt)
    #expect(deleted.appendSequence == originalFacts.sequence)
    #expect(goal.entries?.map(\.persistentModelID) == originalIDs)
    #expect(context.deletedModelsArray.isEmpty)
    #expect(context.insertedModelsArray.map(\.persistentModelID) == [unrelated.persistentModelID])
    #expect(context.hasChanges)

    try context.save()
    let verification = ModelContext(context.container)
    let verifiedGoal = try #require(
      verification.fetch(FetchDescriptor<Goal>()).first { $0.id == goal.id }
    )
    let verifiedEntries = try #require(verifiedGoal.entries).sorted {
      $0.appendSequence < $1.appendSequence
    }
    #expect(verifiedEntries.count == 3)
    #expect(Set(verifiedEntries.map(\.id)) == originalUUIDs)
    #expect(verifiedEntries.map(\.amount) == [1, 2, 3])
    #expect(
      verifiedEntries.map(\.assignedDateKey) == [
        "2024-01-01", "2024-01-01", "2024-01-01",
      ])
    #expect(verifiedEntries.map(\.appendSequence) == [2, 7, 11])
    let verifiedDeleted = try #require(verifiedEntries.first { $0.id == originalFacts.id })
    #expect(verifiedDeleted.amount == originalFacts.amount)
    #expect(verifiedDeleted.assignedDateKey == originalFacts.date)
    #expect(verifiedDeleted.appendedAt == originalFacts.appendedAt)
    #expect(verifiedDeleted.appendSequence == originalFacts.sequence)
    #expect(try verification.fetch(FetchDescriptor<Habit>()).map(\.id) == [unrelated.id])
  }

  @Test("recognized closure rejects all four progress mutation paths before mutation or save")
  func closedGoalsRejectEveryMutationPath() throws {
    do {
      let context = try makeContext()
      let goal = try persistedGoalWithEntries(in: context, sequences: [2])
      goal.closureRawValue = GoalClosure.harvested.rawValue
      try context.save()
      let entryIDs = goal.entries?.map(\.persistentModelID)
      var saveCount = 0
      let operations = GoalProgressOperations(context: context) { saveCount += 1 }

      try expectProgressError(.closedGoal(.harvested)) {
        _ = try operations.append(
          amount: 3,
          to: goal,
          destination: .today,
          at: instant("2024-01-02T12:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }

      #expect(goal.entries?.map(\.persistentModelID) == entryIDs)
      #expect(try context.fetch(FetchDescriptor<GoalEntry>()).count == 1)
      #expect(context.insertedModelsArray.isEmpty)
      #expect(saveCount == 0)
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoalWithEntries(in: context, sequences: [2])
      let entry = try #require(goal.entries?.first)
      goal.closureRawValue = GoalClosure.letGo.rawValue
      try context.save()
      let entryIDs = goal.entries?.map(\.persistentModelID)
      var saveCount = 0
      let operations = GoalProgressOperations(context: context) { saveCount += 1 }

      try expectProgressError(.closedGoal(.letGo)) {
        try operations.delete(
          entry,
          from: goal,
          at: instant("2024-01-02T12:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }

      #expect(goal.entries?.map(\.persistentModelID) == entryIDs)
      #expect(entry.goal === goal)
      #expect(!entry.isDeleted)
      #expect(context.deletedModelsArray.isEmpty)
      #expect(saveCount == 0)
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoalWithReadings(in: context, sequences: [2])
      goal.closureRawValue = GoalClosure.letGo.rawValue
      try context.save()
      let readingIDs = goal.readings?.map(\.persistentModelID)
      var saveCount = 0
      let operations = GoalProgressOperations(context: context) { saveCount += 1 }

      try expectProgressError(.closedGoal(.letGo)) {
        _ = try operations.append(
          value: 90,
          to: goal,
          destination: .today,
          at: instant("2024-01-02T12:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }

      #expect(goal.readings?.map(\.persistentModelID) == readingIDs)
      #expect(try context.fetch(FetchDescriptor<GoalReading>()).count == 1)
      #expect(context.insertedModelsArray.isEmpty)
      #expect(saveCount == 0)
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoalWithReadings(in: context, sequences: [2])
      let reading = try #require(goal.readings?.first)
      goal.closureRawValue = GoalClosure.harvested.rawValue
      try context.save()
      let readingIDs = goal.readings?.map(\.persistentModelID)
      var saveCount = 0
      let operations = GoalProgressOperations(context: context) { saveCount += 1 }

      try expectProgressError(.closedGoal(.harvested)) {
        try operations.delete(
          reading,
          from: goal,
          at: instant("2024-01-02T12:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }

      #expect(goal.readings?.map(\.persistentModelID) == readingIDs)
      #expect(reading.goal === goal)
      #expect(!reading.isDeleted)
      #expect(context.deletedModelsArray.isEmpty)
      #expect(saveCount == 0)
    }
  }

  @Test("corrupt closure rejects all four progress mutation paths before graph validation")
  func corruptClosureRejectsEveryMutationPath() throws {
    do {
      let context = try makeContext()
      let goal = try persistedGoalWithEntries(in: context, sequences: [2])
      goal.closureRawValue = "future-disposition"
      goal.name = ""
      var saveCount = 0
      let operations = GoalProgressOperations(context: context) { saveCount += 1 }

      try expectProgressError(.invalidClosure("future-disposition")) {
        _ = try operations.append(
          amount: 3,
          to: goal,
          destination: .today,
          at: instant("2024-01-02T12:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }
      let entry = try #require(goal.entries?.first)
      try expectProgressError(.invalidClosure("future-disposition")) {
        try operations.delete(
          entry,
          from: goal,
          at: instant("2024-01-02T12:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }

      #expect(entry.goal === goal)
      #expect(!entry.isDeleted)
      #expect(goal.entries?.count == 1)
      #expect(saveCount == 0)
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoalWithReadings(in: context, sequences: [2])
      goal.closureRawValue = "future-disposition"
      goal.name = ""
      var saveCount = 0
      let operations = GoalProgressOperations(context: context) { saveCount += 1 }

      try expectProgressError(.invalidClosure("future-disposition")) {
        _ = try operations.append(
          value: 90,
          to: goal,
          destination: .today,
          at: instant("2024-01-02T12:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }
      let reading = try #require(goal.readings?.first)
      try expectProgressError(.invalidClosure("future-disposition")) {
        try operations.delete(
          reading,
          from: goal,
          at: instant("2024-01-02T12:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }

      #expect(reading.goal === goal)
      #expect(!reading.isDeleted)
      #expect(goal.readings?.count == 1)
      #expect(saveCount == 0)
    }
  }

  @Test("reopening restores unchanged Today and Yesterday append and delete eligibility")
  func reopenedGoalsResumeEveryMutationPath() throws {
    var lifecycleSaveCount = 0
    var progressSaveCount = 0

    do {
      let context = try makeContext()
      let goal = try persistedGoalWithEntries(in: context, sequences: [2])
      let existing = try #require(goal.entries?.first)
      goal.closureRawValue = GoalClosure.harvested.rawValue
      try context.save()
      let lifecycle = GoalLifecycleOperations(context: context) {
        lifecycleSaveCount += 1
        try context.save()
      }
      let progress = GoalProgressOperations(context: context) {
        progressSaveCount += 1
        try context.save()
      }

      try lifecycle.reopen(goal)
      let appended = try progress.append(
        amount: 3,
        to: goal,
        destination: .today,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
      try progress.delete(
        existing,
        from: goal,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )

      #expect(goal.closureRawValue == nil)
      #expect(appended.assignedDateKey == "2024-01-02")
      #expect(appended.goal === goal)
      #expect(goal.entries?.map(\.persistentModelID) == [appended.persistentModelID])
    }

    do {
      let context = try makeContext()
      let goal = try persistedGoalWithReadings(in: context, sequences: [2])
      let existing = try #require(goal.readings?.first)
      goal.closureRawValue = GoalClosure.letGo.rawValue
      try context.save()
      let lifecycle = GoalLifecycleOperations(context: context) {
        lifecycleSaveCount += 1
        try context.save()
      }
      let progress = GoalProgressOperations(context: context) {
        progressSaveCount += 1
        try context.save()
      }

      try lifecycle.reopen(goal)
      let appended = try progress.append(
        value: 90,
        to: goal,
        destination: .yesterday,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
      try progress.delete(
        existing,
        from: goal,
        at: instant("2024-01-02T12:00:00Z"),
        timeZone: timeZone("UTC")
      )

      #expect(goal.closureRawValue == nil)
      #expect(appended.assignedDateKey == "2024-01-01")
      #expect(appended.goal === goal)
      #expect(goal.readings?.map(\.persistentModelID) == [appended.persistentModelID])
    }

    #expect(lifecycleSaveCount == 2)
    #expect(progressSaveCount == 4)
  }

  private func persistedGoal(
    in context: ModelContext,
    kind: GoalKind,
    target: Int = 10,
    baseline: Int? = nil,
    deadline: GoalDate? = nil,
    createdAt: Date = Date(timeIntervalSince1970: 1_704_067_200)
  ) throws -> Goal {
    let goal = Goal(
      name: kind == .accumulate ? "Read" : "Weight",
      kind: kind,
      target: target,
      unit: kind == .accumulate ? "pages" : "kg",
      baseline: kind == .measure ? (baseline ?? 20) : baseline,
      deadline: deadline,
      createdAt: createdAt
    )
    context.insert(goal)
    try context.save()
    return goal
  }

  private func persistedGoalWithEntries(
    in context: ModelContext,
    sequences: [Int],
    assignedDate: GoalDate = GoalDate(rawValue: "2024-01-01")!,
    appendedAt: Date = Date(timeIntervalSince1970: 1_704_067_200)
  ) throws -> Goal {
    let goal = Goal(
      name: "Read",
      kind: .accumulate,
      target: 10,
      unit: "pages",
      createdAt: Date(timeIntervalSince1970: 1_704_067_200)
    )
    goal.entries = sequences.enumerated().map { index, sequence in
      GoalEntry(
        amount: index + 1,
        assignedDate: assignedDate,
        appendedAt: appendedAt.addingTimeInterval(TimeInterval(index)),
        appendSequence: sequence
      )
    }
    context.insert(goal)
    try context.save()
    return goal
  }

  private func persistedGoalWithReadings(
    in context: ModelContext,
    sequences: [Int],
    assignedDate: GoalDate = GoalDate(rawValue: "2024-01-01")!,
    appendedAt: Date = Date(timeIntervalSince1970: 1_704_067_200)
  ) throws -> Goal {
    let goal = Goal(
      name: "Weight",
      kind: .measure,
      target: 80,
      unit: "kg",
      baseline: 100,
      createdAt: Date(timeIntervalSince1970: 1_704_067_200)
    )
    goal.readings = sequences.enumerated().map { index, sequence in
      GoalReading(
        value: 100 - index,
        assignedDate: assignedDate,
        appendedAt: appendedAt.addingTimeInterval(TimeInterval(index)),
        appendSequence: sequence
      )
    }
    context.insert(goal)
    try context.save()
    return goal
  }

  private func expectProgressError(
    _ expected: GoalProgressOperationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected GoalProgressOperationError: \(expected)")
    } catch let error as GoalProgressOperationError {
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

  private func goalDate(_ value: String) throws -> GoalDate {
    try #require(GoalDate(rawValue: value))
  }
}

private enum GoalProgressSaveFailure: Error, Equatable {
  case expected
}
