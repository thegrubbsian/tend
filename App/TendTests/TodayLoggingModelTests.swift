import Foundation
import SwiftData
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Today logging model")
struct TodayLoggingModelTests {
  @Test("only the exact times unit appends from current activation")
  func exactTimesDispatchesDirectAppend() throws {
    let context = try makeContext()
    let refreshContext = makeRefreshContext()
    let times = try insertHabit(in: context, name: "Exact", target: 2, unit: "times")
    let quantityUnits = ["time", "times ", "Times", "repetitions"]
    let quantities = try quantityUnits.map {
      try insertHabit(in: context, name: "Quantity \($0)", target: 10, unit: $0)
    }
    let habits = [times] + quantities
    var progressByID = Dictionary(
      uniqueKeysWithValues: habits.map { ($0.persistentModelID, 0) })
    var appendCalls: [(Int, PersistentIdentifier, LogEntryDestination, TodayRefreshContext)] = []
    var reminderRefreshCount = 0
    let todayModel = TodayModel(
      operations: TodayOperations { habit, _ in
        todaySnapshot(
          progress: progressByID[habit.persistentModelID, default: 0],
          target: habit.target,
          unit: habit.unit
        )
      })
    todayModel.refresh(habits: habits, context: refreshContext)
    let operations = TodayLoggingOperations(
      snapshot: { habit, _ in
        loggingSnapshot(
          habit: habit,
          progress: progressByID[habit.persistentModelID, default: 0]
        )
      },
      append: { amount, habit, destination, receivedContext in
        appendCalls.append((amount, habit.persistentModelID, destination, receivedContext))
        progressByID[habit.persistentModelID, default: 0] += amount
        return try insertEntry(
          in: context,
          habit: habit,
          amount: amount,
          timestamp: receivedContext.instant
        )
      },
      setTotal: { _, _, _, _ in nil },
      delete: { _, _, _ in }
    )
    let model = TodayLoggingModel(
      todayModel: todayModel,
      operations: operations,
      sleep: longSleep,
      reminderRefresh: { reminderRefreshCount += 1 }
    )
    model.activateCurrent(habit: times, habits: habits, context: refreshContext)

    #expect(appendCalls.count == 1)
    #expect(appendCalls[0].0 == 1)
    #expect(appendCalls[0].1 == times.persistentModelID)
    #expect(appendCalls[0].2 == .current)
    #expect(appendCalls[0].3 == refreshContext)
    #expect(model.state.sheet == nil)
    #expect(model.state.undo?.habitID == times.persistentModelID)
    #expect(model.state.undo?.amount == 1)
    #expect(model.state.feedback?.kind == .logged)
    #expect(reminderRefreshCount == 1)

    for quantity in quantities {
      model.activateCurrent(habit: quantity, habits: habits, context: refreshContext)
      #expect(model.state.sheet?.habitID == quantity.persistentModelID)
    }
    #expect(appendCalls.count == 1)
  }

  @Test("current and at-risk activation preserve explicit bucket identity and cadence labels")
  func activationsPreserveScopeIdentityAndLabels() throws {
    let context = try makeContext()
    let refreshContext = makeRefreshContext()
    let daily = try insertHabit(
      in: context,
      name: "Walk",
      target: 8_000,
      unit: "steps"
    )
    let weekly = try insertHabit(
      in: context,
      name: "Read",
      cadence: .weekly,
      target: 3,
      unit: "chapters"
    )
    let count = try insertHabit(
      in: context,
      name: "Posture",
      target: 4,
      unit: "times"
    )
    let habits = [daily, weekly, count]
    var appendDestinations: [LogEntryDestination] = []
    var reminderRefreshCount = 0
    let snapshots: [PersistentIdentifier: HabitLoggingSnapshot] = [
      daily.persistentModelID: loggingSnapshot(
        habit: daily,
        progress: 4_000,
        graceProgress: 3_000
      ),
      weekly.persistentModelID: loggingSnapshot(
        habit: weekly,
        progress: 1,
        graceProgress: 3,
        currentKey: "week:2026-08-03",
        graceKey: "week:2026-07-27"
      ),
      count.persistentModelID: loggingSnapshot(
        habit: count,
        progress: 1,
        graceProgress: 2
      ),
    ]
    let todayModel = TodayModel(
      operations: TodayOperations { habit, _ in
        let snapshot = try #require(snapshots[habit.persistentModelID])
        return todaySnapshot(
          progress: snapshot.current.progress,
          target: snapshot.target,
          unit: snapshot.unit,
          cadence: snapshot.cadence,
          currentStreak: 3,
          isAtRisk: snapshot.grace?.isMet == false,
          isMet: snapshot.current.isMet
        )
      })
    todayModel.refresh(habits: habits, context: refreshContext)
    let operations = TodayLoggingOperations(
      snapshot: { habit, _ in
        try #require(snapshots[habit.persistentModelID])
      },
      append: { amount, habit, destination, receivedContext in
        #expect(amount == 1)
        #expect(habit === count)
        #expect(receivedContext == refreshContext)
        appendDestinations.append(destination)
        return try insertEntry(
          in: context,
          habit: habit,
          amount: amount,
          timestamp: receivedContext.instant
        )
      },
      setTotal: { _, _, _, _ in nil },
      delete: { _, _, _ in }
    )
    let model = TodayLoggingModel(
      todayModel: todayModel,
      operations: operations,
      sleep: longSleep,
      reminderRefresh: { reminderRefreshCount += 1 }
    )
    model.activateCurrent(habit: daily, habits: habits, context: refreshContext)
    var sheet = try #require(model.state.sheet)
    #expect(sheet.selectedPeriodKey == "day:2026-08-05")
    #expect(sheet.scopes.map(\.label) == ["Today", "Yesterday"])
    #expect(sheet.scopes.map(\.entryListLabel) == ["LOGGED TODAY", "LOGGED YESTERDAY"])
    #expect(sheet.scopes.map(\.showsUnfinishedMarker) == [false, true])
    #expect(sheet.currentStreak == 3)

    model.activateAtRisk(habit: daily, habits: habits, context: refreshContext)
    sheet = try #require(model.state.sheet)
    #expect(sheet.selectedPeriodKey == "day:2026-08-04")
    #expect(sheet.progress == 3_000)

    model.activateAtRisk(habit: weekly, habits: habits, context: refreshContext)
    sheet = try #require(model.state.sheet)
    #expect(sheet.selectedPeriodKey == "week:2026-07-27")
    #expect(sheet.scopes.map(\.label) == ["This Week", "Last Week"])
    #expect(sheet.scopes.map(\.entryListLabel) == ["LOGGED THIS WEEK", "LOGGED LAST WEEK"])
    #expect(sheet.scopes.map(\.showsUnfinishedMarker) == [false, false])

    model.activateAtRisk(habit: count, habits: habits, context: refreshContext)
    #expect(appendDestinations == [.periodKey("day:2026-08-04")])
    #expect(model.state.sheet == nil)
    #expect(reminderRefreshCount == 1)
  }

  @Test("transient card state resolves only for its persistent habit identity")
  func transientCardStateIsHabitScoped() throws {
    let context = try makeContext()
    let refreshContext = makeRefreshContext()
    let first = try insertHabit(in: context, name: "First", target: 2, unit: "times")
    let second = try insertHabit(in: context, name: "Second", target: 10, unit: "steps")
    let habits = [first, second]
    var shouldFail = true
    var progress = 0
    var entries: [HabitLoggingEntrySnapshot] = []
    let todayModel = TodayModel(
      operations: TodayOperations { habit, _ in
        todaySnapshot(
          progress: habit === first ? progress : 0,
          target: habit.target,
          unit: habit.unit
        )
      })
    todayModel.refresh(habits: habits, context: refreshContext)
    let operations = TodayLoggingOperations(
      snapshot: { habit, _ in
        loggingSnapshot(
          habit: habit,
          progress: habit === first ? progress : 0,
          currentEntries: habit === first ? entries : []
        )
      },
      append: { amount, habit, _, receivedContext in
        if shouldFail {
          throw FixtureFailure.operation
        }
        let entry = try insertEntry(
          in: context,
          habit: habit,
          amount: amount,
          timestamp: receivedContext.instant
        )
        progress += amount
        entries = [
          HabitLoggingEntrySnapshot(
            id: entry.persistentModelID,
            uuid: entry.id,
            timestamp: entry.timestamp,
            amount: entry.amount,
            entry: entry
          )
        ]
        return entry
      },
      setTotal: { _, _, _, _ in nil },
      delete: { _, _, _ in }
    )
    let model = TodayLoggingModel(
      todayModel: todayModel,
      operations: operations,
      sleep: longSleep
    )

    model.activateCurrent(habit: first, habits: habits, context: refreshContext)

    #expect(
      model.state.actionFailure(for: first.persistentModelID)?.message
        == "Fixture operation failed.")
    #expect(model.state.actionFailure(for: second.persistentModelID) == nil)

    shouldFail = false
    model.activateCurrent(habit: first, habits: habits, context: refreshContext)

    #expect(model.state.undo(for: first.persistentModelID)?.habitID == first.persistentModelID)
    #expect(model.state.undo(for: second.persistentModelID) == nil)
    #expect(model.state.actionFailure(for: first.persistentModelID) == nil)
  }

  @Test("friendly quick-add values are overflow-safe ordered and deduplicated from Finish")
  func quickAddAmountsMatchContract() {
    #expect(QuickAddAmounts(target: 3, progress: 0) == .init(presets: [1], finish: 3))
    #expect(QuickAddAmounts(target: 30, progress: 0) == .init(presets: [5, 10], finish: 30))
    #expect(QuickAddAmounts(target: 64, progress: 44) == .init(presets: [10], finish: 20))
    #expect(
      QuickAddAmounts(target: 8_000, progress: 4_000)
        == .init(presets: [1_000, 2_000], finish: 4_000)
    )
    #expect(QuickAddAmounts(target: 30, progress: 20) == .init(presets: [5], finish: 10))
    #expect(QuickAddAmounts(target: 30, progress: 30) == .init(presets: [5, 10], finish: nil))
    #expect(QuickAddAmounts(target: 30, progress: 40) == .init(presets: [5, 10], finish: nil))
    #expect(
      QuickAddAmounts(target: Int.max, progress: Int.max)
        == .init(
          presets: [1_000_000_000_000_000_000, 2_000_000_000_000_000_000],
          finish: nil
        )
    )
  }

  @Test("amount editors reject invalid local input before any operation")
  func amountValidationStaysLocalAndNonmutating() throws {
    let fixture = try LoggingFixture(target: 10, progress: 3)
    let model = fixture.makeModel()
    fixture.presentSheet(model)

    for input in ["", "0", "-1", "+1", "1.5", " 1", "١", String(repeating: "9", count: 100)] {
      model.beginCustomAmountEditing()
      model.updateAmountInput(input)
      model.submitAmount(habits: fixture.habits, context: fixture.refreshContext)
      #expect(model.state.sheet?.amountInput == input)
      #expect(model.state.sheet?.amountError == "Enter a positive whole number.")
    }
    #expect(fixture.appendAmounts.isEmpty)

    for input in ["", "-1", "+1", "1.5", " 1", "١", String(repeating: "9", count: 100)] {
      model.beginSetTotalEditing()
      model.updateAmountInput(input)
      model.submitAmount(habits: fixture.habits, context: fixture.refreshContext)
      #expect(model.state.sheet?.amountInput == input)
      #expect(model.state.sheet?.amountError == "Enter zero or a positive whole number.")
    }
    model.beginSetTotalEditing()
    model.updateAmountInput("2")
    model.submitAmount(habits: fixture.habits, context: fixture.refreshContext)
    #expect(model.state.sheet?.amountError == "Delete an entry before lowering the total.")
    #expect(fixture.setTotals.isEmpty)
    #expect(model.state.sheet?.progress == 3)
    #expect(model.state.undo == nil)
    #expect(model.state.feedback == nil)
  }

  @Test("quick add custom and set total publish complete post-write state")
  func sheetMutationsPublishCompleteState() throws {
    let fixture = try LoggingFixture(target: 10, progress: 0)
    var reminderRefreshCount = 0
    let model = fixture.makeModel(
      reminderRefresh: { reminderRefreshCount += 1 }
    )
    fixture.presentSheet(model)

    model.appendQuickAdd(
      amount: 2,
      habits: fixture.habits,
      context: fixture.refreshContext
    )
    #expect(model.state.sheet?.progress == 2)
    #expect(model.state.sheet?.entries.map(\.amount) == [2])
    #expect(model.state.undo?.amount == 2)
    #expect(model.state.feedback?.kind == .logged)
    let firstFeedback = try #require(model.state.feedback)
    model.consumeFeedback(firstFeedback.id)
    #expect(model.state.feedback == nil)

    model.beginCustomAmountEditing()
    model.updateAmountInput("3")
    model.submitAmount(habits: fixture.habits, context: fixture.refreshContext)
    #expect(model.state.sheet?.progress == 5)
    #expect(model.state.sheet?.entries.map(\.amount) == [3, 2])
    #expect(model.state.sheet?.amountEditorMode == nil)
    #expect(model.state.sheet?.amountInput.isEmpty == true)
    #expect(model.state.undo?.amount == 3)
    #expect(model.state.feedback?.kind == .logged)
    let secondFeedback = try #require(model.state.feedback)
    model.consumeFeedback(secondFeedback.id)

    model.beginSetTotalEditing()
    model.updateAmountInput("10")
    model.submitAmount(habits: fixture.habits, context: fixture.refreshContext)
    #expect(fixture.setTotals == [10])
    #expect(model.state.sheet?.progress == 10)
    #expect(model.state.sheet?.entries.map(\.amount) == [5, 3, 2])
    #expect(model.state.undo?.amount == 5)
    #expect(model.state.feedback?.kind == .completion)
    let completionFeedback = try #require(model.state.feedback)
    model.consumeFeedback(completionFeedback.id)

    let undoGeneration = try #require(model.state.undo?.generation)
    model.beginSetTotalEditing()
    model.updateAmountInput("10")
    model.submitAmount(habits: fixture.habits, context: fixture.refreshContext)
    #expect(fixture.setTotals == [10, 10])
    #expect(model.state.sheet?.progress == 10)
    #expect(model.state.sheet?.amountEditorMode == nil)
    #expect(model.state.undo?.generation == undoGeneration)
    #expect(model.state.feedback == nil)
    #expect(reminderRefreshCount == 3)
  }

  @Test("each mutation uses one context and reprojects before Today refresh or publication")
  func mutationOrderingIsAtomic() throws {
    let fixture = try LoggingFixture(target: 10, progress: 0)
    var reminderRefreshCount = 0
    let model = fixture.makeModel(
      reminderRefresh: { reminderRefreshCount += 1 }
    )
    fixture.presentSheet(model)
    fixture.events.removeAll()
    fixture.receivedContexts.removeAll()
    fixture.onTodayProjection = {
      #expect(model.state.sheet?.progress == 0)
    }

    model.appendQuickAdd(
      amount: 2,
      habits: fixture.habits,
      context: fixture.refreshContext
    )

    #expect(fixture.events == ["snapshot", "append", "snapshot", "today"])
    #expect(fixture.receivedContexts == Array(repeating: fixture.refreshContext, count: 4))
    #expect(model.state.sheet?.progress == 2)
    #expect(reminderRefreshCount == 1)
    fixture.onTodayProjection = nil

    let acceptedUndo = try #require(model.state.undo?.generation)
    let acceptedFeedback = try #require(model.state.feedback?.id)
    fixture.failAppend = true
    model.appendQuickAdd(
      amount: 2,
      habits: fixture.habits,
      context: fixture.refreshContext
    )
    #expect(model.state.sheet?.progress == 2)
    #expect(model.state.sheet?.sheetError == "Fixture operation failed.")
    #expect(model.state.undo?.generation == acceptedUndo)
    #expect(model.state.feedback?.id == acceptedFeedback)
    #expect(reminderRefreshCount == 1)

    fixture.failAppend = false
    fixture.failNextPostMutationSnapshot = true
    model.appendQuickAdd(
      amount: 2,
      habits: fixture.habits,
      context: fixture.refreshContext
    )
    #expect(fixture.progress == 4)
    #expect(model.state.sheet?.progress == 2)
    #expect(model.state.sheet?.sheetError == "Fixture projection failed.")
    #expect(model.state.undo?.generation == acceptedUndo)
    #expect(model.state.feedback?.id == acceptedFeedback)
    #expect(reminderRefreshCount == 2)
    model.refresh(habits: fixture.habits, goals: [], context: fixture.refreshContext)
    #expect(model.state.sheet?.progress == 4)
    #expect(model.state.sheet?.sheetError == nil)
  }

  @Test("refresh preserves valid selection then falls back or dismisses by identity")
  func refreshTracksLiveScopeAndEligibility() throws {
    let fixture = try LoggingFixture(target: 10, progress: 2, graceProgress: 4)
    let model = fixture.makeModel()
    fixture.presentSheet(model, atRisk: true)
    let graceKey = try #require(model.state.sheet?.selectedPeriodKey)

    fixture.progress = 7
    fixture.graceProgress = 6
    model.refresh(habits: fixture.habits, goals: [], context: fixture.refreshContext)
    #expect(model.state.sheet?.selectedPeriodKey == graceKey)
    #expect(model.state.sheet?.progress == 6)
    #expect(model.state.sheet?.sheetError == nil)

    let announcementBeforeFallback = model.state.announcementToken
    fixture.graceProgress = nil
    model.refresh(habits: fixture.habits, goals: [], context: fixture.refreshContext)
    #expect(model.state.sheet?.selectedPeriodKey == fixture.currentKey)
    #expect(model.state.sheet?.progress == 7)
    #expect(model.state.announcementToken != announcementBeforeFallback)

    fixture.habit.isActive = false
    model.refresh(habits: fixture.habits, goals: [], context: fixture.refreshContext)
    #expect(model.state.sheet == nil)

    fixture.habit.isActive = true
    fixture.presentSheet(model)
    #expect(model.state.sheet != nil)
    model.refresh(habits: [], goals: [], context: fixture.refreshContext)
    #expect(model.state.sheet == nil)
  }

  @Test("a stale selected period falls back before any write")
  func mutationRejectsStaleSelection() throws {
    let fixture = try LoggingFixture(target: 10, progress: 2)
    let model = fixture.makeModel()
    fixture.presentSheet(model)
    let announcementBefore = model.state.announcementToken
    fixture.currentKey = "day:2026-08-06"

    model.appendQuickAdd(amount: 1, habits: fixture.habits, context: fixture.refreshContext)

    #expect(fixture.appendAmounts.isEmpty)
    #expect(model.state.sheet?.selectedPeriodKey == fixture.currentKey)
    #expect(model.state.sheet?.sheetError?.contains("period changed") == true)
    #expect(model.state.announcementToken != announcementBefore)
  }

  @Test("entry deletion targets persistent identity and publishes only after re-projection")
  func deletionUsesExactEntryIdentity() throws {
    let fixture = try LoggingFixture(target: 10, progress: 0)
    let timestamp = fixture.refreshContext.instant.addingTimeInterval(-60)
    let first = try fixture.addEntry(amount: 2, timestamp: timestamp)
    let second = try fixture.addEntry(amount: 3, timestamp: timestamp)
    var reminderRefreshCount = 0
    let model = fixture.makeModel(
      reminderRefresh: { reminderRefreshCount += 1 }
    )
    fixture.presentSheet(model)

    model.deleteEntry(
      first.persistentModelID,
      habits: fixture.habits,
      context: fixture.refreshContext
    )

    #expect(fixture.deletedEntryIDs == [first.persistentModelID])
    #expect(model.state.sheet?.progress == 3)
    #expect(model.state.sheet?.entries.map(\.id) == [second.persistentModelID])
    #expect(model.state.feedback == nil)
    #expect(model.state.undo == nil)
    #expect(Array(fixture.events.suffix(4)) == ["snapshot", "delete", "snapshot", "today"])
    #expect(reminderRefreshCount == 1)

    fixture.failDelete = true
    model.deleteEntry(
      second.persistentModelID,
      habits: fixture.habits,
      context: fixture.refreshContext
    )
    #expect(fixture.deletedEntryIDs == [first.persistentModelID])
    #expect(model.state.sheet?.entries.map(\.id) == [second.persistentModelID])
    #expect(model.state.sheet?.sheetError != nil)
    #expect(reminderRefreshCount == 1)

    let deleteEvents = fixture.events.filter { $0 == "delete" }.count
    model.deleteEntry(
      first.persistentModelID,
      habits: fixture.habits,
      context: fixture.refreshContext
    )
    #expect(fixture.events.filter { $0 == "delete" }.count == deleteEvents)
    #expect(model.state.sheet?.sheetError != nil)
    #expect(reminderRefreshCount == 1)
  }

  @Test("explicit scope selection drives presentation and later writes")
  func scopeSelectionUsesExactPeriodKey() throws {
    let fixture = try LoggingFixture(target: 10, progress: 2, graceProgress: 4)
    let graceEntry = try fixture.addEntry(
      amount: 1,
      destination: .periodKey(fixture.graceKey),
      timestamp: fixture.refreshContext.instant.addingTimeInterval(-120)
    )
    let model = fixture.makeModel()
    fixture.presentSheet(model)
    let announcementBefore = model.state.announcementToken

    model.selectPeriod(
      fixture.graceKey,
      habits: fixture.habits,
      context: fixture.refreshContext
    )
    #expect(model.state.sheet?.selectedPeriodKey == fixture.graceKey)
    #expect(model.state.sheet?.progress == 5)
    #expect(model.state.sheet?.entries.map(\.id) == [graceEntry.persistentModelID])
    #expect(model.state.announcementToken != announcementBefore)

    model.appendQuickAdd(amount: 1, habits: fixture.habits, context: fixture.refreshContext)
    #expect(fixture.appendDestinations.last == .periodKey(fixture.graceKey))
    let undoGeneration = model.state.undo?.generation

    model.beginCustomAmountEditing()
    model.updateAmountInput("3")
    model.cancelAmountEditing()
    #expect(model.state.sheet?.amountEditorMode == nil)
    #expect(model.state.sheet?.amountInput.isEmpty == true)

    model.dismissSheet()
    #expect(model.state.sheet == nil)
    #expect(model.state.undo?.generation == undoGeneration)
  }

  @Test("Undo replaces, retries exact deletion, and expires without mutation")
  func undoLifecycleIsIdentitySafe() async throws {
    let replacementFixture = try LoggingFixture(target: 10, progress: 0)
    var replacementRefreshCount = 0
    let replacementModel = replacementFixture.makeModel(
      reminderRefresh: { replacementRefreshCount += 1 }
    )
    replacementFixture.presentSheet(replacementModel)
    replacementModel.appendQuickAdd(
      amount: 1,
      habits: replacementFixture.habits,
      context: replacementFixture.refreshContext
    )
    let firstUndo = try #require(replacementModel.state.undo)
    replacementModel.appendQuickAdd(
      amount: 1,
      habits: replacementFixture.habits,
      context: replacementFixture.refreshContext
    )
    let replacementUndo = try #require(replacementModel.state.undo)
    #expect(replacementUndo.entryID != firstUndo.entryID)
    #expect(replacementFixture.currentEntries.map(\.persistentModelID).contains(firstUndo.entryID))

    replacementModel.undo(
      habits: replacementFixture.habits,
      context: replacementFixture.refreshContext
    )
    #expect(replacementFixture.deletedEntryIDs == [replacementUndo.entryID])
    #expect(replacementFixture.currentEntries.map(\.persistentModelID) == [firstUndo.entryID])
    #expect(replacementModel.state.undo == nil)
    #expect(replacementModel.state.feedback?.kind == .undo)
    #expect(
      Array(replacementFixture.events.suffix(4)) == ["snapshot", "delete", "snapshot", "today"])
    #expect(replacementRefreshCount == 3)

    let retryFixture = try LoggingFixture(target: 10, progress: 0)
    let retryModel = retryFixture.makeModel()
    retryFixture.presentSheet(retryModel)
    retryModel.appendQuickAdd(
      amount: 1,
      habits: retryFixture.habits,
      context: retryFixture.refreshContext
    )
    let retryUndo = try #require(retryModel.state.undo)
    retryFixture.failDelete = true
    retryModel.undo(habits: retryFixture.habits, context: retryFixture.refreshContext)
    #expect(retryFixture.deletedEntryIDs.isEmpty)
    #expect(retryModel.state.undo?.entryID == retryUndo.entryID)
    #expect(retryModel.state.undo?.error != nil)
    retryFixture.failDelete = false
    retryModel.undo(habits: retryFixture.habits, context: retryFixture.refreshContext)
    #expect(retryFixture.deletedEntryIDs == [retryUndo.entryID])
    #expect(retryModel.state.undo == nil)

    let externalFixture = try LoggingFixture(target: 10, progress: 0)
    let externalModel = externalFixture.makeModel()
    externalFixture.presentSheet(externalModel)
    externalModel.appendQuickAdd(
      amount: 1,
      habits: externalFixture.habits,
      context: externalFixture.refreshContext
    )
    let externalUndo = try #require(externalModel.state.undo)
    let externalFeedback = externalModel.state.feedback?.id
    let externallyDeletedEntry = try #require(
      externalFixture.currentEntries.first {
        $0.persistentModelID == externalUndo.entryID
      })
    try externalFixture.removeEntry(externallyDeletedEntry)
    externalModel.undo(
      habits: externalFixture.habits,
      context: externalFixture.refreshContext
    )
    #expect(externalModel.state.undo == nil)
    #expect(externalModel.state.feedback?.id == externalFeedback)
    #expect(externalFixture.deletedEntryIDs.isEmpty)

    externalModel.appendQuickAdd(
      amount: 1,
      habits: externalFixture.habits,
      context: externalFixture.refreshContext
    )
    let refreshUndo = try #require(externalModel.state.undo)
    let refreshFeedback = externalModel.state.feedback?.id
    let refreshDeletedEntry = try #require(
      externalFixture.currentEntries.first {
        $0.persistentModelID == refreshUndo.entryID
      })
    try externalFixture.removeEntry(refreshDeletedEntry)
    externalModel.refresh(
      habits: externalFixture.habits,
      goals: [],
      context: externalFixture.refreshContext
    )
    #expect(externalModel.state.undo == nil)
    #expect(externalModel.state.feedback?.id == refreshFeedback)

    let sleeper = ControlledSleeper()
    let expiryFixture = try LoggingFixture(target: 10, progress: 0)
    let expiryModel = expiryFixture.makeModel {
      try await sleeper.sleep($0)
    }
    expiryFixture.presentSheet(expiryModel)
    expiryModel.appendQuickAdd(
      amount: 1,
      habits: expiryFixture.habits,
      context: expiryFixture.refreshContext
    )
    await sleeper.waitForCount(1)
    let firstGeneration = try #require(expiryModel.state.undo?.generation)
    expiryModel.appendQuickAdd(
      amount: 1,
      habits: expiryFixture.habits,
      context: expiryFixture.refreshContext
    )
    await sleeper.waitForCount(2)
    let secondGeneration = try #require(expiryModel.state.undo?.generation)
    #expect(secondGeneration != firstGeneration)
    let durations = await sleeper.recordedDurations
    #expect(durations == [.seconds(5), .seconds(5)])

    await sleeper.resumeOldest()
    for _ in 0..<20 {
      await Task.yield()
    }
    #expect(expiryModel.state.undo?.generation == secondGeneration)

    let expiryFeedback = expiryModel.state.feedback?.id
    await sleeper.resumeOldest()
    for _ in 0..<20 where expiryModel.state.undo != nil {
      await Task.yield()
    }
    #expect(expiryModel.state.undo == nil)
    #expect(expiryFixture.deletedEntryIDs.isEmpty)
    #expect(expiryModel.state.feedback?.id == expiryFeedback)
  }

  @Test("direct count Undo expires without reverting committed progress")
  func directCountUndoExpiresWithoutMutation() async throws {
    let sleeper = ControlledSleeper()
    let fixture = try LoggingFixture(target: 2, progress: 0, unit: "times")
    let model = fixture.makeModel {
      try await sleeper.sleep($0)
    }
    fixture.todayModel.refresh(
      habits: fixture.habits,
      context: fixture.refreshContext
    )

    model.activateCurrent(
      habit: fixture.habit,
      habits: fixture.habits,
      context: fixture.refreshContext
    )

    await sleeper.waitForCount(1)
    #expect(await sleeper.recordedDurations == [.seconds(5)])
    #expect(fixture.progress == 1)
    #expect(fixture.currentEntries.count == 1)
    #expect(model.state.undo?.amount == 1)

    await sleeper.resumeOldest()
    for _ in 0..<100 where model.state.undo != nil {
      await Task.yield()
    }

    #expect(model.state.undo == nil)
    #expect(fixture.progress == 1)
    #expect(fixture.currentEntries.count == 1)
    #expect(fixture.deletedEntryIDs.isEmpty)
  }

  @Test("Undo uses the fresh context deadline before deleting")
  func expiredUndoIsNonmutatingWhenExpiryDeliveryIsDelayed() async throws {
    let sleeper = ControlledSleeper()
    let fixture = try LoggingFixture(target: 10, progress: 0)
    let model = fixture.makeModel {
      try await sleeper.sleep($0)
    }
    fixture.presentSheet(model)
    model.appendQuickAdd(
      amount: 1,
      habits: fixture.habits,
      context: fixture.refreshContext
    )
    await sleeper.waitForCount(1)
    let feedbackID = model.state.feedback?.id
    let lateContext = TodayRefreshContext(
      instant: fixture.refreshContext.instant.addingTimeInterval(6),
      timeZone: fixture.refreshContext.timeZone,
      calendar: fixture.refreshContext.calendar,
      locale: fixture.refreshContext.locale
    )

    model.undo(habits: fixture.habits, context: lateContext)

    #expect(model.state.undo == nil)
    #expect(model.state.feedback?.id == feedbackID)
    #expect(fixture.currentEntries.count == 1)
    #expect(fixture.deletedEntryIDs.isEmpty)
    await sleeper.resumeOldest()
  }

  @Test("model teardown cancels only pending Undo expiry work")
  func modelLifetimeCancelsOnlyExpiryWork() async throws {
    let sleeper = CancellationSleeper()
    let fixture = try LoggingFixture(target: 10, progress: 0)
    var model: TodayLoggingModel? = fixture.makeModel {
      try await sleeper.sleep($0)
    }
    fixture.presentSheet(try #require(model))
    model?.appendQuickAdd(
      amount: 1,
      habits: fixture.habits,
      context: fixture.refreshContext
    )
    await sleeper.waitUntilStarted()
    weak let releasedModel = model

    model = nil
    for _ in 0..<100 {
      if await sleeper.wasCancelled {
        break
      }
      await Task.yield()
    }

    #expect(releasedModel == nil)
    #expect(await sleeper.wasCancelled)
    #expect(fixture.progress == 1)
    #expect(fixture.currentEntries.count == 1)
  }

  @Test("feedback represents value transitions and ignores non-feedback operations")
  func feedbackUsesValueSemantics() throws {
    let unmetFixture = try LoggingFixture(target: 10, progress: 0)
    let unmetModel = unmetFixture.makeModel()
    unmetFixture.presentSheet(unmetModel)
    unmetModel.appendQuickAdd(
      amount: 1,
      habits: unmetFixture.habits,
      context: unmetFixture.refreshContext
    )
    #expect(unmetModel.state.feedback?.kind == .logged)

    let completionFixture = try LoggingFixture(target: 10, progress: 9)
    let completionModel = completionFixture.makeModel()
    completionFixture.presentSheet(completionModel)
    completionModel.appendQuickAdd(
      amount: 1,
      habits: completionFixture.habits,
      context: completionFixture.refreshContext
    )
    #expect(completionModel.state.feedback?.kind == .completion)

    let alreadyMetFixture = try LoggingFixture(target: 10, progress: 10)
    let alreadyMetModel = alreadyMetFixture.makeModel()
    alreadyMetFixture.presentSheet(alreadyMetModel)
    alreadyMetModel.appendQuickAdd(
      amount: 1,
      habits: alreadyMetFixture.habits,
      context: alreadyMetFixture.refreshContext
    )
    #expect(alreadyMetModel.state.feedback?.kind == .logged)
    let eventID = try #require(alreadyMetModel.state.feedback?.id)

    alreadyMetModel.beginSetTotalEditing()
    alreadyMetModel.updateAmountInput("11")
    alreadyMetModel.submitAmount(
      habits: alreadyMetFixture.habits,
      context: alreadyMetFixture.refreshContext
    )
    #expect(alreadyMetModel.state.feedback?.id == eventID)

    alreadyMetModel.refresh(
      habits: alreadyMetFixture.habits,
      goals: [],
      context: alreadyMetFixture.refreshContext
    )
    #expect(alreadyMetModel.state.feedback?.id == eventID)

    alreadyMetFixture.failAppend = true
    alreadyMetModel.appendQuickAdd(
      amount: 1,
      habits: alreadyMetFixture.habits,
      context: alreadyMetFixture.refreshContext
    )
    #expect(alreadyMetModel.state.feedback?.id == eventID)

    let entryID = try #require(alreadyMetModel.state.sheet?.entries.first?.id)
    alreadyMetFixture.failAppend = false
    alreadyMetModel.deleteEntry(
      entryID,
      habits: alreadyMetFixture.habits,
      context: alreadyMetFixture.refreshContext
    )
    #expect(alreadyMetModel.state.feedback?.id == eventID)

    alreadyMetModel.consumeFeedback(eventID)
    #expect(alreadyMetModel.state.feedback == nil)
  }

  @Test("stale activation and malformed identities preserve unrelated interactions")
  func independentInteractionStateRefreshesByHabitIdentity() throws {
    let context = try makeContext()
    let refreshContext = makeRefreshContext()
    let first = try insertHabit(in: context, name: "First", target: 10, unit: "steps")
    let second = try insertHabit(in: context, name: "Second", target: 10, unit: "steps")
    let habits = [first, second]
    var firstProgress = 0
    var secondProgress = 2
    var firstEntries: [HabitLoggingEntrySnapshot] = []
    var firstProjectionError: (any Error)?
    var secondProjectionError: (any Error)?
    let todayModel = TodayModel(
      operations: TodayOperations { habit, _ in
        todaySnapshot(
          progress: habit === first ? firstProgress : secondProgress,
          target: habit.target,
          unit: habit.unit
        )
      })
    todayModel.refresh(habits: habits, context: refreshContext)
    let operations = TodayLoggingOperations(
      snapshot: { habit, _ in
        if habit === first, let firstProjectionError {
          throw firstProjectionError
        }
        if habit === second, let secondProjectionError {
          throw secondProjectionError
        }
        return loggingSnapshot(
          habit: habit,
          progress: habit === first ? firstProgress : secondProgress,
          currentEntries: habit === first ? firstEntries : []
        )
      },
      append: { amount, habit, _, receivedContext in
        guard habit === first else { throw FixtureFailure.operation }
        let entry = try insertEntry(
          in: context,
          habit: habit,
          amount: amount,
          timestamp: receivedContext.instant
        )
        firstProgress += amount
        firstEntries.insert(
          HabitLoggingEntrySnapshot(
            id: entry.persistentModelID,
            uuid: entry.id,
            timestamp: entry.timestamp,
            amount: entry.amount,
            entry: entry
          ),
          at: 0
        )
        return entry
      },
      setTotal: { _, _, _, _ in nil },
      delete: { _, _, _ in }
    )
    let model = TodayLoggingModel(
      todayModel: todayModel,
      operations: operations,
      sleep: longSleep
    )

    model.activateCurrent(habit: first, habits: habits, context: refreshContext)
    model.appendQuickAdd(amount: 1, habits: habits, context: refreshContext)
    let firstUndo = try #require(model.state.undo?.generation)
    model.activateAtRisk(habit: first, habits: habits, context: refreshContext)
    #expect(model.state.undo?.generation == firstUndo)

    model.activateCurrent(habit: second, habits: habits, context: refreshContext)
    secondProgress = 7
    firstProjectionError = HabitLoggingComputationError.detachedHabit
    model.refresh(habits: habits, goals: [], context: refreshContext)
    #expect(model.state.undo == nil)
    #expect(model.state.feedback == nil)
    #expect(model.state.sheet?.habitID == second.persistentModelID)
    #expect(model.state.sheet?.progress == 7)

    secondProjectionError = BucketEvaluationError.invalidRequirement(0)
    model.refresh(habits: habits, goals: [], context: refreshContext)
    #expect(model.state.sheet == nil)
  }

  private actor ControlledSleeper {
    private var durations: [Duration] = []
    private var continuations: [CheckedContinuation<Void, any Error>] = []

    var recordedDurations: [Duration] {
      durations
    }

    func sleep(_ duration: Duration) async throws {
      durations.append(duration)
      try await withCheckedThrowingContinuation { continuation in
        continuations.append(continuation)
      }
    }

    func waitForCount(_ count: Int) async {
      while continuations.count < count {
        await Task.yield()
      }
    }

    func resumeOldest() {
      continuations.removeFirst().resume()
    }
  }

  private actor CancellationSleeper {
    private var started = false
    private(set) var wasCancelled = false

    func sleep(_ duration: Duration) async throws {
      started = true
      do {
        try await Task.sleep(for: duration + .seconds(60))
      } catch {
        wasCancelled = true
        throw error
      }
    }

    func waitUntilStarted() async {
      while !started {
        await Task.yield()
      }
    }
  }

  @MainActor
  private final class LoggingFixture {
    let context: ModelContext
    let habit: Habit
    let refreshContext: TodayRefreshContext
    var currentKey = "day:2026-08-05"
    var graceKey = "day:2026-08-04"
    var progress: Int
    var graceProgress: Int?
    var currentEntries: [LogEntry] = []
    var graceEntries: [LogEntry] = []
    var appendAmounts: [Int] = []
    var appendDestinations: [LogEntryDestination] = []
    var setTotals: [Int] = []
    var deletedEntryIDs: [PersistentIdentifier] = []
    var events: [String] = []
    var receivedContexts: [TodayRefreshContext] = []
    var failAppend = false
    var failSetTotal = false
    var failDelete = false
    var failNextPostMutationSnapshot = false
    var onTodayProjection: (() -> Void)?
    private var mutationAwaitingProjection = false

    var habits: [Habit] { [habit] }

    lazy var todayModel = TodayModel(
      operations: TodayOperations { [unowned self] habit, context in
        events.append("today")
        receivedContexts.append(context)
        onTodayProjection?()
        return TodayLoggingModelTests().todaySnapshot(
          progress: progress,
          target: habit.target,
          unit: habit.unit,
          cadence: HabitCadence(rawValue: habit.cadenceRawValue)!,
          currentStreak: 4,
          isAtRisk: graceProgress.map { $0 < habit.target } ?? false
        )
      })

    lazy var operations = TodayLoggingOperations(
      snapshot: { [unowned self] _, context in
        events.append("snapshot")
        receivedContexts.append(context)
        if mutationAwaitingProjection, failNextPostMutationSnapshot {
          failNextPostMutationSnapshot = false
          mutationAwaitingProjection = false
          throw FixtureFailure.projection
        }
        mutationAwaitingProjection = false
        return snapshot()
      },
      append: { [unowned self] amount, _, destination, context in
        events.append("append")
        receivedContexts.append(context)
        if failAppend {
          throw FixtureFailure.operation
        }
        appendAmounts.append(amount)
        appendDestinations.append(destination)
        mutationAwaitingProjection = true
        return try addEntry(amount: amount, destination: destination)
      },
      setTotal: { [unowned self] total, _, destination, context in
        events.append("setTotal")
        receivedContexts.append(context)
        if failSetTotal {
          throw FixtureFailure.operation
        }
        setTotals.append(total)
        let selectedProgress: Int
        switch destination {
        case .current:
          selectedProgress = progress
        case .periodKey(let key) where key == currentKey:
          selectedProgress = progress
        case .periodKey:
          selectedProgress = graceProgress ?? 0
        }
        guard total != selectedProgress else {
          return nil
        }
        let amount = total - selectedProgress
        mutationAwaitingProjection = true
        return try addEntry(amount: amount, destination: destination)
      },
      delete: { [unowned self] entry, _, context in
        events.append("delete")
        receivedContexts.append(context)
        if failDelete {
          throw FixtureFailure.operation
        }
        deletedEntryIDs.append(entry.persistentModelID)
        try removeEntry(entry)
        mutationAwaitingProjection = true
      }
    )

    init(
      target: Int,
      progress: Int,
      graceProgress: Int? = nil,
      unit: String = "steps",
      cadence: HabitCadence = .daily
    ) throws {
      context = ModelContext(try TendModelContainer.inMemory())
      habit = Habit(
        name: "Fixture",
        cadence: cadence,
        target: target,
        unit: unit,
        createdAt: Date(timeIntervalSince1970: 100)
      )
      context.insert(habit)
      try context.save()
      self.progress = progress
      self.graceProgress = graceProgress
      refreshContext = TodayLoggingModelTests().makeRefreshContext()
    }

    func makeModel(
      sleep: @escaping TodayLoggingModel.Sleep = { duration in
        try await Task.sleep(for: duration + .seconds(60))
      },
      reminderRefresh: @escaping ReminderRefreshSignal = {}
    ) -> TodayLoggingModel {
      TodayLoggingModel(
        todayModel: todayModel,
        operations: operations,
        sleep: sleep,
        reminderRefresh: reminderRefresh
      )
    }

    func presentSheet(_ model: TodayLoggingModel, atRisk: Bool = false) {
      todayModel.refresh(habits: habits, context: refreshContext)
      if atRisk {
        model.activateAtRisk(habit: habit, habits: habits, context: refreshContext)
      } else {
        model.activateCurrent(habit: habit, habits: habits, context: refreshContext)
      }
    }

    func snapshot() -> HabitLoggingSnapshot {
      TodayLoggingModelTests().loggingSnapshot(
        habit: habit,
        progress: progress,
        graceProgress: graceProgress,
        currentKey: currentKey,
        graceKey: graceKey,
        currentEntries: currentEntries.map(entrySnapshot),
        graceEntries: graceEntries.map(entrySnapshot)
      )
    }

    @discardableResult
    func addEntry(
      amount: Int,
      destination: LogEntryDestination = .current,
      timestamp: Date? = nil,
      id: UUID = UUID()
    ) throws -> LogEntry {
      let entry = LogEntry(
        id: id,
        timestamp: timestamp ?? refreshContext.instant,
        amount: amount,
        habit: habit
      )
      context.insert(entry)
      try context.save()
      switch destination {
      case .current:
        progress += amount
        currentEntries.insert(entry, at: 0)
      case .periodKey(let key) where key == currentKey:
        progress += amount
        currentEntries.insert(entry, at: 0)
      case .periodKey(let key) where key == graceKey:
        graceProgress = (graceProgress ?? 0) + amount
        graceEntries.insert(entry, at: 0)
      case .periodKey:
        throw FixtureFailure.operation
      }
      return entry
    }

    func removeEntry(_ entry: LogEntry) throws {
      if let index = currentEntries.firstIndex(where: {
        $0.persistentModelID == entry.persistentModelID
      }) {
        progress -= currentEntries[index].amount
        currentEntries.remove(at: index)
        return
      }
      if let index = graceEntries.firstIndex(where: {
        $0.persistentModelID == entry.persistentModelID
      }) {
        graceProgress = (graceProgress ?? 0) - graceEntries[index].amount
        graceEntries.remove(at: index)
        return
      }
      throw FixtureFailure.operation
    }

    private func entrySnapshot(_ entry: LogEntry) -> HabitLoggingEntrySnapshot {
      HabitLoggingEntrySnapshot(
        id: entry.persistentModelID,
        uuid: entry.id,
        timestamp: entry.timestamp,
        amount: entry.amount,
        entry: entry
      )
    }
  }

  private enum FixtureFailure: Error, LocalizedError {
    case operation
    case projection

    var errorDescription: String? {
      switch self {
      case .operation:
        "Fixture operation failed."
      case .projection:
        "Fixture projection failed."
      }
    }
  }
  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func insertHabit(
    in context: ModelContext,
    name: String,
    cadence: HabitCadence = .daily,
    target: Int,
    unit: String
  ) throws -> Habit {
    let habit = Habit(
      name: name,
      cadence: cadence,
      target: target,
      unit: unit,
      createdAt: Date(timeIntervalSince1970: 100)
    )
    context.insert(habit)
    try context.save()
    return habit
  }

  private func insertEntry(
    in context: ModelContext,
    habit: Habit,
    amount: Int,
    timestamp: Date
  ) throws -> LogEntry {
    let entry = LogEntry(
      timestamp: timestamp,
      amount: amount,
      habit: habit
    )
    context.insert(entry)
    try context.save()
    return entry
  }

  private func makeRefreshContext() -> TodayRefreshContext {
    let timeZone = TimeZone(identifier: "UTC")!
    let locale = Locale(identifier: "en_US")
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    calendar.timeZone = timeZone
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return TodayRefreshContext(
      instant: Date(timeIntervalSince1970: 1_754_352_000),
      timeZone: timeZone,
      calendar: calendar,
      locale: locale
    )
  }

  private func loggingSnapshot(
    habit: Habit,
    progress: Int,
    graceProgress: Int? = nil,
    currentKey: String = "day:2026-08-05",
    graceKey: String = "day:2026-08-04",
    currentEntries: [HabitLoggingEntrySnapshot] = [],
    graceEntries: [HabitLoggingEntrySnapshot] = []
  ) -> HabitLoggingSnapshot {
    let current = HabitLoggingBucketSnapshot(
      periodKey: currentKey,
      phase: .open,
      progress: progress,
      target: habit.target,
      unit: habit.unit,
      isMet: progress >= habit.target,
      entries: currentEntries
    )
    let grace = graceProgress.map {
      HabitLoggingBucketSnapshot(
        periodKey: graceKey,
        phase: .grace,
        progress: $0,
        target: habit.target,
        unit: habit.unit,
        isMet: $0 >= habit.target,
        entries: graceEntries
      )
    }
    return HabitLoggingSnapshot(
      habitID: habit.persistentModelID,
      name: habit.name,
      cadence: HabitCadence(rawValue: habit.cadenceRawValue)!,
      target: habit.target,
      unit: habit.unit,
      current: current,
      grace: grace
    )
  }

  private func todaySnapshot(
    progress: Int,
    target: Int,
    unit: String,
    cadence: HabitCadence = .daily,
    currentStreak: Int = 0,
    isAtRisk: Bool = false,
    isMet: Bool? = nil
  ) -> HabitTodaySnapshot {
    HabitTodaySnapshot(
      periodKey: cadence == .daily ? "day:2026-08-05" : "week:2026-08-03",
      progress: progress,
      target: target,
      unit: unit,
      cadence: cadence,
      currentStreak: currentStreak,
      isAtRisk: isAtRisk,
      isMet: isMet ?? (progress >= target)
    )
  }

  private func longSleep(_ duration: Duration) async throws {
    try await Task.sleep(for: duration + .seconds(60))
  }
}
