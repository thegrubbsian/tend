import Foundation
import Observation
import SwiftData
import TendCore

@MainActor
struct TodayLoggingOperations {
  typealias Snapshot = (Habit, TodayRefreshContext) throws -> HabitLoggingSnapshot
  typealias Append = (
    Int,
    Habit,
    LogEntryDestination,
    TodayRefreshContext
  ) throws -> LogEntry
  typealias SetTotal = (
    Int,
    Habit,
    LogEntryDestination,
    TodayRefreshContext
  ) throws -> LogEntry?
  typealias Delete = (LogEntry, Habit, TodayRefreshContext) throws -> Void

  let snapshot: Snapshot
  let append: Append
  let setTotal: SetTotal
  let delete: Delete

  init(
    snapshot: @escaping Snapshot,
    append: @escaping Append,
    setTotal: @escaping SetTotal,
    delete: @escaping Delete
  ) {
    self.snapshot = snapshot
    self.append = append
    self.setTotal = setTotal
    self.delete = delete
  }

  static func live(context: ModelContext) -> Self {
    let computation = HabitLoggingComputation(context: context)
    let entries = LogEntryOperations(context: context)
    return Self(
      snapshot: { habit, refreshContext in
        try computation.snapshot(
          for: habit,
          at: refreshContext.instant,
          timeZone: refreshContext.timeZone
        )
      },
      append: { amount, habit, destination, refreshContext in
        try entries.append(
          amount: amount,
          to: habit,
          destination: destination,
          at: refreshContext.instant,
          timeZone: refreshContext.timeZone
        )
      },
      setTotal: { total, habit, destination, refreshContext in
        try entries.setTotal(
          total,
          for: habit,
          destination: destination,
          at: refreshContext.instant,
          timeZone: refreshContext.timeZone
        )
      },
      delete: { entry, habit, refreshContext in
        try entries.delete(
          entry,
          from: habit,
          at: refreshContext.instant,
          timeZone: refreshContext.timeZone
        )
      }
    )
  }
}

struct QuickAddAmounts: Equatable {
  let presets: [Int]
  let finish: Int?

  init(presets: [Int], finish: Int?) {
    self.presets = presets
    self.finish = finish
  }

  init(target: Int, progress: Int) {
    guard target > 0 else {
      self.init(presets: [], finish: nil)
      return
    }

    let candidates = [target / 6, target / 3]
      .map { Self.friendlyFloor(max($0, 1)) }
    let remaining = target.subtractingReportingOverflow(progress)
    let finish =
      !remaining.overflow && remaining.partialValue > 0
      ? remaining.partialValue
      : nil
    self.init(
      presets: Array(Set(candidates)).filter { $0 != finish }.sorted(),
      finish: finish
    )
  }

  private static func friendlyFloor(_ value: Int) -> Int {
    precondition(value > 0)
    var scale = 1
    while scale <= value / 10 {
      scale *= 10
    }
    let leading = value / scale
    if leading >= 5 {
      return scale * 5
    }
    if leading >= 2 {
      return scale * 2
    }
    return scale
  }
}

struct LogSheetScope: Identifiable, Equatable {
  var id: String { periodKey }

  let periodKey: String
  let label: String
  let entryListLabel: String
  let isGrace: Bool
  let showsUnfinishedMarker: Bool
}

struct LogSheetEntryPresentation: Identifiable, Equatable {
  let id: PersistentIdentifier
  let uuid: UUID
  let timestamp: Date
  let amount: Int
  let timestampText: String
  let amountText: String
  let accessibilityLabel: String
}

enum LogAmountEditorMode: Equatable {
  case customAmount
  case setTotal
}

struct LogSheetPresentation: Equatable {
  let habitID: PersistentIdentifier
  let habitName: String
  let cadence: HabitCadence
  let scopes: [LogSheetScope]
  let selectedPeriodKey: String
  let progress: Int
  let target: Int
  let unit: String
  let isMet: Bool
  let currentStreak: Int
  let progressFraction: Double
  let quickAddAmounts: QuickAddAmounts
  let entries: [LogSheetEntryPresentation]
  let amountEditorMode: LogAmountEditorMode?
  let amountInput: String
  let amountError: String?
  let sheetError: String?
}

struct TodayLogUndo {
  let habitID: PersistentIdentifier
  let entryID: PersistentIdentifier
  let amount: Int
  let unit: String
  let originPeriodKey: String
  let generation: UUID
  let expiresAt: Date
  let error: String?
}

struct TodayLoggingInlineFailure: Equatable {
  let habitID: PersistentIdentifier
  let message: String
}

struct TodayLoggingFeedback: Identifiable, Equatable {
  enum Kind: Equatable {
    case logged
    case completion
    case undo
  }

  let id: UUID
  let kind: Kind
  let habitID: PersistentIdentifier
}

struct TodayLoggingState {
  var sheet: LogSheetPresentation?
  var undo: TodayLogUndo?
  var feedback: TodayLoggingFeedback?
  var actionFailure: TodayLoggingInlineFailure?
  var announcementToken: UUID?

  init(
    sheet: LogSheetPresentation? = nil,
    undo: TodayLogUndo? = nil,
    feedback: TodayLoggingFeedback? = nil,
    actionFailure: TodayLoggingInlineFailure? = nil,
    announcementToken: UUID? = nil
  ) {
    self.sheet = sheet
    self.undo = undo
    self.feedback = feedback
    self.actionFailure = actionFailure
    self.announcementToken = announcementToken
  }
}

@MainActor
@Observable
final class TodayLoggingModel {
  typealias Sleep = @Sendable (Duration) async throws -> Void

  private(set) var state = TodayLoggingState()

  @ObservationIgnored private let todayModel: TodayModel
  @ObservationIgnored private let operations: TodayLoggingOperations
  @ObservationIgnored private let sleep: Sleep
  @ObservationIgnored private var expiryTask: Task<Void, Never>?

  init(
    todayModel: TodayModel,
    operations: TodayLoggingOperations,
    sleep: @escaping Sleep = { duration in
      try await Task.sleep(for: duration)
    }
  ) {
    self.todayModel = todayModel
    self.operations = operations
    self.sleep = sleep
  }

  convenience init(
    context: ModelContext,
    todayModel: TodayModel,
    sleep: @escaping Sleep = { duration in
      try await Task.sleep(for: duration)
    }
  ) {
    self.init(
      todayModel: todayModel,
      operations: .live(context: context),
      sleep: sleep
    )
  }

  deinit {
    expiryTask?.cancel()
  }

  func activateCurrent(
    habit: Habit,
    habits: [Habit],
    context: TodayRefreshContext
  ) {
    activate(
      habit: habit,
      habits: habits,
      selection: .current,
      context: context
    )
  }

  func activateAtRisk(
    habit: Habit,
    habits: [Habit],
    context: TodayRefreshContext
  ) {
    activate(
      habit: habit,
      habits: habits,
      selection: .grace,
      context: context
    )
  }

  func beginCustomAmountEditing() {
    beginAmountEditing(.customAmount)
  }

  func beginSetTotalEditing() {
    beginAmountEditing(.setTotal)
  }

  func updateAmountInput(_ input: String) {
    guard let sheet = state.sheet, sheet.amountEditorMode != nil else { return }
    var replacement = state
    replacement.sheet = replacing(
      sheet,
      amountEditorMode: sheet.amountEditorMode,
      amountInput: input,
      amountError: nil,
      sheetError: nil
    )
    state = replacement
  }

  func submitAmount(
    habits: [Habit],
    context: TodayRefreshContext
  ) {
    guard let sheet = state.sheet, let mode = sheet.amountEditorMode else { return }
    switch mode {
    case .customAmount:
      guard let amount = decimalInteger(sheet.amountInput), amount > 0 else {
        publishAmountError("Enter a positive whole number.")
        return
      }
      performAppend(amount: amount, habits: habits, context: context)
    case .setTotal:
      guard let total = decimalInteger(sheet.amountInput) else {
        publishAmountError("Enter zero or a positive whole number.")
        return
      }
      guard total >= sheet.progress else {
        publishAmountError("Delete an entry before lowering the total.")
        return
      }
      performSetTotal(total, habits: habits, context: context)
    }
  }

  func appendQuickAdd(
    amount: Int,
    habits: [Habit],
    context: TodayRefreshContext
  ) {
    guard let sheet = state.sheet,
      sheet.quickAddAmounts.presets.contains(amount) || sheet.quickAddAmounts.finish == amount
    else {
      return
    }
    performAppend(amount: amount, habits: habits, context: context)
  }

  func selectPeriod(
    _ periodKey: String,
    habits: [Habit],
    context: TodayRefreshContext
  ) {
    guard let openSheet = state.sheet,
      let habit = liveHabit(matching: openSheet.habitID, in: habits)
    else {
      if let habitID = state.sheet?.habitID {
        clearIneligibleState(for: habitID)
      }
      return
    }

    do {
      let snapshot = try operations.snapshot(habit, context)
      guard bucket(in: snapshot, periodKey: periodKey) != nil else {
        publishStaleSelection(snapshot: snapshot, context: context)
        return
      }
      var replacement = state
      replacement.sheet = presentation(
        snapshot: snapshot,
        selectedPeriodKey: periodKey,
        context: context,
        prior: nil
      )
      replacement.announcementToken = UUID()
      replacement.actionFailure = nil
      state = replacement
    } catch {
      publishSheetFailure(error)
    }
  }

  func cancelAmountEditing() {
    guard let sheet = state.sheet else { return }
    var replacement = state
    replacement.sheet = replacing(
      sheet,
      amountEditorMode: nil,
      amountInput: "",
      amountError: nil,
      sheetError: nil
    )
    state = replacement
  }

  func dismissSheet() {
    guard state.sheet != nil else { return }
    var replacement = state
    replacement.sheet = nil
    state = replacement
  }

  func consumeFeedback(_ id: UUID) {
    guard state.feedback?.id == id else { return }
    var replacement = state
    replacement.feedback = nil
    state = replacement
  }

  func refresh(
    habits: [Habit],
    context: TodayRefreshContext
  ) {
    todayModel.refresh(habits: habits, context: context)
    var replacement = state
    var changedWithoutSheet = false

    if let undo = replacement.undo {
      if let undoHabit = liveHabit(matching: undo.habitID, in: habits) {
        if replacement.sheet?.habitID != undo.habitID {
          do {
            let undoSnapshot = try operations.snapshot(undoHabit, context)
            if !containsEntry(undo.entryID, in: undoSnapshot) {
              replacement.undo = nil
              expiryTask?.cancel()
              changedWithoutSheet = true
            }
          } catch {
            if invalidatesInteractionState(error) {
              clearIneligibleState(for: undo.habitID, in: &replacement)
            } else {
              replacement.undo = replacing(undo, error: message(for: error))
            }
            changedWithoutSheet = true
          }
        }
      } else {
        clearIneligibleState(for: undo.habitID, in: &replacement)
        changedWithoutSheet = true
      }
    }

    guard let openSheet = replacement.sheet else {
      if changedWithoutSheet {
        state = replacement
      }
      return
    }
    guard let habit = liveHabit(matching: openSheet.habitID, in: habits) else {
      clearIneligibleState(for: openSheet.habitID, in: &replacement)
      state = replacement
      return
    }

    do {
      let snapshot = try operations.snapshot(habit, context)
      let selected = bucket(in: snapshot, periodKey: openSheet.selectedPeriodKey)
      replacement.sheet = presentation(
        snapshot: snapshot,
        selectedPeriodKey: selected?.periodKey ?? snapshot.current.periodKey,
        context: context,
        prior: selected == nil ? nil : openSheet
      )
      if let refreshedSheet = replacement.sheet {
        replacement.sheet = replacing(
          refreshedSheet,
          amountEditorMode: refreshedSheet.amountEditorMode,
          amountInput: refreshedSheet.amountInput,
          amountError: refreshedSheet.amountError,
          sheetError: nil
        )
      }
      if let undo = replacement.undo,
        undo.habitID == snapshot.habitID,
        !containsEntry(undo.entryID, in: snapshot)
      {
        replacement.undo = nil
        expiryTask?.cancel()
      }
      if selected == nil {
        replacement.announcementToken = UUID()
      }
      replacement.actionFailure = nil
      state = replacement
    } catch {
      if invalidatesInteractionState(error) {
        clearIneligibleState(for: openSheet.habitID, in: &replacement)
      } else {
        replacement.sheet = replacing(
          openSheet,
          amountEditorMode: openSheet.amountEditorMode,
          amountInput: openSheet.amountInput,
          amountError: nil,
          sheetError: message(for: error)
        )
      }
      state = replacement
    }
  }

  func deleteEntry(
    _ entryID: PersistentIdentifier,
    habits: [Habit],
    context: TodayRefreshContext
  ) {
    guard let openSheet = state.sheet,
      let habit = liveHabit(matching: openSheet.habitID, in: habits)
    else {
      if let habitID = state.sheet?.habitID {
        clearIneligibleState(for: habitID)
      }
      return
    }

    do {
      let before = try operations.snapshot(habit, context)
      guard let selectedBefore = bucket(in: before, periodKey: openSheet.selectedPeriodKey) else {
        publishStaleSelection(snapshot: before, context: context)
        return
      }
      guard let entry = selectedBefore.entries.first(where: { $0.id == entryID })?.entry else {
        publishSheetMessage("That entry is no longer available.")
        return
      }
      try operations.delete(entry, habit, context)
      let after = try operations.snapshot(habit, context)
      todayModel.refresh(habits: habits, context: context)
      let selectedAfter = bucket(in: after, periodKey: selectedBefore.periodKey) ?? after.current
      var replacement = state
      replacement.sheet = presentation(
        snapshot: after,
        selectedPeriodKey: selectedAfter.periodKey,
        context: context,
        prior: nil
      )
      if selectedAfter.periodKey != selectedBefore.periodKey {
        replacement.announcementToken = UUID()
      }
      if replacement.undo?.entryID == entryID {
        replacement.undo = nil
        expiryTask?.cancel()
      }
      replacement.actionFailure = nil
      state = replacement
    } catch {
      publishSheetFailure(error)
    }
  }

  func undo(
    habits: [Habit],
    context: TodayRefreshContext
  ) {
    guard let pending = state.undo else { return }
    guard context.instant < pending.expiresAt else {
      clearUndo(matching: pending.entryID)
      return
    }
    guard let habit = liveHabit(matching: pending.habitID, in: habits) else {
      clearIneligibleState(for: pending.habitID)
      return
    }

    do {
      let before = try operations.snapshot(habit, context)
      guard let origin = bucket(in: before, periodKey: pending.originPeriodKey) else {
        publishUndoFailure("That log can no longer be undone.")
        return
      }
      guard let entry = origin.entries.first(where: { $0.id == pending.entryID })?.entry else {
        clearUndo(matching: pending.entryID)
        return
      }
      try operations.delete(entry, habit, context)
      let after = try operations.snapshot(habit, context)
      todayModel.refresh(habits: habits, context: context)
      var replacement = state
      if let openSheet = replacement.sheet, openSheet.habitID == habit.persistentModelID {
        let selected = bucket(in: after, periodKey: openSheet.selectedPeriodKey)
        replacement.sheet = presentation(
          snapshot: after,
          selectedPeriodKey: selected?.periodKey ?? after.current.periodKey,
          context: context,
          prior: nil
        )
        if selected == nil {
          replacement.announcementToken = UUID()
        }
      }
      replacement.undo = nil
      replacement.feedback = TodayLoggingFeedback(
        id: UUID(),
        kind: .undo,
        habitID: habit.persistentModelID
      )
      replacement.actionFailure = nil
      expiryTask?.cancel()
      state = replacement
    } catch {
      if invalidatesInteractionState(error) {
        clearIneligibleState(for: pending.habitID)
      } else {
        publishUndoFailure(message(for: error))
      }
    }
  }

  private func beginAmountEditing(_ mode: LogAmountEditorMode) {
    guard let sheet = state.sheet else { return }
    var replacement = state
    replacement.sheet = replacing(
      sheet,
      amountEditorMode: mode,
      amountInput: "",
      amountError: nil,
      sheetError: nil
    )
    state = replacement
  }

  private func performAppend(
    amount: Int,
    habits: [Habit],
    context: TodayRefreshContext
  ) {
    performEntryMutation(habits: habits, context: context) {
      try operations.append($0, $1, $2, $3)
    } value: {
      amount
    }
  }

  private func performSetTotal(
    _ total: Int,
    habits: [Habit],
    context: TodayRefreshContext
  ) {
    performEntryMutation(habits: habits, context: context) {
      try operations.setTotal(total, $1, $2, $3)
    } value: {
      total
    }
  }

  private func performEntryMutation(
    habits: [Habit],
    context: TodayRefreshContext,
    mutate: (
      Int,
      Habit,
      LogEntryDestination,
      TodayRefreshContext
    ) throws -> LogEntry?,
    value: () -> Int
  ) {
    guard let openSheet = state.sheet,
      let habit = liveHabit(matching: openSheet.habitID, in: habits)
    else {
      if let habitID = state.sheet?.habitID {
        clearIneligibleState(for: habitID)
      }
      return
    }

    do {
      let before = try operations.snapshot(habit, context)
      guard let selectedBefore = bucket(in: before, periodKey: openSheet.selectedPeriodKey) else {
        publishStaleSelection(snapshot: before, context: context)
        return
      }
      let destination = LogEntryDestination.periodKey(selectedBefore.periodKey)
      guard let entry = try mutate(value(), habit, destination, context) else {
        var replacement = state
        replacement.sheet = replacing(
          openSheet,
          amountEditorMode: nil,
          amountInput: "",
          amountError: nil,
          sheetError: nil
        )
        state = replacement
        return
      }
      let after = try operations.snapshot(habit, context)
      todayModel.refresh(habits: habits, context: context)
      let selectedAfter = bucket(in: after, periodKey: selectedBefore.periodKey) ?? after.current
      let undo = makeUndo(
        entry: entry,
        habitID: habit.persistentModelID,
        amount: entry.amount,
        unit: after.unit,
        periodKey: selectedBefore.periodKey,
        context: context
      )
      var replacement = state
      replacement.sheet = presentation(
        snapshot: after,
        selectedPeriodKey: selectedAfter.periodKey,
        context: context,
        prior: nil
      )
      replacement.undo = undo
      replacement.feedback = TodayLoggingFeedback(
        id: UUID(),
        kind: !selectedBefore.isMet && selectedAfter.isMet ? .completion : .logged,
        habitID: habit.persistentModelID
      )
      replacement.actionFailure = nil
      state = replacement
      scheduleExpiry(for: undo.generation)
    } catch {
      publishSheetFailure(error)
    }
  }

  private func decimalInteger(_ input: String) -> Int? {
    guard !input.isEmpty,
      input.unicodeScalars.allSatisfy({ (48...57).contains($0.value) })
    else {
      return nil
    }
    return Int(input)
  }

  private func publishAmountError(_ message: String) {
    guard let sheet = state.sheet else { return }
    var replacement = state
    replacement.sheet = replacing(
      sheet,
      amountEditorMode: sheet.amountEditorMode,
      amountInput: sheet.amountInput,
      amountError: message,
      sheetError: nil
    )
    state = replacement
  }

  private func publishSheetFailure(_ error: Error) {
    if invalidatesInteractionState(error) {
      if let habitID = state.sheet?.habitID {
        clearIneligibleState(for: habitID)
      }
      return
    }
    guard let sheet = state.sheet else { return }
    var replacement = state
    replacement.sheet = replacing(
      sheet,
      amountEditorMode: sheet.amountEditorMode,
      amountInput: sheet.amountInput,
      amountError: nil,
      sheetError: message(for: error)
    )
    state = replacement
  }

  private func publishSheetMessage(_ message: String) {
    guard let sheet = state.sheet else { return }
    var replacement = state
    replacement.sheet = replacing(
      sheet,
      amountEditorMode: sheet.amountEditorMode,
      amountInput: sheet.amountInput,
      amountError: nil,
      sheetError: message
    )
    state = replacement
  }

  private func publishUndoFailure(_ message: String) {
    guard let undo = state.undo else { return }
    var replacement = state
    replacement.undo = replacing(undo, error: message)
    state = replacement
  }

  private func replacing(_ undo: TodayLogUndo, error: String?) -> TodayLogUndo {
    TodayLogUndo(
      habitID: undo.habitID,
      entryID: undo.entryID,
      amount: undo.amount,
      unit: undo.unit,
      originPeriodKey: undo.originPeriodKey,
      generation: undo.generation,
      expiresAt: undo.expiresAt,
      error: error
    )
  }

  private func publishStaleSelection(
    snapshot: HabitLoggingSnapshot,
    context: TodayRefreshContext
  ) {
    var replacement = state
    replacement.sheet = presentation(
      snapshot: snapshot,
      selectedPeriodKey: snapshot.current.periodKey,
      context: context,
      prior: nil
    )
    replacement.sheet = replacement.sheet.map {
      replacing(
        $0,
        amountEditorMode: nil,
        amountInput: "",
        amountError: nil,
        sheetError: "Logging period changed. Review the current period and try again."
      )
    }
    replacement.announcementToken = UUID()
    state = replacement
  }

  private func replacing(
    _ sheet: LogSheetPresentation,
    amountEditorMode: LogAmountEditorMode?,
    amountInput: String,
    amountError: String?,
    sheetError: String?
  ) -> LogSheetPresentation {
    LogSheetPresentation(
      habitID: sheet.habitID,
      habitName: sheet.habitName,
      cadence: sheet.cadence,
      scopes: sheet.scopes,
      selectedPeriodKey: sheet.selectedPeriodKey,
      progress: sheet.progress,
      target: sheet.target,
      unit: sheet.unit,
      isMet: sheet.isMet,
      currentStreak: sheet.currentStreak,
      progressFraction: sheet.progressFraction,
      quickAddAmounts: sheet.quickAddAmounts,
      entries: sheet.entries,
      amountEditorMode: amountEditorMode,
      amountInput: amountInput,
      amountError: amountError,
      sheetError: sheetError
    )
  }
  private func activate(
    habit: Habit,
    habits: [Habit],
    selection: ActivationSelection,
    context: TodayRefreshContext
  ) {
    guard let liveHabit = liveHabit(matching: habit.persistentModelID, in: habits) else {
      clearIneligibleState(for: habit.persistentModelID)
      return
    }

    do {
      let before = try operations.snapshot(liveHabit, context)
      guard let selectedBefore = bucket(in: before, selection: selection) else {
        return
      }
      if before.unit == "times" {
        try appendOne(
          to: liveHabit,
          habits: habits,
          destination: destination(for: selection, bucket: selectedBefore),
          before: selectedBefore,
          context: context
        )
      } else {
        var replacement = state
        replacement.sheet = presentation(
          snapshot: before,
          selectedPeriodKey: selectedBefore.periodKey,
          context: context,
          prior: nil
        )
        replacement.actionFailure = nil
        state = replacement
      }
    } catch {
      publishActionFailure(error, habitID: liveHabit.persistentModelID)
    }
  }

  private func appendOne(
    to habit: Habit,
    habits: [Habit],
    destination: LogEntryDestination,
    before: HabitLoggingBucketSnapshot,
    context: TodayRefreshContext
  ) throws {
    let entry = try operations.append(1, habit, destination, context)
    let after = try operations.snapshot(habit, context)
    todayModel.refresh(habits: habits, context: context)
    let selectedAfter = bucket(in: after, periodKey: before.periodKey) ?? after.current
    let undo = makeUndo(
      entry: entry,
      habitID: habit.persistentModelID,
      amount: 1,
      unit: after.unit,
      periodKey: before.periodKey,
      context: context
    )
    var replacement = state
    replacement.sheet = nil
    replacement.undo = undo
    replacement.feedback = TodayLoggingFeedback(
      id: UUID(),
      kind: !before.isMet && selectedAfter.isMet ? .completion : .logged,
      habitID: habit.persistentModelID
    )
    replacement.actionFailure = nil
    state = replacement
    scheduleExpiry(for: undo.generation)
  }

  private func presentation(
    snapshot: HabitLoggingSnapshot,
    selectedPeriodKey: String,
    context: TodayRefreshContext,
    prior: LogSheetPresentation?
  ) -> LogSheetPresentation {
    let buckets = [snapshot.current] + [snapshot.grace].compactMap { $0 }
    let selected = bucket(in: snapshot, periodKey: selectedPeriodKey) ?? snapshot.current
    let scopes = buckets.map { bucket in
      LogSheetScope(
        periodKey: bucket.periodKey,
        label: scopeLabel(cadence: snapshot.cadence, isGrace: bucket.phase == .grace),
        entryListLabel: entryListLabel(
          cadence: snapshot.cadence,
          isGrace: bucket.phase == .grace
        ),
        isGrace: bucket.phase == .grace,
        showsUnfinishedMarker: bucket.phase == .grace && !bucket.isMet
      )
    }
    let fraction = Double(selected.progress) / Double(selected.target)
    return LogSheetPresentation(
      habitID: snapshot.habitID,
      habitName: snapshot.name,
      cadence: snapshot.cadence,
      scopes: scopes,
      selectedPeriodKey: selected.periodKey,
      progress: selected.progress,
      target: selected.target,
      unit: selected.unit,
      isMet: selected.isMet,
      currentStreak: currentStreak(for: snapshot.habitID),
      progressFraction: min(max(fraction, 0), 1),
      quickAddAmounts: QuickAddAmounts(target: selected.target, progress: selected.progress),
      entries: selected.entries.map {
        entryPresentation($0, cadence: snapshot.cadence, unit: selected.unit, context: context)
      },
      amountEditorMode: prior?.amountEditorMode,
      amountInput: prior?.amountInput ?? "",
      amountError: prior?.amountError,
      sheetError: prior?.sheetError
    )
  }

  private func entryPresentation(
    _ entry: HabitLoggingEntrySnapshot,
    cadence: HabitCadence,
    unit: String,
    context: TodayRefreshContext
  ) -> LogSheetEntryPresentation {
    let formatter = HabitPresentationFormatter(
      calendar: context.calendar,
      locale: context.locale,
      timeZone: context.timeZone
    )
    let timestampText: String
    switch cadence {
    case .daily:
      timestampText = formatter.time(entry.timestamp)
    case .weekly:
      let weekday = entry.timestamp.formatted(
        Date.FormatStyle(
          locale: context.locale,
          calendar: context.calendar,
          timeZone: context.timeZone
        ).weekday(.abbreviated)
      )
      timestampText = "\(weekday) \(formatter.time(entry.timestamp))"
    }
    let amountText = formatter.amount(entry.amount, unit: unit)
    return LogSheetEntryPresentation(
      id: entry.id,
      uuid: entry.uuid,
      timestamp: entry.timestamp,
      amount: entry.amount,
      timestampText: timestampText,
      amountText: amountText,
      accessibilityLabel: "\(timestampText), \(amountText)"
    )
  }

  private func makeUndo(
    entry: LogEntry,
    habitID: PersistentIdentifier,
    amount: Int,
    unit: String,
    periodKey: String,
    context: TodayRefreshContext
  ) -> TodayLogUndo {
    TodayLogUndo(
      habitID: habitID,
      entryID: entry.persistentModelID,
      amount: amount,
      unit: unit,
      originPeriodKey: periodKey,
      generation: UUID(),
      expiresAt: context.instant.addingTimeInterval(5),
      error: nil
    )
  }

  private func scheduleExpiry(for generation: UUID) {
    expiryTask?.cancel()
    expiryTask = Task { [weak self, sleep] in
      do {
        try await sleep(.seconds(5))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      self?.expireUndo(generation: generation)
    }
  }

  private func expireUndo(generation: UUID) {
    guard state.undo?.generation == generation else { return }
    var replacement = state
    replacement.undo = nil
    state = replacement
  }

  private func invalidatesInteractionState(_ error: Error) -> Bool {
    error is HabitLoggingComputationError
      || error is BucketEvaluationError
      || error is BucketReconciliationError
      || error is CalendarBucketScheduleError
  }

  private func publishActionFailure(_ error: Error, habitID: PersistentIdentifier) {
    if invalidatesInteractionState(error) {
      clearIneligibleState(for: habitID)
      return
    }
    var replacement = state
    replacement.actionFailure = TodayLoggingInlineFailure(
      habitID: habitID,
      message: message(for: error)
    )
    state = replacement
  }

  private func clearIneligibleState(for habitID: PersistentIdentifier) {
    var replacement = state
    clearIneligibleState(for: habitID, in: &replacement)
    state = replacement
  }

  private func clearIneligibleState(
    for habitID: PersistentIdentifier,
    in replacement: inout TodayLoggingState
  ) {
    if replacement.sheet?.habitID == habitID {
      replacement.sheet = nil
    }
    if replacement.undo?.habitID == habitID {
      replacement.undo = nil
      expiryTask?.cancel()
    }
    if replacement.feedback?.habitID == habitID {
      replacement.feedback = nil
    }
    if replacement.actionFailure?.habitID == habitID {
      replacement.actionFailure = nil
    }
  }

  private func clearUndo(matching entryID: PersistentIdentifier) {
    guard state.undo?.entryID == entryID else { return }
    var replacement = state
    replacement.undo = nil
    expiryTask?.cancel()
    state = replacement
  }

  private func containsEntry(
    _ entryID: PersistentIdentifier,
    in snapshot: HabitLoggingSnapshot
  ) -> Bool {
    snapshot.current.entries.contains { $0.id == entryID }
      || snapshot.grace?.entries.contains { $0.id == entryID } == true
  }

  private func liveHabit(
    matching habitID: PersistentIdentifier,
    in habits: [Habit]
  ) -> Habit? {
    habits.first { $0.persistentModelID == habitID && $0.isActive }
  }

  private func bucket(
    in snapshot: HabitLoggingSnapshot,
    selection: ActivationSelection
  ) -> HabitLoggingBucketSnapshot? {
    switch selection {
    case .current:
      snapshot.current
    case .grace:
      snapshot.grace
    }
  }

  private func bucket(
    in snapshot: HabitLoggingSnapshot,
    periodKey: String
  ) -> HabitLoggingBucketSnapshot? {
    if snapshot.current.periodKey == periodKey {
      return snapshot.current
    }
    if snapshot.grace?.periodKey == periodKey {
      return snapshot.grace
    }
    return nil
  }

  private func destination(
    for selection: ActivationSelection,
    bucket: HabitLoggingBucketSnapshot
  ) -> LogEntryDestination {
    switch selection {
    case .current:
      .current
    case .grace:
      .periodKey(bucket.periodKey)
    }
  }

  private func currentStreak(for habitID: PersistentIdentifier) -> Int {
    guard case .dashboard(let dashboard)? = todayModel.presentation else {
      return 0
    }
    return (dashboard.toTendRows + dashboard.tendedRows)
      .first { $0.id == habitID }?
      .facts?.snapshot.currentStreak ?? 0
  }

  private func scopeLabel(cadence: HabitCadence, isGrace: Bool) -> String {
    switch (cadence, isGrace) {
    case (.daily, false):
      "Today"
    case (.daily, true):
      "Yesterday"
    case (.weekly, false):
      "This Week"
    case (.weekly, true):
      "Last Week"
    }
  }

  private func entryListLabel(cadence: HabitCadence, isGrace: Bool) -> String {
    switch (cadence, isGrace) {
    case (.daily, false):
      "LOGGED TODAY"
    case (.daily, true):
      "LOGGED YESTERDAY"
    case (.weekly, false):
      "LOGGED THIS WEEK"
    case (.weekly, true):
      "LOGGED LAST WEEK"
    }
  }

  private func message(for error: Error) -> String {
    if let localized = error as? LocalizedError,
      let description = localized.errorDescription,
      !description.isEmpty
    {
      return description
    }
    return "Logging unavailable. Try again."
  }

  private enum ActivationSelection {
    case current
    case grace
  }
}
