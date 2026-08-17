import Foundation
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Goal form model")
struct GoalFormModelTests {
  @Test("New mode starts from the approved defaults")
  func newModeStartsFromApprovedDefaults() {
    let model = GoalFormModel(mode: .new)

    #expect(model.name.isEmpty)
    #expect(model.kind == .accumulate)
    #expect(model.targetText == "1")
    #expect(model.unit == "times")
    #expect(model.baselineText.isEmpty)
    #expect(model.deadline == nil)
    #expect(!model.isKindLocked)
    #expect(!model.isSaving)
    #expect(model.focusedField == nil)
    #expect(model.persistenceError == nil)
  }

  @Test("Accumulate Save trims its payload while preserving the raw drafts")
  func accumulateSaveTrimsPayloadWhilePreservingRawDrafts() throws {
    let instant = Date(timeIntervalSince1970: 1_725_214_400)
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let calendar = Calendar(identifier: .gregorian)
    let expectedGoal = Goal(name: "Walk", kind: .accumulate, target: 2, unit: "laps")
    let recorder = GoalFormPersistenceRecorder(createdGoal: expectedGoal)
    let model = GoalFormModel(mode: .new)
    model.name = "  Morning   walk  "
    model.targetText = "2"
    model.unit = "  laps per day  "

    #expect(recorder.createInvocations.isEmpty)
    #expect(recorder.updateInvocations.isEmpty)

    let savedGoal = model.save(
      using: recorder.persistence,
      at: instant,
      calendar: calendar,
      timeZone: timeZone
    )

    let invocation = try #require(recorder.createInvocations.only)
    #expect(savedGoal === expectedGoal)
    #expect(
      invocation.fields
        == GoalCreationFields(
          name: "Morning   walk",
          kind: .accumulate,
          target: 2,
          unit: "laps per day",
          baseline: nil,
          deadline: nil
        ))
    #expect(invocation.instant == instant)
    #expect(invocation.timeZone.identifier == timeZone.identifier)
    #expect(recorder.createInvocations.count == 1)
    #expect(recorder.updateInvocations.isEmpty)
    #expect(model.name == "  Morning   walk  ")
    #expect(model.targetText == "2")
    #expect(model.unit == "  laps per day  ")
    #expect(model.persistenceError == nil)
  }

  @Test("Measure Save sends the exact signed-baseline and deadline payload")
  func measureSaveSendsExactPayload() throws {
    let instant = Date(timeIntervalSince1970: 1_725_214_400)
    let timeZone = try #require(TimeZone(identifier: "UTC"))
    let deadline = try #require(GoalDate(year: 2026, month: 11, day: 1))
    let expectedGoal = Goal(
      name: "Fund",
      kind: .measure,
      target: 5_000,
      unit: "dollars",
      baseline: -250,
      deadline: deadline
    )
    let recorder = GoalFormPersistenceRecorder(createdGoal: expectedGoal)
    let model = GoalFormModel(mode: .new)
    model.name = "Fund"
    model.selectKind(.measure)
    model.targetText = "5000"
    model.unit = "dollars"
    model.baselineText = "-250"
    model.deadline = deadline

    let savedGoal = model.save(
      using: recorder.persistence,
      at: instant,
      calendar: Calendar(identifier: .gregorian),
      timeZone: timeZone
    )

    let invocation = try #require(recorder.createInvocations.only)
    #expect(savedGoal === expectedGoal)
    #expect(
      invocation.fields
        == GoalCreationFields(
          name: "Fund",
          kind: .measure,
          target: 5_000,
          unit: "dollars",
          baseline: -250,
          deadline: deadline
        ))
    #expect(recorder.createInvocations.count == 1)
    #expect(recorder.updateInvocations.isEmpty)
  }

  @Test(
    "target accepts only canonical unsigned positive integers",
    arguments: [
      "", "0", "-1", "+1", "1.5", "1,000", " 1 ", "goal",
      "999999999999999999999999999999999999",
    ]
  )
  func targetRejectsEveryInvalidShape(_ draft: String) throws {
    let recorder = GoalFormPersistenceRecorder()
    let model = validAccumulateModel()
    model.targetText = draft

    let savedGoal = model.save(
      using: recorder.persistence,
      at: Date(timeIntervalSince1970: 1_725_214_400),
      calendar: Calendar(identifier: .gregorian),
      timeZone: .gmt
    )

    #expect(savedGoal == nil)
    #expect(model.focusedField == .target)
    #expect(model.error(for: .target) == .invalidTarget)
    #expect(recorder.totalInvocationCount == 0)
  }

  @Test(
    "Measure baseline rejects non-integer and overflowing text",
    arguments: ["1.5", "--1", "+", "1,000", "baseline", "999999999999999999999999999999999999"]
  )
  func measureBaselineRejectsInvalidShapes(_ draft: String) {
    let recorder = GoalFormPersistenceRecorder()
    let model = validMeasureModel()
    model.baselineText = draft

    let savedGoal = model.save(
      using: recorder.persistence,
      at: Date(timeIntervalSince1970: 1_725_214_400),
      calendar: Calendar(identifier: .gregorian),
      timeZone: .gmt
    )

    #expect(savedGoal == nil)
    #expect(model.focusedField == .baseline)
    #expect(model.error(for: .baseline) == .invalidBaseline)
    #expect(recorder.totalInvocationCount == 0)
  }

  @Test("Measure baseline accepts negative, explicitly positive, and zero integers")
  func measureBaselineAcceptsSignedIntegers() throws {
    let examples: [(draft: String, expected: Int)] = [
      ("-12", -12),
      ("+12", 12),
      ("0", 0),
    ]

    for example in examples {
      let recorder = GoalFormPersistenceRecorder()
      let model = validMeasureModel()
      model.targetText = "20"
      model.baselineText = example.draft

      _ = model.save(
        using: recorder.persistence,
        at: Date(timeIntervalSince1970: 1_725_214_400),
        calendar: Calendar(identifier: .gregorian),
        timeZone: .gmt
      )

      let invocation = try #require(recorder.createInvocations.only)
      #expect(invocation.fields.baseline == example.expected)
    }
  }

  @Test("Measure direction and equality are left to the domain operation")
  func measureDirectionAndEqualityArePassedThrough() throws {
    let examples: [(target: Int, baseline: Int)] = [
      (5, 10),
      (10, 5),
      (10, 10),
    ]

    for example in examples {
      let recorder = GoalFormPersistenceRecorder()
      let model = validMeasureModel()
      model.targetText = String(example.target)
      model.baselineText = String(example.baseline)

      _ = model.save(
        using: recorder.persistence,
        at: Date(timeIntervalSince1970: 1_725_214_400),
        calendar: Calendar(identifier: .gregorian),
        timeZone: .gmt
      )

      let invocation = try #require(recorder.createInvocations.only)
      #expect(invocation.fields.target == example.target)
      #expect(invocation.fields.baseline == example.baseline)
    }
  }

  @Test("Measure to Accumulate clears baseline and never restores it")
  func switchingKindClearsBaselineWithoutRestoringIt() {
    let recorder = GoalFormPersistenceRecorder()
    let model = validMeasureModel()
    model.baselineText = "-40"

    model.selectKind(.accumulate)
    #expect(model.baselineText.isEmpty)
    #expect(model.error(for: .baseline) == nil)

    model.selectKind(.measure)

    #expect(model.baselineText.isEmpty)
    let savedGoal = model.save(
      using: recorder.persistence,
      at: Date(timeIntervalSince1970: 1_725_214_400),
      calendar: Calendar(identifier: .gregorian),
      timeZone: .gmt
    )
    #expect(savedGoal == nil)
    #expect(model.focusedField == .baseline)
    #expect(model.error(for: .baseline) == .missingBaseline)
    #expect(recorder.totalInvocationCount == 0)
  }

  @Test("Save focuses the first invalid field and exposes each local error in order")
  func saveFocusesFirstInvalidFieldInFieldOrder() {
    let recorder = GoalFormPersistenceRecorder()
    let model = GoalFormModel(mode: .new)
    model.selectKind(.measure)
    model.name = "  "
    model.targetText = "0"
    model.unit = "\n\t"
    model.baselineText = ""

    #expect(save(model, with: recorder) == nil)
    #expect(model.focusedField == .name)
    #expect(model.error(for: .name) == .emptyName)
    #expect(model.error(for: .target) == .invalidTarget)
    #expect(model.error(for: .unit) == .emptyUnit)
    #expect(model.error(for: .baseline) == .missingBaseline)

    model.name = "Read"
    #expect(save(model, with: recorder) == nil)
    #expect(model.focusedField == .target)

    model.targetText = "4"
    #expect(save(model, with: recorder) == nil)
    #expect(model.focusedField == .unit)

    model.unit = "books"
    #expect(save(model, with: recorder) == nil)
    #expect(model.focusedField == .baseline)

    #expect(recorder.totalInvocationCount == 0)
  }

  @Test("A deadline can be added to New and removed from Edit")
  func deadlineCanBeAddedAndRemoved() throws {
    let deadline = try #require(GoalDate(year: 2027, month: 3, day: 14))
    let newRecorder = GoalFormPersistenceRecorder()
    let newModel = validAccumulateModel()
    newModel.deadline = deadline

    _ = save(newModel, with: newRecorder)

    #expect(try #require(newRecorder.createInvocations.only).fields.deadline == deadline)

    let goal = Goal(
      name: "Walk",
      kind: .accumulate,
      target: 1,
      deadline: deadline
    )
    let editRecorder = GoalFormPersistenceRecorder(createdGoal: goal)
    let editModel = GoalFormModel(mode: .edit(goal))
    editModel.deadline = nil

    _ = save(editModel, with: editRecorder)

    #expect(try #require(editRecorder.updateInvocations.only).fields.deadline == nil)
  }

  @Test("deadline adapter preserves local dates near midnight and both DST transitions")
  func deadlineAdapterPreservesCivilDateNearMidnightAndDST() throws {
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let calendar = Calendar(identifier: .gregorian)
    let examples: [(date: Date, expected: GoalDate)] = [
      (
        try utcDate(year: 2024, month: 3, day: 10, hour: 7, minute: 59),
        try #require(GoalDate(year: 2024, month: 3, day: 9))
      ),
      (
        try utcDate(year: 2024, month: 3, day: 10, hour: 10, minute: 1),
        try #require(GoalDate(year: 2024, month: 3, day: 10))
      ),
      (
        try utcDate(year: 2024, month: 11, day: 3, hour: 8, minute: 30),
        try #require(GoalDate(year: 2024, month: 11, day: 3))
      ),
      (
        try utcDate(year: 2024, month: 11, day: 3, hour: 9, minute: 30),
        try #require(GoalDate(year: 2024, month: 11, day: 3))
      ),
    ]

    for example in examples {
      #expect(
        GoalFormDeadlineAdapter.goalDate(
          from: example.date,
          calendar: calendar,
          timeZone: timeZone
        ) == example.expected)

      let pickerDate = GoalFormDeadlineAdapter.date(
        for: example.expected,
        calendar: calendar,
        timeZone: timeZone
      )
      #expect(
        GoalFormDeadlineAdapter.goalDate(
          from: pickerDate,
          calendar: calendar,
          timeZone: timeZone
        ) == example.expected)
    }
  }

  @Test("deadline adapter reads Gregorian civil dates with a non-Gregorian calendar")
  func deadlineAdapterReadsGregorianDateWithNonGregorianCalendar() throws {
    let timeZone = try #require(TimeZone(identifier: "Asia/Riyadh"))
    let callerCalendar = Calendar(identifier: .islamicUmmAlQura)
    let instant = try utcDate(year: 2024, month: 3, day: 10, hour: 21, minute: 30)
    let expected = try #require(GoalDate(year: 2024, month: 3, day: 11))

    #expect(
      GoalFormDeadlineAdapter.goalDate(
        from: instant,
        calendar: callerCalendar,
        timeZone: timeZone
      ) == expected)
  }

  @Test("deadline adapter writes Gregorian civil dates with a non-Gregorian calendar")
  func deadlineAdapterWritesGregorianDateWithNonGregorianCalendar() throws {
    let timeZone = try #require(TimeZone(identifier: "Asia/Riyadh"))
    let callerCalendar = Calendar(identifier: .islamicUmmAlQura)
    let expected = try #require(GoalDate(year: 2024, month: 3, day: 11))

    let pickerDate = GoalFormDeadlineAdapter.date(
      for: expected,
      calendar: callerCalendar,
      timeZone: timeZone
    )
    var gregorianCalendar = Calendar(identifier: .gregorian)
    gregorianCalendar.timeZone = timeZone
    let components = gregorianCalendar.dateComponents(
      [.year, .month, .day],
      from: pickerDate
    )

    #expect(components.year == 2024)
    #expect(components.month == 3)
    #expect(components.day == 11)
  }

  @Test("Edit snapshots persisted values once and never permits a kind change")
  func editSnapshotsValuesAndLocksKind() throws {
    let deadline = try #require(GoalDate(year: 2026, month: 8, day: 31))
    let goal = Goal(
      name: "Run",
      kind: .measure,
      target: 10,
      unit: "kilometers",
      baseline: 2,
      deadline: deadline
    )
    let model = GoalFormModel(mode: .edit(goal))

    #expect(model.name == "Run")
    #expect(model.kind == .measure)
    #expect(model.targetText == "10")
    #expect(model.unit == "kilometers")
    #expect(model.baselineText == "2")
    #expect(model.deadline == deadline)
    #expect(model.isKindLocked)

    goal.name = "Externally changed"
    goal.target = 99
    goal.unit = "miles"
    goal.baseline = 50
    goal.deadlineKey = nil
    model.selectKind(.accumulate)

    #expect(model.name == "Run")
    #expect(model.kind == .measure)
    #expect(model.targetText == "10")
    #expect(model.unit == "kilometers")
    #expect(model.baselineText == "2")
    #expect(model.deadline == deadline)
  }

  @Test("Edit rejects an unsupported stored kind without coercing or writing")
  func editRejectsUnsupportedStoredKind() {
    let goal = Goal(
      name: "Walk",
      kind: .accumulate,
      target: 4,
      unit: "laps",
      baseline: nil
    )
    goal.kindRawValue = "future-kind"
    let recorder = GoalFormPersistenceRecorder(createdGoal: goal)
    let model = GoalFormModel(mode: .edit(goal))

    #expect(
      model.configurationErrorMessage
        == "This goal has an unsupported stored kind and can’t be edited.")
    #expect(!model.canSave)

    let savedGoal = save(model, with: recorder)

    #expect(savedGoal == nil)
    #expect(recorder.totalInvocationCount == 0)
    #expect(goal.name == "Walk")
    #expect(goal.kindRawValue == "future-kind")
    #expect(goal.target == 4)
    #expect(goal.unit == "laps")
    #expect(goal.baseline == nil)
    #expect(goal.deadlineKey == nil)
  }

  @Test("Edit rejects a malformed stored deadline without dropping or writing it")
  func editRejectsMalformedStoredDeadline() {
    let goal = Goal(
      name: "Read",
      kind: .accumulate,
      target: 3,
      unit: "books",
      baseline: nil
    )
    goal.deadlineKey = "2026-02-30"
    let recorder = GoalFormPersistenceRecorder(createdGoal: goal)
    let model = GoalFormModel(mode: .edit(goal))

    #expect(
      model.configurationErrorMessage
        == "This goal has an invalid stored deadline and can’t be edited.")
    #expect(!model.canSave)

    let savedGoal = save(model, with: recorder)

    #expect(savedGoal == nil)
    #expect(recorder.totalInvocationCount == 0)
    #expect(goal.name == "Read")
    #expect(goal.kindRawValue == GoalKind.accumulate.rawValue)
    #expect(goal.target == 3)
    #expect(goal.unit == "books")
    #expect(goal.baseline == nil)
    #expect(goal.deadlineKey == "2026-02-30")
  }

  @Test("Edit Save updates the original closed goal exactly once without changing kind")
  func editSaveUpdatesOriginalClosedGoalExactlyOnce() throws {
    let originalDeadline = try #require(GoalDate(year: 2026, month: 8, day: 31))
    let replacementDeadline = try #require(GoalDate(year: 2027, month: 1, day: 2))
    let timeZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    let goal = Goal(
      name: "Net worth",
      kind: .measure,
      target: 100,
      unit: "dollars",
      baseline: 10,
      deadline: originalDeadline
    )
    goal.closureRawValue = GoalClosure.harvested.rawValue
    let recorder = GoalFormPersistenceRecorder(createdGoal: goal)
    let model = GoalFormModel(mode: .edit(goal))
    model.name = "  Retirement fund  "
    model.targetText = "500"
    model.unit = "  thousands of dollars  "
    model.baselineText = "-20"
    model.deadline = replacementDeadline
    model.selectKind(.accumulate)

    #expect(goal.name == "Net worth")
    #expect(goal.kindRawValue == GoalKind.measure.rawValue)
    #expect(goal.target == 100)
    #expect(goal.unit == "dollars")
    #expect(goal.baseline == 10)
    #expect(goal.deadlineKey == originalDeadline.rawValue)
    #expect(goal.closureRawValue == GoalClosure.harvested.rawValue)
    #expect(recorder.totalInvocationCount == 0)

    let savedGoal = model.save(
      using: recorder.persistence,
      at: Date(timeIntervalSince1970: 1_800_000_000),
      calendar: calendar,
      timeZone: timeZone
    )

    let invocation = try #require(recorder.updateInvocations.only)
    #expect(savedGoal === goal)
    #expect(invocation.goal === goal)
    #expect(
      invocation.fields
        == GoalEditableFields(
          name: "Retirement fund",
          target: 500,
          unit: "thousands of dollars",
          baseline: -20,
          deadline: replacementDeadline
        ))
    #expect(invocation.calendar.identifier == calendar.identifier)
    #expect(invocation.calendar.firstWeekday == calendar.firstWeekday)
    #expect(invocation.timeZone.identifier == timeZone.identifier)
    #expect(recorder.createInvocations.isEmpty)
    #expect(recorder.updateInvocations.count == 1)
    #expect(goal.kindRawValue == GoalKind.measure.rawValue)
  }

  @Test("Editing or discarding a draft performs no persistence or optimistic mutation")
  func unsavedAndCancelledDraftsPerformNoWrites() throws {
    let deadline = try #require(GoalDate(year: 2026, month: 12, day: 20))
    let goal = Goal(
      name: "Read",
      kind: .accumulate,
      target: 3,
      unit: "books",
      deadline: deadline
    )
    let recorder = GoalFormPersistenceRecorder(createdGoal: goal)

    do {
      let model = GoalFormModel(mode: .edit(goal))
      model.name = "Discarded edit"
      model.targetText = "9"
      model.unit = "chapters"
      model.deadline = nil
      _ = recorder.persistence
    }

    #expect(recorder.totalInvocationCount == 0)
    #expect(goal.name == "Read")
    #expect(goal.target == 3)
    #expect(goal.unit == "books")
    #expect(goal.deadlineKey == deadline.rawValue)
  }

  @Test("A localized save failure retains every draft and exposes its diagnostic")
  func localizedSaveFailureRetainsDraftAndDiagnostic() throws {
    let deadline = try #require(GoalDate(year: 2026, month: 10, day: 15))
    let recorder = GoalFormPersistenceRecorder()
    recorder.createError = TestGoalSaveFailure.expected
    let model = validMeasureModel()
    model.name = "  Savings  "
    model.targetText = "100"
    model.unit = "  dollars  "
    model.baselineText = "-8"
    model.deadline = deadline

    let savedGoal = save(model, with: recorder)

    #expect(savedGoal == nil)
    #expect(recorder.createInvocations.count == 1)
    #expect(model.name == "  Savings  ")
    #expect(model.targetText == "100")
    #expect(model.unit == "  dollars  ")
    #expect(model.baselineText == "-8")
    #expect(model.deadline == deadline)
    #expect(model.kind == .measure)
    #expect(model.persistenceError == "Unable to save this goal right now.")
    #expect(!model.isSaving)
  }

  @Test("A domain rejection reaches persistence and retains the draft with a fallback diagnostic")
  func domainFailureRetainsDraftAndFallbackDiagnostic() {
    let recorder = GoalFormPersistenceRecorder()
    recorder.createError = GoalCreationOperationError.measureBaselineEqualsTarget(10)
    let model = validMeasureModel()
    model.targetText = "10"
    model.baselineText = "10"

    let savedGoal = save(model, with: recorder)

    #expect(savedGoal == nil)
    #expect(recorder.createInvocations.count == 1)
    #expect(recorder.createInvocations.first?.fields.target == 10)
    #expect(recorder.createInvocations.first?.fields.baseline == 10)
    #expect(model.targetText == "10")
    #expect(model.baselineText == "10")
    #expect(model.persistenceError == "We couldn’t save this goal. Your changes are still here.")
    #expect(!model.isSaving)
  }

  @Test("Edit failure leaves the persisted goal untouched and retains the full draft")
  func editFailureLeavesGoalUntouchedAndRetainsDraft() throws {
    let oldDeadline = try #require(GoalDate(year: 2026, month: 9, day: 1))
    let newDeadline = try #require(GoalDate(year: 2026, month: 10, day: 1))
    let goal = Goal(
      name: "Weight",
      kind: .measure,
      target: 70,
      unit: "kg",
      baseline: 80,
      deadline: oldDeadline
    )
    let recorder = GoalFormPersistenceRecorder(createdGoal: goal)
    recorder.updateError = TestGoalSaveFailure.expected
    let model = GoalFormModel(mode: .edit(goal))
    model.name = "  Body weight  "
    model.targetText = "68"
    model.unit = " kilograms "
    model.baselineText = "+81"
    model.deadline = newDeadline

    let savedGoal = save(model, with: recorder)

    #expect(savedGoal == nil)
    #expect(recorder.updateInvocations.count == 1)
    #expect(goal.name == "Weight")
    #expect(goal.target == 70)
    #expect(goal.unit == "kg")
    #expect(goal.baseline == 80)
    #expect(goal.deadlineKey == oldDeadline.rawValue)
    #expect(model.name == "  Body weight  ")
    #expect(model.targetText == "68")
    #expect(model.unit == " kilograms ")
    #expect(model.baselineText == "+81")
    #expect(model.deadline == newDeadline)
    #expect(model.persistenceError == "Unable to save this goal right now.")
  }

  @Test("Save rejects a reentrant submission while the operation is in flight")
  func saveRejectsReentrantSubmission() throws {
    let expectedGoal = Goal(name: "Walk", kind: .accumulate, target: 1)
    var model: GoalFormModel!
    var persistence: GoalFormPersistence!
    var createCallCount = 0
    var reentrantResult: Goal?
    var observedSavingState = false

    persistence = GoalFormPersistence(
      create: { _, _, _ in
        createCallCount += 1
        observedSavingState = model.isSaving
        reentrantResult = model.save(
          using: persistence,
          at: Date(timeIntervalSince1970: 1_725_214_400),
          calendar: Calendar(identifier: .gregorian),
          timeZone: .gmt
        )
        return expectedGoal
      },
      update: { _, _, _, _ in
        Issue.record("New Save must not dispatch update")
      }
    )
    model = validAccumulateModel()

    let savedGoal = save(model, with: persistence)

    #expect(savedGoal === expectedGoal)
    #expect(observedSavingState)
    #expect(reentrantResult == nil)
    #expect(createCallCount == 1)
    #expect(!model.isSaving)
  }
}

@MainActor
private final class GoalFormPersistenceRecorder {
  struct CreateInvocation {
    let fields: GoalCreationFields
    let instant: Date
    let timeZone: TimeZone
  }

  struct UpdateInvocation {
    let goal: Goal
    let fields: GoalEditableFields
    let calendar: Calendar
    let timeZone: TimeZone
  }

  var createError: Error?
  var updateError: Error?
  private(set) var createInvocations: [CreateInvocation] = []
  private(set) var updateInvocations: [UpdateInvocation] = []

  private let createdGoal: Goal

  init(
    createdGoal: Goal = Goal(name: "Created", kind: .accumulate, target: 1)
  ) {
    self.createdGoal = createdGoal
  }

  var totalInvocationCount: Int {
    createInvocations.count + updateInvocations.count
  }

  var persistence: GoalFormPersistence {
    GoalFormPersistence(
      create: { fields, instant, timeZone in
        self.createInvocations.append(
          CreateInvocation(fields: fields, instant: instant, timeZone: timeZone)
        )
        if let createError = self.createError {
          throw createError
        }
        return self.createdGoal
      },
      update: { goal, fields, calendar, timeZone in
        self.updateInvocations.append(
          UpdateInvocation(
            goal: goal,
            fields: fields,
            calendar: calendar,
            timeZone: timeZone
          ))
        if let updateError = self.updateError {
          throw updateError
        }
      }
    )
  }
}

@MainActor
private func validAccumulateModel() -> GoalFormModel {
  let model = GoalFormModel(mode: .new)
  model.name = "Walk"
  model.targetText = "1"
  model.unit = "times"
  return model
}

@MainActor
private func validMeasureModel() -> GoalFormModel {
  let model = GoalFormModel(mode: .new)
  model.name = "Measure"
  model.selectKind(.measure)
  model.targetText = "10"
  model.unit = "units"
  model.baselineText = "0"
  return model
}

@MainActor
private func save(
  _ model: GoalFormModel,
  with recorder: GoalFormPersistenceRecorder
) -> Goal? {
  save(model, with: recorder.persistence)
}

@MainActor
private func save(
  _ model: GoalFormModel,
  with persistence: GoalFormPersistence
) -> Goal? {
  model.save(
    using: persistence,
    at: Date(timeIntervalSince1970: 1_725_214_400),
    calendar: Calendar(identifier: .gregorian),
    timeZone: .gmt
  )
}

private func utcDate(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
  minute: Int
) throws -> Date {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .gmt
  return try #require(
    calendar.date(
      from: DateComponents(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
      )))
}

private enum TestGoalSaveFailure: LocalizedError {
  case expected

  var errorDescription: String? {
    "Unable to save this goal right now."
  }
}

private extension Collection {
  var only: Element? {
    count == 1 ? first : nil
  }
}
