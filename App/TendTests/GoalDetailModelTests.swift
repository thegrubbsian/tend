import Foundation
import SwiftData
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Goal detail model")
struct GoalDetailModelTests {
  @Test("initial load failure is retryable and a later refresh keeps the last good presentation")
  func retriesLoadsWithoutDiscardingGoodFacts() throws {
    let fixture = try GoalDetailFixture()
    let good = fixture.accumulateSnapshot(name: "Walk", total: 14, target: 10)
    let recorder = GoalDetailOperationsRecorder(
      snapshots: [.failure(TestGoalDetailFailure.load), .success(good), .failure(TestGoalDetailFailure.load)]
    )
    let model = fixture.model(operations: recorder.operations)

    model.start()

    #expect(model.goalID == fixture.goal.id)
    #expect(model.presentation == nil)
    #expect(model.loadFailure?.retryTitle == "Try again")
    #expect(recorder.snapshotInvocations.count == 1)

    model.retryLoad()
    let presentation = try #require(model.presentation)
    #expect(presentation.goalID == fixture.goal.id)
    #expect(presentation.name == "Walk")
    #expect(model.loadFailure == nil)

    model.refresh()

    #expect(model.presentation == presentation)
    #expect(model.loadFailure != nil)
    #expect(!model.canMutate)
  }

  @Test("over-achieved accumulation presents query progress without clamping and exposes open actions")
  func presentsOverAchievedAccumulateGoal() throws {
    let fixture = try GoalDetailFixture()
    let snapshot = fixture.accumulateSnapshot(
      name: "Walk",
      total: 14,
      target: 10,
      unit: "miles",
      destinations: [.today, .yesterday]
    )
    let model = fixture.loadedModel(snapshot: snapshot)
    let presentation = try #require(model.presentation)

    #expect(
      presentation.progress
        == .accumulate(total: 14, target: 10, unit: "miles", normalizedProgress: 1.4)
    )
    #expect(presentation.progressText == "14 of 10 miles")
    #expect(presentation.deadlineText == "No deadline")
    #expect(presentation.standing == .onPace)
    #expect(presentation.expectedNormalizedProgress == nil)
    #expect(presentation.standingText == "On pace")
    #expect(presentation.closure == nil)
    #expect(presentation.closureText == nil)
    #expect(
      presentation.actions == [.edit, .addProgress, .harvest, .letGo, .deleteGoal]
    )
    #expect(
      presentation.appendDestinations
        == [
          GoalDetailAppendDestination(destination: .today, title: "Today"),
          GoalDetailAppendDestination(destination: .yesterday, title: "Yesterday"),
        ]
    )
  }

  @Test("measure presentation preserves increasing and decreasing domain facts")
  func presentsBothMeasureDirections() throws {
    let fixture = try GoalDetailFixture()
    let increasing = fixture.measureSnapshot(baseline: 10, target: 20, current: 15)
    let decreasing = fixture.measureSnapshot(baseline: 20, target: 10, current: 14)

    let increasingModel = fixture.loadedModel(snapshot: increasing)
    let decreasingModel = fixture.loadedModel(snapshot: decreasing)

    #expect(
      increasingModel.presentation?.progress
        == .measure(
          baseline: 10,
          target: 20,
          current: 15,
          completedDistance: 5,
          totalDistance: 10,
          direction: .increasing,
          unit: "kg",
          normalizedProgress: 0.5
        )
    )
    #expect(increasingModel.presentation?.progressText == "15 kg now · 5 of 10 kg")
    #expect(
      decreasingModel.presentation?.progress
        == .measure(
          baseline: 20,
          target: 10,
          current: 14,
          completedDistance: 6,
          totalDistance: 10,
          direction: .decreasing,
          unit: "kg",
          normalizedProgress: 0.6
        )
    )
    #expect(decreasingModel.presentation?.progressText == "14 kg now · 6 of 10 kg")
  }

  @Test("deadline, standing, and closure wording map only query facts to valid actions")
  func presentsStandingAndClosureStates() throws {
    let fixture = try GoalDetailFixture()
    let deadline = try #require(GoalDate(year: 2026, month: 1, day: 20))
    let cases: [(GoalStanding, String)] = [
      (.onPace, "On pace"),
      (.behind, "Behind"),
      (.pastDue, "Past due"),
    ]

    for (standing, expectedText) in cases {
      let snapshot = fixture.accumulateSnapshot(
        deadline: deadline,
        standing: GoalStandingSnapshot(
          standing: standing,
          actualNormalizedProgress: 0.4,
          expectedNormalizedProgress: standing == .pastDue ? 1 : 0.5,
          deadlineBoundary: fixture.instant,
          nextTimeRefresh: nil
        )
      )
      let model = fixture.loadedModel(snapshot: snapshot)
      #expect(model.presentation?.deadlineText == "5 days remaining · Due Jan 20, 2026")
      #expect(model.presentation?.standing == standing)
      #expect(
        model.presentation?.expectedNormalizedProgress
          == (standing == .pastDue ? 1 : 0.5)
      )
      #expect(model.presentation?.standingText == expectedText)
    }

    let harvested = fixture.loadedModel(
      snapshot: fixture.accumulateSnapshot(closure: .harvested, destinations: [])
    )
    #expect(harvested.presentation?.closure == .harvested)
    #expect(harvested.presentation?.standing == nil)
    #expect(harvested.presentation?.expectedNormalizedProgress == nil)
    #expect(harvested.presentation?.closureText == "Harvested")
    #expect(harvested.presentation?.actions == [.edit, .reopen, .deleteGoal])

    let letGo = fixture.loadedModel(
      snapshot: fixture.accumulateSnapshot(closure: .letGo, destinations: [])
    )
    #expect(letGo.presentation?.closure == .letGo)
    #expect(letGo.presentation?.standing == nil)
    #expect(letGo.presentation?.expectedNormalizedProgress == nil)
    #expect(letGo.presentation?.closureText == "Let go")
    #expect(letGo.presentation?.actions == [.edit, .reopen, .deleteGoal])
  }

  @Test("deadline wording includes localized civil-day distance and formatted due date")
  func presentsDeadlineCivilDayContext() throws {
    let fixture = try GoalDetailFixture()
    let cases: [(GoalDate, String)] = [
      (try #require(GoalDate(year: 2026, month: 1, day: 15)), "Due today · Jan 15, 2026"),
      (try #require(GoalDate(year: 2026, month: 1, day: 16)), "1 day remaining · Due Jan 16, 2026"),
      (try #require(GoalDate(year: 2026, month: 1, day: 17)), "2 days remaining · Due Jan 17, 2026"),
      (try #require(GoalDate(year: 2026, month: 1, day: 14)), "1 day past due · Due Jan 14, 2026"),
      (try #require(GoalDate(year: 2026, month: 1, day: 13)), "2 days past due · Due Jan 13, 2026"),
    ]

    for (deadline, expected) in cases {
      let standing: GoalStanding = deadline < cases[0].0 ? .pastDue : .onPace
      let model = fixture.loadedModel(
        snapshot: fixture.accumulateSnapshot(
          deadline: deadline,
          standing: .init(
            standing: standing,
            actualNormalizedProgress: 0,
            expectedNormalizedProgress: standing == .pastDue ? 1 : 0.5,
            deadlineBoundary: fixture.instant,
            nextTimeRefresh: nil
          )
        )
      )
      #expect(model.presentation?.deadlineText == expected)
    }
  }

  @Test("history preserves query order, local day wording, and same-day effective reading")
  func presentsHistoryInAuthoritativeOrder() throws {
    let fixture = try GoalDetailFixture()
    let today = try #require(GoalDate(year: 2026, month: 1, day: 15))
    let yesterday = try #require(GoalDate(year: 2026, month: 1, day: 14))
    let effectiveID = GoalReadingIdentity(rawValue: UUID())
    let supersededID = GoalReadingIdentity(rawValue: UUID())
    let oldID = GoalReadingIdentity(rawValue: UUID())
    let history: [GoalDetailHistoryItem] = [
      .reading(
        GoalDetailReading(
          id: effectiveID,
          assignedDate: today,
          value: 14,
          appendedAt: fixture.instant,
          appendSequence: 3,
          isDeleteEligible: true,
          isEffective: true
        )),
      .reading(
        GoalDetailReading(
          id: supersededID,
          assignedDate: today,
          value: 12,
          appendedAt: fixture.instant.addingTimeInterval(-60),
          appendSequence: 2,
          isDeleteEligible: true,
          isEffective: false
        )),
      .reading(
        GoalDetailReading(
          id: oldID,
          assignedDate: yesterday,
          value: 11,
          appendedAt: fixture.instant.addingTimeInterval(-86_400),
          appendSequence: 1,
          isDeleteEligible: true,
          isEffective: false
        )),
    ]
    let model = fixture.loadedModel(snapshot: fixture.measureSnapshot(history: history))
    let facts = try #require(model.presentation?.history)

    #expect(facts.map(\.id) == [.reading(effectiveID), .reading(supersededID), .reading(oldID)])
    #expect(facts.map(\.dateText) == ["Today", "Today", "Yesterday"])
    #expect(facts.map(\.isEffective) == [true, false, false])
    #expect(facts.map(\.valueText) == ["14 kg", "12 kg", "11 kg"])
  }

  @Test("append sends exact captured Today and Yesterday payloads")
  func appendsExactPayloads() throws {
    let fixture = try GoalDetailFixture()
    let initial = fixture.accumulateSnapshot(destinations: [.today, .yesterday])
    let afterToday = fixture.accumulateSnapshot(total: 3, destinations: [.today, .yesterday])
    let afterYesterday = fixture.accumulateSnapshot(total: 7, destinations: [.today, .yesterday])
    let recorder = GoalDetailOperationsRecorder(
      snapshots: [.success(initial), .success(afterToday), .success(afterYesterday)]
    )
    let model = fixture.model(operations: recorder.operations)
    model.start()

    model.presentEntrySheet()
    model.entryText = "3"
    model.selectAppendDestination(.today)
    model.saveEntry()

    #expect(
      recorder.appendInvocations.first
        == .init(
          kind: .accumulate,
          value: 3,
          destination: .today,
          instant: fixture.instant,
          timeZone: fixture.timeZone
        )
    )
    #expect(!model.isPresentingEntrySheet)
    #expect(model.presentation?.progressText == "3 of 10 times")

    model.presentEntrySheet()
    model.entryText = "4"
    model.selectAppendDestination(.yesterday)
    model.saveEntry()

    #expect(
      recorder.appendInvocations.last
        == .init(
          kind: .accumulate,
          value: 4,
          destination: .yesterday,
          instant: fixture.instant,
          timeZone: fixture.timeZone
        )
    )
    #expect(model.presentation?.progressText == "7 of 10 times")
  }

  @Test("append choices never invent unavailable destinations")
  func refusesUnavailableDestinations() throws {
    let fixture = try GoalDetailFixture()
    let recorder = GoalDetailOperationsRecorder(
      snapshots: [.success(fixture.accumulateSnapshot(destinations: [.yesterday]))]
    )
    let model = fixture.model(operations: recorder.operations)
    model.start()

    model.presentEntrySheet()
    #expect(model.selectedAppendDestination == .yesterday)
    model.selectAppendDestination(.today)
    #expect(model.selectedAppendDestination == .yesterday)
    model.entryText = "2"
    model.saveEntry()
    #expect(recorder.appendInvocations.only?.destination == .yesterday)

    let unavailable = fixture.loadedModel(
      snapshot: fixture.accumulateSnapshot(destinations: [])
    )
    unavailable.presentEntrySheet()
    #expect(!unavailable.isPresentingEntrySheet)
  }

  @Test("accumulate validation accepts only canonical positive decimal Int values")
  func validatesAccumulateDrafts() throws {
    let fixture = try GoalDetailFixture()
    let model = fixture.loadedModel(snapshot: fixture.accumulateSnapshot(destinations: [.today]))
    model.presentEntrySheet()

    for invalid in ["", "0", "-1", "+1", "01", " 1", "1 ", "1.0", "١"] {
      model.entryText = invalid
      #expect(!model.canSaveEntry, "Unexpectedly accepted \(invalid)")
    }
    for valid in ["1", "42", String(Int.max)] {
      model.entryText = valid
      #expect(model.canSaveEntry, "Unexpectedly rejected \(valid)")
    }
  }

  @Test("measure validation accepts every canonical signed Int and rejects alternate spellings")
  func validatesMeasureDrafts() throws {
    let fixture = try GoalDetailFixture()
    let model = fixture.loadedModel(snapshot: fixture.measureSnapshot(destinations: [.today]))
    model.presentEntrySheet()

    for valid in [String(Int.min), "-1", "0", "1", String(Int.max)] {
      model.entryText = valid
      #expect(model.canSaveEntry, "Unexpectedly rejected \(valid)")
    }
    for invalid in ["", "+1", "-0", "00", "01", "-01", " 0", "0 ", "1.0", "١"] {
      model.entryText = invalid
      #expect(!model.canSaveEntry, "Unexpectedly accepted \(invalid)")
    }
  }

  @Test("nonempty invalid entry drafts expose kind-specific inline validation")
  func presentsEntryValidationMessages() throws {
    let fixture = try GoalDetailFixture()
    let accumulate = fixture.loadedModel(
      snapshot: fixture.accumulateSnapshot(destinations: [.today])
    )
    accumulate.presentEntrySheet()
    #expect(accumulate.entryValidationMessage == nil)
    accumulate.entryText = "0"
    #expect(accumulate.entryValidationMessage == "Enter a positive whole number.")
    accumulate.entryText = "01"
    #expect(accumulate.entryValidationMessage == "Enter a positive whole number.")
    accumulate.entryText = "2"
    #expect(accumulate.entryValidationMessage == nil)

    let measure = fixture.loadedModel(
      snapshot: fixture.measureSnapshot(destinations: [.today])
    )
    measure.presentEntrySheet()
    #expect(measure.entryValidationMessage == nil)
    measure.entryText = "+1"
    #expect(measure.entryValidationMessage == "Enter a whole number.")
    measure.entryText = "-0"
    #expect(measure.entryValidationMessage == "Enter a whole number.")
    measure.entryText = "-1"
    #expect(measure.entryValidationMessage == nil)
  }

  @Test("history deletion requires query eligibility and dispatches the exact typed identity")
  func authorizesHistoryDeletion() throws {
    let fixture = try GoalDetailFixture()
    let eligibleID = GoalEntryIdentity(rawValue: UUID())
    let ineligibleID = GoalEntryIdentity(rawValue: UUID())
    let today = try #require(GoalDate(year: 2026, month: 1, day: 15))
    let history: [GoalDetailHistoryItem] = [
      .entry(.init(id: eligibleID, assignedDate: today, amount: 2, appendedAt: fixture.instant, appendSequence: 2, isDeleteEligible: true)),
      .entry(.init(id: ineligibleID, assignedDate: today, amount: 1, appendedAt: fixture.instant, appendSequence: 1, isDeleteEligible: false)),
    ]
    let initial = fixture.accumulateSnapshot(total: 3, history: history)
    let refreshed = fixture.accumulateSnapshot(total: 1, history: Array(history.dropFirst()))
    let recorder = GoalDetailOperationsRecorder(snapshots: [.success(initial), .success(refreshed)])
    let model = fixture.model(operations: recorder.operations)
    model.start()

    model.requestHistoryDeletion(.entry(ineligibleID))
    #expect(model.confirmation == nil)
    model.requestHistoryDeletion(.entry(eligibleID))
    #expect(model.confirmation == .deleteHistory(.entry(eligibleID)))
    model.confirmPendingAction()

    #expect(recorder.deleteInvocations == [.entry(eligibleID)])
    #expect(model.presentation?.history.map(\.id) == [.entry(ineligibleID)])
  }

  @Test("rejected history deletion is a retryable mutation failure, not a silent reload")
  func rejectsUnresolvedHistoryDeletion() throws {
    let fixture = try GoalDetailFixture()
    let entryID = GoalEntryIdentity(rawValue: UUID())
    let today = try #require(GoalDate(year: 2026, month: 1, day: 15))
    let history: [GoalDetailHistoryItem] = [
      .entry(
        .init(
          id: entryID,
          assignedDate: today,
          amount: 2,
          appendedAt: fixture.instant,
          appendSequence: 1,
          isDeleteEligible: true
        ))
    ]
    let initial = fixture.accumulateSnapshot(total: 2, history: history)
    let recorder = GoalDetailOperationsRecorder(
      snapshots: [.success(initial)],
      deleteResults: [.success(.rejected), .success(.rejected)]
    )
    let model = fixture.model(operations: recorder.operations)
    model.start()
    let lastGood = model.presentation
    model.requestHistoryDeletion(.entry(entryID))

    model.confirmPendingAction()

    #expect(model.presentation == lastGood)
    #expect(model.confirmation == .deleteHistory(.entry(entryID)))
    #expect(model.operationFailure?.placement == .history)
    #expect(model.operationFailure?.canCancel == true)
    #expect(model.loadFailure == nil)
    #expect(recorder.snapshotInvocations.count == 1)

    model.retryOperation()
    #expect(recorder.deleteInvocations == [.entry(entryID), .entry(entryID)])
    #expect(recorder.snapshotInvocations.count == 1)
    #expect(model.operationFailure?.placement == .history)
    #expect(model.confirmation == .deleteHistory(.entry(entryID)))

    model.cancelOperationFailure()
    #expect(model.operationFailure == nil)
    #expect(model.confirmation == nil)
    #expect(model.presentation == lastGood)
  }

  @Test("Edit cancel preserves facts and Edit save refreshes from the query")
  func refreshesAfterEditSave() throws {
    let fixture = try GoalDetailFixture()
    let initial = fixture.accumulateSnapshot(name: "Walk")
    let edited = fixture.accumulateSnapshot(name: "Walk farther")
    let recorder = GoalDetailOperationsRecorder(snapshots: [.success(initial), .success(edited)])
    let model = fixture.model(operations: recorder.operations)
    model.start()

    model.presentEdit()
    #expect(model.goalForEditing === fixture.goal)
    model.editCancelled()
    #expect(!model.isPresentingEdit)
    #expect(recorder.snapshotInvocations.count == 1)

    model.presentEdit()
    model.editSaved()
    #expect(!model.isPresentingEdit)
    #expect(model.presentation?.name == "Walk farther")
    #expect(recorder.snapshotInvocations.count == 2)
  }

  @Test("Harvest, Let go, and Reopen require confirmation and refresh only after persistence")
  func performsLifecycleMutations() throws {
    let fixture = try GoalDetailFixture()
    let open = fixture.accumulateSnapshot()
    let harvested = fixture.accumulateSnapshot(closure: .harvested, destinations: [])
    let reopened = fixture.accumulateSnapshot()
    let letGo = fixture.accumulateSnapshot(closure: .letGo, destinations: [])
    let recorder = GoalDetailOperationsRecorder(
      snapshots: [.success(open), .success(harvested), .success(reopened), .success(letGo)]
    )
    let model = fixture.model(operations: recorder.operations)
    model.start()

    model.requestConfirmation(.harvest)
    #expect(recorder.lifecycleInvocations.isEmpty)
    model.confirmPendingAction()
    #expect(recorder.lifecycleInvocations == [.close(.harvested)])
    #expect(model.presentation?.closureText == "Harvested")

    model.requestConfirmation(.reopen)
    model.confirmPendingAction()
    #expect(recorder.lifecycleInvocations.last == .reopen)
    #expect(model.presentation?.closureText == nil)

    model.requestConfirmation(.letGo)
    model.confirmPendingAction()
    #expect(recorder.lifecycleInvocations.last == .close(.letGo))
    #expect(model.presentation?.closureText == "Let go")
  }

  @Test("goal deletion signals dismissal without attempting a missing-goal reload")
  func deletesGoalWithoutReload() throws {
    let fixture = try GoalDetailFixture()
    let recorder = GoalDetailOperationsRecorder(snapshots: [.success(fixture.accumulateSnapshot())])
    let model = fixture.model(operations: recorder.operations)
    model.start()

    model.requestConfirmation(.deleteGoal)
    model.confirmPendingAction()

    #expect(recorder.deleteGoalInvocations == 1)
    #expect(recorder.snapshotInvocations.count == 1)
    #expect(model.isDeleted)
    #expect(!model.canMutate)
    #expect(model.confirmation == nil)
  }

  @Test("failed append preserves presentation and draft, retries the exact request, and can be cancelled")
  func retriesAndCancelsFailedAppendWithoutOptimisticDrift() throws {
    let fixture = try GoalDetailFixture()
    let initial = fixture.accumulateSnapshot(total: 1, destinations: [.today])
    let refreshed = fixture.accumulateSnapshot(total: 3, destinations: [.today])
    let recorder = GoalDetailOperationsRecorder(
      snapshots: [.success(initial), .success(refreshed)],
      appendResults: [.failure(TestGoalDetailFailure.append), .success(())]
    )
    let capturedInstant = fixture.instant.addingTimeInterval(60)
    let unusedRetryInstant = fixture.instant.addingTimeInterval(86_400)
    let capturedTimeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let unusedRetryTimeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    var instants = [fixture.instant, capturedInstant, unusedRetryInstant]
    var timeZones = [fixture.timeZone, capturedTimeZone, unusedRetryTimeZone]
    let model = GoalDetailModel(
      goal: fixture.goal,
      operations: recorder.operations,
      now: { instants.removeFirst() },
      timeZone: { timeZones.removeFirst() },
      calendar: { fixture.calendar },
      locale: { fixture.locale }
    )
    model.start()
    let lastGood = model.presentation
    model.presentEntrySheet()
    model.entryText = "2"

    model.saveEntry()

    #expect(model.presentation == lastGood)
    #expect(model.isPresentingEntrySheet)
    #expect(model.entryText == "2")
    #expect(model.operationFailure?.placement == .entrySheet)
    #expect(!model.canMutate)
    model.entryText = "9"
    model.requestConfirmation(.harvest)
    #expect(model.confirmation == nil)

    model.retryOperation()

    #expect(recorder.appendInvocations.count == 2)
    #expect(recorder.appendInvocations.first == recorder.appendInvocations.last)
    #expect(recorder.appendInvocations.last?.instant == capturedInstant)
    #expect(recorder.appendInvocations.last?.timeZone == capturedTimeZone)
    #expect(instants == [unusedRetryInstant])
    #expect(timeZones == [unusedRetryTimeZone])
    #expect(model.presentation?.progressText == "3 of 10 times")
    #expect(!model.isPresentingEntrySheet)

    let cancellingRecorder = GoalDetailOperationsRecorder(
      snapshots: [.success(initial)],
      appendResults: [.failure(TestGoalDetailFailure.append)]
    )
    let cancellingModel = fixture.model(operations: cancellingRecorder.operations)
    cancellingModel.start()
    cancellingModel.presentEntrySheet()
    cancellingModel.entryText = "2"
    cancellingModel.saveEntry()
    cancellingModel.cancelOperationFailure()
    #expect(cancellingModel.operationFailure == nil)
    #expect(!cancellingModel.isPresentingEntrySheet)
    #expect(cancellingRecorder.appendInvocations.count == 1)
  }

  @Test("failed lifecycle operation retains confirmation until retry or cancel")
  func preservesLifecycleFailureContext() throws {
    let fixture = try GoalDetailFixture()
    let open = fixture.accumulateSnapshot()
    let closed = fixture.accumulateSnapshot(closure: .harvested, destinations: [])
    let recorder = GoalDetailOperationsRecorder(
      snapshots: [.success(open), .success(closed)],
      lifecycleResults: [.failure(TestGoalDetailFailure.lifecycle), .success(())]
    )
    let model = fixture.model(operations: recorder.operations)
    model.start()
    model.requestConfirmation(.harvest)
    model.confirmPendingAction()

    #expect(model.confirmation == .harvest)
    #expect(model.presentation?.closureText == nil)
    #expect(model.operationFailure?.placement == .lifecycle)

    model.retryOperation()
    #expect(recorder.lifecycleInvocations == [.close(.harvested), .close(.harvested)])
    #expect(model.confirmation == nil)
    #expect(model.presentation?.closureText == "Harvested")

    let cancelRecorder = GoalDetailOperationsRecorder(
      snapshots: [.success(open)],
      lifecycleResults: [.failure(TestGoalDetailFailure.lifecycle)]
    )
    let cancelModel = fixture.model(operations: cancelRecorder.operations)
    cancelModel.start()
    cancelModel.requestConfirmation(.letGo)
    cancelModel.confirmPendingAction()
    cancelModel.cancelOperationFailure()
    #expect(cancelModel.confirmation == nil)
    #expect(cancelModel.operationFailure == nil)
    #expect(cancelModel.presentation?.closureText == nil)
  }

  @Test("committed mutation reload failure locks mutations and retries reload without duplicating persistence")
  func recoversCommittedMutationWithReloadOnlyRetry() throws {
    let fixture = try GoalDetailFixture()
    let initial = fixture.accumulateSnapshot(total: 1, destinations: [.today])
    let refreshed = fixture.accumulateSnapshot(total: 3, destinations: [.today])
    let recorder = GoalDetailOperationsRecorder(
      snapshots: [.success(initial), .failure(TestGoalDetailFailure.load), .success(refreshed)]
    )
    let model = fixture.model(operations: recorder.operations)
    model.start()
    let lastGood = model.presentation
    model.presentEntrySheet()
    model.entryText = "2"
    model.saveEntry()

    #expect(recorder.appendInvocations.count == 1)
    #expect(model.presentation == lastGood)
    #expect(model.operationFailure?.placement == .reload)
    #expect(model.operationFailure?.canCancel == false)
    #expect(model.isPresentingEntrySheet)
    #expect(!model.canMutate)

    model.saveEntry()
    model.requestConfirmation(.harvest)
    model.confirmPendingAction()
    #expect(recorder.appendInvocations.count == 1)
    #expect(recorder.lifecycleInvocations.isEmpty)

    model.cancelOperationFailure()
    #expect(model.operationFailure?.placement == .reload)
    model.retryOperation()

    #expect(recorder.appendInvocations.count == 1)
    #expect(recorder.snapshotInvocations.count == 3)
    #expect(model.presentation?.progressText == "3 of 10 times")
    #expect(model.operationFailure == nil)
    #expect(!model.isPresentingEntrySheet)
    #expect(model.canMutate)
  }

  @Test("measure append captures signed value and destination before dispatch")
  func appendsExactSignedMeasurePayload() throws {
    let fixture = try GoalDetailFixture()
    let initial = fixture.measureSnapshot(destinations: [.yesterday])
    let refreshed = fixture.measureSnapshot(current: -4, destinations: [.yesterday])
    let recorder = GoalDetailOperationsRecorder(
      snapshots: [.success(initial), .success(refreshed)]
    )
    let model = fixture.model(operations: recorder.operations)
    model.start()
    model.presentEntrySheet()
    model.entryText = "-4"

    model.saveEntry()

    #expect(
      recorder.appendInvocations.only
        == .init(
          kind: .measure,
          value: -4,
          destination: .yesterday,
          instant: fixture.instant,
          timeZone: fixture.timeZone
        )
    )
  }

  @Test("history and goal-delete failures retain their own confirmation and cancel safely")
  func preservesDeletionFailureContexts() throws {
    let fixture = try GoalDetailFixture()
    let entryID = GoalEntryIdentity(rawValue: UUID())
    let today = try #require(GoalDate(year: 2026, month: 1, day: 15))
    let history: [GoalDetailHistoryItem] = [
      .entry(
        .init(
          id: entryID,
          assignedDate: today,
          amount: 1,
          appendedAt: fixture.instant,
          appendSequence: 1,
          isDeleteEligible: true
        ))
    ]
    let snapshot = fixture.accumulateSnapshot(total: 1, history: history)
    let recorder = GoalDetailOperationsRecorder(
      snapshots: [.success(snapshot)],
      deleteResults: [.failure(TestGoalDetailFailure.deletion)],
      deleteGoalResults: [.failure(TestGoalDetailFailure.deletion)]
    )
    let model = fixture.model(operations: recorder.operations)
    model.start()

    model.requestHistoryDeletion(.entry(entryID))
    model.confirmPendingAction()
    #expect(model.confirmation == .deleteHistory(.entry(entryID)))
    #expect(model.operationFailure?.placement == .history)
    #expect(model.presentation?.history.count == 1)
    model.cancelOperationFailure()
    #expect(model.confirmation == nil)
    #expect(model.presentation?.history.count == 1)

    model.requestConfirmation(.deleteGoal)
    model.confirmPendingAction()
    #expect(model.confirmation == .deleteGoal)
    #expect(model.operationFailure?.placement == .goalDeletion)
    #expect(!model.isDeleted)
    model.cancelOperationFailure()
    #expect(model.confirmation == nil)
    #expect(!model.isDeleted)
  }

  @Test("entry, Edit, and confirmation interactions are mutually exclusive")
  func keepsOneInteractionContext() throws {
    let fixture = try GoalDetailFixture()
    let model = fixture.loadedModel(
      snapshot: fixture.accumulateSnapshot(destinations: [.today, .yesterday])
    )

    model.presentEntrySheet()
    model.entryText = "7"
    model.selectAppendDestination(.yesterday)
    model.presentEntrySheet()
    model.presentEdit()
    model.requestConfirmation(.harvest)
    #expect(model.isPresentingEntrySheet)
    #expect(!model.isPresentingEdit)
    #expect(model.confirmation == nil)
    #expect(model.entryText == "7")
    #expect(model.selectedAppendDestination == .yesterday)

    model.cancelEntrySheet()
    model.presentEdit()
    model.presentEntrySheet()
    model.requestConfirmation(.deleteGoal)
    #expect(model.isPresentingEdit)
    #expect(!model.isPresentingEntrySheet)
    #expect(model.confirmation == nil)

    model.editCancelled()
    model.requestConfirmation(.harvest)
    model.requestConfirmation(.letGo)
    model.presentEntrySheet()
    model.presentEdit()
    #expect(model.confirmation == .harvest)
    #expect(!model.isPresentingEntrySheet)
    #expect(!model.isPresentingEdit)
  }

  @Test("synchronous operation reentry cannot duplicate a save")
  func guardsReentrantSave() throws {
    let fixture = try GoalDetailFixture()
    let initial = fixture.accumulateSnapshot(destinations: [.today])
    let refreshed = fixture.accumulateSnapshot(total: 2, destinations: [.today])
    var model: GoalDetailModel?
    var appendCalls = 0
    let operations = GoalDetailOperations(
      snapshot: { _, _, _, _ in appendCalls == 0 ? initial : refreshed },
      appendAmount: { _, _, _, _, _ in
        appendCalls += 1
        model?.saveEntry()
      }
    )
    model = fixture.model(operations: operations)
    model?.start()
    model?.presentEntrySheet()
    model?.entryText = "2"

    model?.saveEntry()

    #expect(appendCalls == 1)
    #expect(model?.presentation?.progressText == "2 of 10 times")
    #expect(model?.isOperationInFlight == false)
  }

  @Test("malformed query output never replaces the last good presentation")
  func rejectsMalformedQueryOutput() throws {
    let fixture = try GoalDetailFixture()
    let good = fixture.accumulateSnapshot(name: "Good")
    let wrongID = fixture.accumulateSnapshot(id: UUID(), name: "Wrong identity")
    let mismatchedKind = GoalDetailSnapshot(
      metadata: good.metadata,
      progress: fixture.measureSnapshot().progress,
      standing: good.standing,
      availableAppendDestinations: good.availableAppendDestinations,
      history: good.history
    )
    let recorder = GoalDetailOperationsRecorder(
      snapshots: [.success(good), .success(wrongID), .success(mismatchedKind)]
    )
    let model = fixture.model(operations: recorder.operations)
    model.start()
    let lastGood = model.presentation

    model.refresh()
    #expect(model.presentation == lastGood)
    #expect(model.loadFailure != nil)

    model.retryLoad()
    #expect(model.presentation == lastGood)
    #expect(model.loadFailure != nil)
  }

  @Test("projection rejects missing open standing, closed standing, and nonfinite expectations")
  func rejectsMalformedStandingContracts() throws {
    let fixture = try GoalDetailFixture()
    let standing = GoalStandingSnapshot(
      standing: .onPace,
      actualNormalizedProgress: 0,
      expectedNormalizedProgress: 0.5,
      deadlineBoundary: nil,
      nextTimeRefresh: nil
    )
    let malformed = [
      fixture.accumulateSnapshot(omitsStanding: true),
      fixture.accumulateSnapshot(
        closure: .harvested,
        standing: standing,
        destinations: []
      ),
      fixture.accumulateSnapshot(
        standing: GoalStandingSnapshot(
          standing: .behind,
          actualNormalizedProgress: 0,
          expectedNormalizedProgress: .infinity,
          deadlineBoundary: nil,
          nextTimeRefresh: nil
        )
      ),
    ]

    for snapshot in malformed {
      let model = fixture.loadedModel(snapshot: snapshot)
      #expect(model.presentation == nil)
      #expect(model.loadFailure != nil)
    }
  }

  @Test("selected identity is captured once while every presentation fact comes from the query")
  func keepsStableSelectedIdentity() throws {
    let fixture = try GoalDetailFixture()
    let selectedID = fixture.goal.id
    let recorder = GoalDetailOperationsRecorder(
      snapshots: [.success(fixture.accumulateSnapshot(id: selectedID, name: "Query name"))]
    )
    let model = fixture.model(operations: recorder.operations)
    fixture.goal.id = UUID()
    fixture.goal.name = "Raw mutated name"
    fixture.goal.target = 999

    model.start()

    #expect(model.goalID == selectedID)
    #expect(model.presentation?.goalID == selectedID)
    #expect(model.presentation?.name == "Query name")
    #expect(model.presentation?.progressText == "0 of 10 times")
    #expect(recorder.snapshotInvocations.only?.goal === fixture.goal)
  }

  @Test("live history deletion delegates exactly-one-owned children and rejects every other cardinality")
  func liveDeletionResolvesExactlyOneOwnedChild() throws {
    let fixture = try GoalDetailFixture()
    let container = try TendModelContainer.inMemory()
    let context = container.mainContext
    let goal = Goal(name: "Walk", kind: .accumulate, target: 10)
    let foreignGoal = Goal(name: "Read", kind: .accumulate, target: 10)
    context.insert(goal)
    context.insert(foreignGoal)
    let date = try #require(GoalDate(year: 2026, month: 1, day: 15))
    let sharedID = UUID()
    let foreign = GoalEntry(
      id: sharedID,
      amount: 9,
      assignedDate: date,
      appendedAt: fixture.instant,
      appendSequence: 1,
      goal: foreignGoal
    )
    context.insert(foreign)
    try context.save()
    let operations = GoalDetailOperations.live(context: context)

    #expect(
      try operations.deleteHistory(
        .entry(.init(rawValue: sharedID)), goal, fixture.instant, fixture.timeZone
      ) == .rejected
    )
    #expect(foreign.modelContext != nil)
    let entryID = UUID()
    let entry = GoalEntry(
      id: entryID,
      amount: 2,
      assignedDate: date,
      appendedAt: fixture.instant,
      appendSequence: 1,
      goal: goal
    )
    context.insert(entry)
    try context.save()
    #expect(
      try operations.deleteHistory(
        .entry(.init(rawValue: entryID)), goal, fixture.instant, fixture.timeZone
      ) == .deleted
    )
    let deletedEntries = try context.fetch(
      FetchDescriptor<GoalEntry>(predicate: #Predicate { $0.id == entryID })
    )
    #expect(deletedEntries.isEmpty)

    let measureGoal = Goal(
      name: "Weight",
      kind: .measure,
      target: 20,
      unit: "kg",
      baseline: 10,
      createdAt: fixture.instant.addingTimeInterval(-86_400)
    )
    let readingID = UUID()
    let reading = GoalReading(
      id: readingID,
      value: 15,
      assignedDate: date,
      appendedAt: fixture.instant,
      appendSequence: 1,
      goal: measureGoal
    )
    context.insert(measureGoal)
    context.insert(reading)
    try context.save()
    #expect(
      try operations.deleteHistory(
        .reading(.init(rawValue: readingID)),
        measureGoal,
        fixture.instant,
        fixture.timeZone
      ) == .deleted
    )
    let deletedReadings = try context.fetch(
      FetchDescriptor<GoalReading>(predicate: #Predicate { $0.id == readingID })
    )
    #expect(deletedReadings.isEmpty)


    let ambiguousID = UUID()
    let first = GoalEntry(id: ambiguousID, amount: 1, assignedDate: date, appendedAt: fixture.instant, appendSequence: 1, goal: goal)
    let second = GoalEntry(id: ambiguousID, amount: 2, assignedDate: date, appendedAt: fixture.instant, appendSequence: 2, goal: goal)
    context.insert(first)
    context.insert(second)
    try context.save()

    #expect(
      try operations.deleteHistory(
        .entry(.init(rawValue: ambiguousID)), goal, fixture.instant, fixture.timeZone
      ) == .rejected
    )
    let matches = try context.fetch(
      FetchDescriptor<GoalEntry>(predicate: #Predicate { $0.id == ambiguousID })
    )
    #expect(matches.count == 2)
  }
}

@MainActor
private final class GoalDetailOperationsRecorder {
  struct SnapshotInvocation {
    let goal: Goal
    let instant: Date
    let calendar: Calendar
    let timeZone: TimeZone
  }

  struct AppendInvocation: Equatable {
    let kind: GoalKind
    let value: Int
    let destination: GoalProgressDestination
    let instant: Date
    let timeZone: TimeZone
  }

  enum LifecycleInvocation: Equatable {
    case close(GoalClosure)
    case reopen
  }

  var snapshotInvocations: [SnapshotInvocation] = []
  var appendInvocations: [AppendInvocation] = []
  var deleteInvocations: [GoalDetailHistoryID] = []
  var lifecycleInvocations: [LifecycleInvocation] = []
  var deleteGoalInvocations = 0

  private var snapshots: [Result<GoalDetailSnapshot, TestGoalDetailFailure>]
  private var appendResults: [Result<Void, TestGoalDetailFailure>]
  private var deleteResults: [Result<GoalDetailDeleteHistoryResult, TestGoalDetailFailure>]
  private var lifecycleResults: [Result<Void, TestGoalDetailFailure>]
  private var deleteGoalResults: [Result<Void, TestGoalDetailFailure>]

  init(
    snapshots: [Result<GoalDetailSnapshot, TestGoalDetailFailure>],
    appendResults: [Result<Void, TestGoalDetailFailure>] = [],
    deleteResults: [Result<GoalDetailDeleteHistoryResult, TestGoalDetailFailure>] = [],
    lifecycleResults: [Result<Void, TestGoalDetailFailure>] = [],
    deleteGoalResults: [Result<Void, TestGoalDetailFailure>] = []
  ) {
    self.snapshots = snapshots
    self.appendResults = appendResults
    self.deleteResults = deleteResults
    self.lifecycleResults = lifecycleResults
    self.deleteGoalResults = deleteGoalResults
  }

  var operations: GoalDetailOperations {
    GoalDetailOperations(
      snapshot: { [unowned self] goal, instant, calendar, timeZone in
        snapshotInvocations.append(.init(goal: goal, instant: instant, calendar: calendar, timeZone: timeZone))
        guard !snapshots.isEmpty else { throw TestGoalDetailFailure.load }
        return try snapshots.removeFirst().get()
      },
      appendAmount: { [unowned self] value, _, destination, instant, timeZone in
        appendInvocations.append(.init(kind: .accumulate, value: value, destination: destination, instant: instant, timeZone: timeZone))
        try next(&appendResults, fallback: ()).get()
      },
      appendValue: { [unowned self] value, _, destination, instant, timeZone in
        appendInvocations.append(.init(kind: .measure, value: value, destination: destination, instant: instant, timeZone: timeZone))
        try next(&appendResults, fallback: ()).get()
      },
      deleteHistory: { [unowned self] id, _, _, _ in
        deleteInvocations.append(id)
        return try next(&deleteResults, fallback: .deleted).get()
      },
      close: { [unowned self] _, closure in
        lifecycleInvocations.append(.close(closure))
        try next(&lifecycleResults, fallback: ()).get()
      },
      reopen: { [unowned self] _ in
        lifecycleInvocations.append(.reopen)
        try next(&lifecycleResults, fallback: ()).get()
      },
      deleteGoal: { [unowned self] _ in
        deleteGoalInvocations += 1
        try next(&deleteGoalResults, fallback: ()).get()
      }
    )
  }

  private func next<Value>(
    _ results: inout [Result<Value, TestGoalDetailFailure>],
    fallback: @autoclosure () -> Value
  ) -> Result<Value, TestGoalDetailFailure> {
    guard !results.isEmpty else { return .success(fallback()) }
    return results.removeFirst()
  }
}

@MainActor
private final class GoalDetailFixture {
  let instant: Date
  let timeZone: TimeZone
  let calendar: Calendar
  let locale: Locale
  let goal: Goal

  init() throws {
    timeZone = try #require(TimeZone(identifier: "UTC"))
    locale = Locale(identifier: "en_US")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.locale = locale
    self.calendar = calendar
    instant = try Self.date("2026-01-15T12:00:00Z")
    goal = Goal(
      id: UUID(),
      name: "Raw goal",
      kind: .accumulate,
      target: 999,
      createdAt: try Self.date("2026-01-01T12:00:00Z")
    )
  }

  func model(operations: GoalDetailOperations) -> GoalDetailModel {
    GoalDetailModel(
      goal: goal,
      operations: operations,
      now: { [instant] in instant },
      timeZone: { [timeZone] in timeZone },
      calendar: { [calendar] in calendar },
      locale: { [locale] in locale }
    )
  }

  func loadedModel(snapshot: GoalDetailSnapshot) -> GoalDetailModel {
    let recorder = GoalDetailOperationsRecorder(snapshots: [.success(snapshot)])
    let model = self.model(operations: recorder.operations)
    model.start()
    return model
  }

  func accumulateSnapshot(
    id: UUID? = nil,
    name: String = "Walk",
    total: Int = 0,
    target: Int = 10,
    unit: String = "times",
    deadline: GoalDate? = nil,
    closure: GoalClosure? = nil,
    standing: GoalStandingSnapshot? = nil,
    omitsStanding: Bool = false,
    destinations: [GoalProgressDestination] = [.today],
    history: [GoalDetailHistoryItem] = []
  ) -> GoalDetailSnapshot {
    let normalizedProgress = Double(total) / Double(target)
    let resolvedStanding = standingSnapshot(
      closure: closure,
      standing: standing,
      omitsStanding: omitsStanding,
      actualNormalizedProgress: normalizedProgress
    )
    return GoalDetailSnapshot(
      metadata: GoalDetailMetadata(
        id: id ?? goal.id,
        name: name,
        kind: .accumulate,
        target: target,
        unit: unit,
        baseline: nil,
        deadline: deadline,
        createdAt: goal.createdAt,
        closure: closure
      ),
      progress: .accumulate(
        AccumulateGoalProgress(
          total: total,
          target: target,
          unit: unit,
          normalizedProgress: normalizedProgress
        )),
      standing: resolvedStanding,
      availableAppendDestinations: destinations,
      history: history
    )
  }

  func measureSnapshot(
    baseline: Int = 10,
    target: Int = 20,
    current: Int = 15,
    unit: String = "kg",
    closure: GoalClosure? = nil,
    standing: GoalStandingSnapshot? = nil,
    omitsStanding: Bool = false,
    destinations: [GoalProgressDestination] = [.today],
    history: [GoalDetailHistoryItem] = []
  ) -> GoalDetailSnapshot {
    let totalDistance = abs(target - baseline)
    let completedDistance = target >= baseline ? current - baseline : baseline - current
    let normalizedProgress = Double(completedDistance) / Double(totalDistance)
    let resolvedStanding = standingSnapshot(
      closure: closure,
      standing: standing,
      omitsStanding: omitsStanding,
      actualNormalizedProgress: normalizedProgress
    )
    return GoalDetailSnapshot(
      metadata: GoalDetailMetadata(
        id: goal.id,
        name: "Weight",
        kind: .measure,
        target: target,
        unit: unit,
        baseline: baseline,
        deadline: nil,
        createdAt: goal.createdAt,
        closure: closure
      ),
      progress: .measure(
        MeasureGoalProgress(
          baseline: baseline,
          target: target,
          currentValue: current,
          effectiveReadingID: nil,
          completedDistance: completedDistance,
          totalDistance: totalDistance,
          unit: unit,
          normalizedProgress: normalizedProgress
        )),
      standing: resolvedStanding,
      availableAppendDestinations: destinations,
      history: history
    )
  }

  private func standingSnapshot(
    closure: GoalClosure?,
    standing: GoalStandingSnapshot?,
    omitsStanding: Bool,
    actualNormalizedProgress: Double
  ) -> GoalStandingSnapshot? {
    if closure != nil {
      return standing
    }
    if omitsStanding {
      return nil
    }
    return standing
      ?? GoalStandingSnapshot(
        standing: .onPace,
        actualNormalizedProgress: actualNormalizedProgress,
        expectedNormalizedProgress: nil,
        deadlineBoundary: nil,
        nextTimeRefresh: nil
      )
  }

  private static func date(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    return try #require(formatter.date(from: value))
  }
}

private enum TestGoalDetailFailure: LocalizedError {
  case load
  case append
  case lifecycle
  case deletion

  var errorDescription: String? {
    switch self {
    case .load: "Test load failure"
    case .append: "Test append failure"
    case .lifecycle: "Test lifecycle failure"
    case .deletion: "Test deletion failure"
    }
  }
}

private extension Collection {
  var only: Element? { count == 1 ? first : nil }
}
