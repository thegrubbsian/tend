import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Goal creation operations")
struct GoalCreationOperationsTests {
  @Test("accumulate creation normalizes fields and saves one childless goal")
  func accumulateCreationNormalizesAndSavesOneChildlessGoal() throws {
    let context = try makeContext()
    let createdAt = try instant("2024-07-04T12:34:56Z")
    var saveCount = 0
    let operations = GoalCreationOperations(context: context) {
      saveCount += 1
      try context.save()
    }

    let goal = try operations.create(
      fields: GoalCreationFields(
        name: "  Read   deeply \n",
        kind: .accumulate,
        target: 12
      ),
      at: createdAt,
      timeZone: timeZone("UTC")
    )

    #expect(goal.name == "Read   deeply")
    #expect(goal.kindRawValue == GoalKind.accumulate.rawValue)
    #expect(goal.target == 12)
    #expect(goal.unit == "times")
    #expect(goal.baseline == nil)
    #expect(goal.deadlineKey == nil)
    #expect(goal.createdAt == createdAt)
    #expect(goal.entries?.isEmpty == true)
    #expect(goal.readings?.isEmpty == true)
    #expect(try context.fetch(FetchDescriptor<Goal>()).map(\.id) == [goal.id])
    #expect(try context.fetch(FetchDescriptor<GoalEntry>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<GoalReading>()).isEmpty)
    #expect(saveCount == 1)
    #expect(!context.hasChanges)
  }

  @Test("accumulate creation preserves a custom unit and deadline and repeated calls stay distinct")
  func accumulateCreationPreservesCustomConfigurationAndDistinctActions() throws {
    let context = try makeContext()
    let deadline = try goalDate("2024-12-31")
    let fields = GoalCreationFields(
      name: "  Publish  ",
      kind: .accumulate,
      target: .max,
      unit: "  pages  ",
      deadline: deadline
    )
    let operations = GoalCreationOperations(context: context)
    let createdAt = try instant("2024-12-31T12:00:00Z")

    let first = try operations.create(
      fields: fields,
      at: createdAt,
      timeZone: timeZone("UTC")
    )
    let second = try operations.create(
      fields: fields,
      at: createdAt,
      timeZone: timeZone("UTC")
    )

    #expect(first.name == "Publish")
    #expect(first.unit == "pages")
    #expect(first.target == .max)
    #expect(first.deadlineKey == deadline.rawValue)
    #expect(first.id != second.id)
    #expect(first.persistentModelID != second.persistentModelID)
    #expect(try context.fetch(FetchDescriptor<Goal>()).count == 2)
    #expect(!context.hasChanges)
  }

  @Test("measure creation preserves increasing and decreasing baselines without derived progress")
  func measureCreationPreservesDirectionOnlyInItsBaselineAndTarget() throws {
    let context = try makeContext()
    let operations = GoalCreationOperations(context: context)
    let cases = [
      (name: "Increase", baseline: -10, target: 20),
      (name: "From zero", baseline: 0, target: 20),
      (name: "Decrease", baseline: 100, target: 80),
    ]

    for value in cases {
      let goal = try operations.create(
        fields: GoalCreationFields(
          name: value.name,
          kind: .measure,
          target: value.target,
          unit: "kg",
          baseline: value.baseline
        ),
        at: try instant("2024-01-01T00:00:00Z"),
        timeZone: timeZone("UTC")
      )

      #expect(goal.kindRawValue == GoalKind.measure.rawValue)
      #expect(goal.baseline == value.baseline)
      #expect(goal.target == value.target)
      #expect(goal.entries?.isEmpty == true)
      #expect(goal.readings?.isEmpty == true)
    }

    #expect(try context.fetch(FetchDescriptor<Goal>()).count == cases.count)
    #expect(try context.fetch(FetchDescriptor<GoalEntry>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<GoalReading>()).isEmpty)
    #expect(!context.hasChanges)
  }

  @Test("invalid fields fail with typed errors before insertion or save")
  func invalidFieldsFailBeforeInsertionOrSave() throws {
    let context = try makeContext()
    var saveCount = 0
    let operations = GoalCreationOperations(context: context) {
      saveCount += 1
      try context.save()
    }
    let cases: [(GoalCreationFields, GoalCreationOperationError)] = [
      (
        GoalCreationFields(name: " \n\t ", kind: .accumulate, target: 1),
        .emptyName
      ),
      (
        GoalCreationFields(name: "Read", kind: .accumulate, target: 0),
        .invalidTarget(0)
      ),
      (
        GoalCreationFields(name: "Read", kind: .accumulate, target: -1),
        .invalidTarget(-1)
      ),
      (
        GoalCreationFields(name: "Read", kind: .accumulate, target: 1, unit: " \t"),
        .emptyUnit
      ),
      (
        GoalCreationFields(name: "Read", kind: .accumulate, target: 1, baseline: 0),
        .accumulateBaseline(0)
      ),
      (
        GoalCreationFields(name: "Weight", kind: .measure, target: 80),
        .missingMeasureBaseline
      ),
      (
        GoalCreationFields(name: "Weight", kind: .measure, target: 80, baseline: 80),
        .measureBaselineEqualsTarget(80)
      ),
    ]

    for (fields, expectedError) in cases {
      try expectCreationError(expectedError) {
        _ = try operations.create(
          fields: fields,
          at: instant("2024-01-01T12:00:00Z"),
          timeZone: timeZone("UTC")
        )
      }
      #expect(try context.fetch(FetchDescriptor<Goal>()).isEmpty)
      #expect(saveCount == 0)
      #expect(!context.hasChanges)
    }
  }

  @Test("deadline validity uses the following local-day boundary across zones and DST")
  func deadlineValidityUsesFollowingLocalDayBoundaryAcrossZonesAndDST() throws {
    let cases = [
      (
        key: "2024-07-04",
        zone: "Asia/Tokyo",
        expectedBoundary: "2024-07-04T15:00:00Z"
      ),
      (
        key: "2024-03-10",
        zone: "America/Los_Angeles",
        expectedBoundary: "2024-03-11T07:00:00Z"
      ),
      (
        key: "2024-11-03",
        zone: "America/Los_Angeles",
        expectedBoundary: "2024-11-04T08:00:00Z"
      ),
      (
        key: "2024-07-04",
        zone: "UTC",
        expectedBoundary: "2024-07-05T00:00:00Z"
      ),
    ]

    for value in cases {
      let context = try makeContext()
      var saveCount = 0
      let operations = GoalCreationOperations(context: context) {
        saveCount += 1
        try context.save()
      }
      let deadline = try goalDate(value.key)
      let zone = try timeZone(value.zone)
      let boundary = try followingDayBoundary(after: deadline, in: zone)
      #expect(boundary == (try instant(value.expectedBoundary)))

      let goal = try operations.create(
        fields: GoalCreationFields(
          name: "Deadline in \(value.zone)",
          kind: .accumulate,
          target: 1,
          deadline: deadline
        ),
        at: boundary.addingTimeInterval(-1),
        timeZone: zone
      )
      #expect(goal.deadlineKey == deadline.rawValue)
      #expect(saveCount == 1)

      try expectCreationError(.deadlineExpired(deadline)) {
        _ = try operations.create(
          fields: GoalCreationFields(
            name: "Too late in \(value.zone)",
            kind: .accumulate,
            target: 1,
            deadline: deadline
          ),
          at: boundary,
          timeZone: zone
        )
      }
      #expect(saveCount == 1)
      #expect(try context.fetch(FetchDescriptor<Goal>()).count == 1)
      #expect(!context.hasChanges)
    }
  }

  @Test("unrepresentable following deadline day fails before insertion or save")
  func unrepresentableDeadlineBoundaryFailsBeforeInsertionOrSave() throws {
    let context = try makeContext()
    var saveCount = 0
    let operations = GoalCreationOperations(context: context) {
      saveCount += 1
      try context.save()
    }
    let maximumDate = try goalDate("9999-12-31")

    try expectCreationError(.invalidDeadlineBoundary(.unrepresentableDate)) {
      _ = try operations.create(
        fields: GoalCreationFields(
          name: "Beyond supported calendar",
          kind: .accumulate,
          target: 1,
          deadline: maximumDate
        ),
        at: instant("2024-01-01T00:00:00Z"),
        timeZone: timeZone("UTC")
      )
    }

    #expect(saveCount == 0)
    #expect(try context.fetch(FetchDescriptor<Goal>()).isEmpty)
    #expect(!context.hasChanges)
  }

  @Test("save failure detaches only the inserted goal and preserves unrelated pending habits")
  func saveFailureDetachesOnlyInsertedGoalAndPreservesUnrelatedChanges() throws {
    let context = try makeContext()
    let unrelatedHabit = Habit(
      name: "Pending habit",
      cadence: .daily,
      target: 1,
      createdAt: try instant("2024-01-01T00:00:00Z")
    )
    context.insert(unrelatedHabit)
    var insertedGoal: Goal?
    var saveCount = 0
    let operations = GoalCreationOperations(context: context) {
      saveCount += 1
      insertedGoal = try context.fetch(FetchDescriptor<Goal>()).first
      throw GoalCreationSaveFailure.expected
    }

    do {
      _ = try operations.create(
        fields: GoalCreationFields(name: "Failing goal", kind: .accumulate, target: 1),
        at: try instant("2024-01-01T12:00:00Z"),
        timeZone: timeZone("UTC")
      )
      Issue.record("Expected save failure")
    } catch let error as GoalCreationSaveFailure {
      #expect(error == .expected)
    }

    #expect(saveCount == 1)
    #expect(insertedGoal?.modelContext == nil)
    #expect(insertedGoal?.entries?.isEmpty == true)
    #expect(insertedGoal?.readings?.isEmpty == true)
    #expect(try context.fetch(FetchDescriptor<Goal>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<GoalEntry>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<GoalReading>()).isEmpty)
    #expect(context.hasChanges)
    #expect(try context.fetch(FetchDescriptor<Habit>()).map(\.id) == [unrelatedHabit.id])
    #expect(
      context.insertedModelsArray.map(\.persistentModelID) == [unrelatedHabit.persistentModelID])
    #expect(context.changedModelsArray.isEmpty)
    #expect(context.deletedModelsArray.isEmpty)

    try context.save()
    let verificationContext = ModelContext(context.container)
    #expect(try verificationContext.fetch(FetchDescriptor<Goal>()).isEmpty)
    #expect(
      try verificationContext.fetch(FetchDescriptor<Habit>()).map(\.id) == [unrelatedHabit.id])
  }

  @Test("created goals survive reopening a file-backed container")
  func createdGoalsSurviveReopeningFileBackedContainer() throws {
    let location = try makeTemporaryStoreLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let createdAt = try instant("2024-05-06T07:08:09Z")
    let goalID: UUID

    do {
      let container = try TendModelContainer.fileBacked(at: location.store)
      let goal = try GoalCreationOperations(context: container.mainContext).create(
        fields: GoalCreationFields(
          name: "Reopen me",
          kind: .measure,
          target: 75,
          unit: "kg",
          baseline: 90,
          deadline: goalDate("2024-05-06")
        ),
        at: createdAt,
        timeZone: timeZone("UTC")
      )
      goalID = goal.id
    }

    let reopened = try TendModelContainer.fileBacked(at: location.store)
    let fetched = try #require(
      ModelContext(reopened).fetch(FetchDescriptor<Goal>()).first { $0.id == goalID }
    )
    #expect(fetched.name == "Reopen me")
    #expect(fetched.kindRawValue == GoalKind.measure.rawValue)
    #expect(fetched.target == 75)
    #expect(fetched.unit == "kg")
    #expect(fetched.baseline == 90)
    #expect(fetched.deadlineKey == "2024-05-06")
    #expect(fetched.createdAt == createdAt)
    #expect(fetched.entries?.isEmpty == true)
    #expect(fetched.readings?.isEmpty == true)
  }

  private func expectCreationError(
    _ expected: GoalCreationOperationError,
    performing operation: () throws -> Void
  ) throws {
    do {
      try operation()
      Issue.record("Expected GoalCreationOperationError: \(expected)")
    } catch let error as GoalCreationOperationError {
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

  private func goalDate(_ value: String) throws -> LocalDate {
    try #require(LocalDate(rawValue: value))
  }

  private func followingDayBoundary(after date: LocalDate, in timeZone: TimeZone) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    let start = try #require(
      calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day))
    )
    return try #require(calendar.date(byAdding: .day, value: 1, to: start))
  }

  private func makeTemporaryStoreLocation() throws -> (directory: URL, store: URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("GoalCreationOperationsTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false
    )
    return (directory, directory.appendingPathComponent("Tend.store"))
  }
}

private enum GoalCreationSaveFailure: Error, Equatable {
  case expected
}
