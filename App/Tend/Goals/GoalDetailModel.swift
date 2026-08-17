import Foundation
import Observation
import SwiftData
import TendCore

struct GoalDetailLoadFailure: Equatable, Sendable {
  let message: String
  let retryTitle: String
}

enum GoalDetailMeasureDirection: Equatable, Sendable {
  case increasing
  case decreasing
}

enum GoalDetailProgressFact: Equatable, Sendable {
  case accumulate(
    total: Int,
    target: Int,
    unit: String,
    normalizedProgress: Double
  )
  case measure(
    baseline: Int,
    target: Int,
    current: Int,
    completedDistance: Int,
    totalDistance: Int,
    direction: GoalDetailMeasureDirection,
    unit: String,
    normalizedProgress: Double
  )
}

enum GoalDetailHistoryID: Equatable, Hashable, Sendable {
  case entry(GoalEntryIdentity)
  case reading(GoalReadingIdentity)
}

struct GoalDetailHistoryFact: Equatable, Identifiable, Sendable {
  let id: GoalDetailHistoryID
  let assignedDate: GoalDate
  let value: Int
  let dateText: String
  let valueText: String
  let isEffective: Bool
  let isDeleteEligible: Bool
}

struct GoalDetailAppendDestination: Equatable, Sendable {
  let destination: GoalProgressDestination
  let title: String
}

enum GoalDetailAction: Equatable, Sendable {
  case edit
  case addProgress
  case harvest
  case letGo
  case reopen
  case deleteGoal
}

struct GoalDetailPresentation: Equatable, Sendable {
  let goalID: UUID
  let name: String
  let kind: GoalKind
  let progress: GoalDetailProgressFact
  let progressText: String
  let deadlineText: String
  let standing: GoalStanding?
  let expectedNormalizedProgress: Double?
  let standingText: String?
  let closure: GoalClosure?
  let closureText: String?
  let appendDestinations: [GoalDetailAppendDestination]
  let history: [GoalDetailHistoryFact]
  let actions: [GoalDetailAction]
}

enum GoalDetailConfirmation: Equatable, Sendable {
  case harvest
  case letGo
  case reopen
  case deleteGoal
  case deleteHistory(GoalDetailHistoryID)
}

struct GoalDetailOperationFailure: Equatable, Sendable {
  enum Placement: Equatable, Sendable {
    case entrySheet
    case history
    case lifecycle
    case goalDeletion
    case reload
  }

  let message: String
  let retryTitle: String
  let cancelTitle: String?
  let placement: Placement

  var canCancel: Bool { cancelTitle != nil }
}

enum GoalDetailDeleteHistoryResult: Equatable, Sendable {
  case deleted
  case rejected
}

@MainActor
struct GoalDetailOperations {
  typealias Snapshot = (
    _ goal: Goal,
    _ instant: Date,
    _ calendar: Calendar,
    _ timeZone: TimeZone
  ) throws -> GoalDetailSnapshot
  typealias Append = (
    _ value: Int,
    _ goal: Goal,
    _ destination: GoalProgressDestination,
    _ instant: Date,
    _ timeZone: TimeZone
  ) throws -> Void
  typealias DeleteHistory = (
    _ id: GoalDetailHistoryID,
    _ goal: Goal,
    _ instant: Date,
    _ timeZone: TimeZone
  ) throws -> GoalDetailDeleteHistoryResult
  typealias Close = (_ goal: Goal, _ closure: GoalClosure) throws -> Void
  typealias Reopen = (_ goal: Goal) throws -> Void
  typealias DeleteGoal = (_ goal: Goal) throws -> Void

  let snapshot: Snapshot
  let appendAmount: Append
  let appendValue: Append
  let deleteHistory: DeleteHistory
  let close: Close
  let reopen: Reopen
  let deleteGoal: DeleteGoal

  init(
    snapshot: @escaping Snapshot,
    appendAmount: @escaping Append = { _, _, _, _, _ in
      throw UnsupportedOperation.mutation
    },
    appendValue: @escaping Append = { _, _, _, _, _ in
      throw UnsupportedOperation.mutation
    },
    deleteHistory: @escaping DeleteHistory = { _, _, _, _ in
      throw UnsupportedOperation.mutation
    },
    close: @escaping Close = { _, _ in
      throw UnsupportedOperation.mutation
    },
    reopen: @escaping Reopen = { _ in
      throw UnsupportedOperation.mutation
    },
    deleteGoal: @escaping DeleteGoal = { _ in
      throw UnsupportedOperation.mutation
    }
  ) {
    self.snapshot = snapshot
    self.appendAmount = appendAmount
    self.appendValue = appendValue
    self.deleteHistory = deleteHistory
    self.close = close
    self.reopen = reopen
    self.deleteGoal = deleteGoal
  }

  static func live(context: ModelContext) -> Self {
    let query = GoalDetailQuery(context: context)
    let progress = GoalProgressOperations(context: context)
    let lifecycle = GoalLifecycleOperations(context: context)
    let management = GoalManagementOperations(context: context)

    return Self(
      snapshot: { goal, instant, calendar, timeZone in
        try query.snapshot(
          for: goal,
          at: instant,
          calendar: calendar,
          timeZone: timeZone
        )
      },
      appendAmount: { value, goal, destination, instant, timeZone in
        try progress.append(
          amount: value,
          to: goal,
          destination: destination,
          at: instant,
          timeZone: timeZone
        )
      },
      appendValue: { value, goal, destination, instant, timeZone in
        try progress.append(
          value: value,
          to: goal,
          destination: destination,
          at: instant,
          timeZone: timeZone
        )
      },
      deleteHistory: { id, goal, instant, timeZone in
        switch id {
        case .entry(let identity):
          let rawID = identity.rawValue
          let matches = try context.fetch(
            FetchDescriptor<GoalEntry>(predicate: #Predicate { $0.id == rawID })
          )
          let owned = matches.filter {
            $0.goal?.persistentModelID == goal.persistentModelID
          }
          guard owned.count == 1, let entry = owned.first else {
            return .rejected
          }
          try progress.delete(entry, from: goal, at: instant, timeZone: timeZone)
        case .reading(let identity):
          let rawID = identity.rawValue
          let matches = try context.fetch(
            FetchDescriptor<GoalReading>(predicate: #Predicate { $0.id == rawID })
          )
          let owned = matches.filter {
            $0.goal?.persistentModelID == goal.persistentModelID
          }
          guard owned.count == 1, let reading = owned.first else {
            return .rejected
          }
          try progress.delete(reading, from: goal, at: instant, timeZone: timeZone)
        }
        return .deleted
      },
      close: { goal, closure in
        try lifecycle.close(goal, as: closure)
      },
      reopen: { goal in
        try lifecycle.reopen(goal)
      },
      deleteGoal: { goal in
        try management.delete(goal)
      }
    )
  }

  private enum UnsupportedOperation: Error {
    case mutation
  }
}

@MainActor
@Observable
final class GoalDetailModel {
  let goalID: UUID

  private(set) var presentation: GoalDetailPresentation?
  private(set) var loadFailure: GoalDetailLoadFailure?
  private(set) var operationFailure: GoalDetailOperationFailure?
  private(set) var isOperationInFlight = false
  private(set) var isPresentingEntrySheet = false
  var entryText = ""
  private(set) var selectedAppendDestination: GoalProgressDestination?
  private(set) var isPresentingEdit = false
  private(set) var confirmation: GoalDetailConfirmation?
  private(set) var isDeleted = false

  var canMutate: Bool {
    presentation != nil
      && loadFailure == nil
      && operationFailure == nil
      && !isOperationInFlight
      && !isDeleted
  }

  var canSaveEntry: Bool {
    guard
      canMutate,
      isPresentingEntrySheet,
      let presentation,
      let selectedAppendDestination,
      presentation.appendDestinations.contains(where: {
        $0.destination == selectedAppendDestination
      })
    else { return false }

    return parsedEntry(for: presentation.kind) != nil
  }

  var entryValidationMessage: String? {
    guard
      isPresentingEntrySheet,
      !entryText.isEmpty,
      let kind = presentation?.kind,
      parsedEntry(for: kind) == nil
    else { return nil }

    let currentLocale = Locale(identifier: locale().identifier)
    switch kind {
    case .accumulate:
      return String(
        localized: "Enter a positive whole number.",
        locale: currentLocale
      )
    case .measure:
      return String(localized: "Enter a whole number.", locale: currentLocale)
    }
  }

  var goalForEditing: Goal? {
    guard canMutate, isPresentingEdit else { return nil }
    return goal
  }

  @ObservationIgnored private let goal: Goal
  @ObservationIgnored private let operations: GoalDetailOperations
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private let timeZone: () -> TimeZone
  @ObservationIgnored private let calendar: () -> Calendar
  @ObservationIgnored private let locale: () -> Locale
  @ObservationIgnored private var retryState: RetryState?

  convenience init(
    goal: Goal,
    context: ModelContext,
    now: @escaping () -> Date = Date.init,
    timeZone: @escaping () -> TimeZone = { TimeZone.current },
    calendar: @escaping () -> Calendar = { Calendar(identifier: .gregorian) },
    locale: @escaping () -> Locale = { Locale.current }
  ) {
    self.init(
      goal: goal,
      operations: .live(context: context),
      now: now,
      timeZone: timeZone,
      calendar: calendar,
      locale: locale
    )
  }

  init(
    goal: Goal,
    operations: GoalDetailOperations,
    now: @escaping () -> Date,
    timeZone: @escaping () -> TimeZone,
    calendar: @escaping () -> Calendar,
    locale: @escaping () -> Locale
  ) {
    goalID = goal.id
    self.goal = goal
    self.operations = operations
    self.now = now
    self.timeZone = timeZone
    self.calendar = calendar
    self.locale = locale
  }

  func start() {
    load(using: makeContext())
  }

  func refresh() {
    guard !isOperationInFlight, operationFailure == nil, !isDeleted else { return }
    load(using: makeContext())
  }

  func retryLoad() {
    guard loadFailure != nil, !isOperationInFlight, operationFailure == nil, !isDeleted else {
      return
    }
    load(using: makeContext())
  }

  func presentEntrySheet() {
    guard
      canMutate,
      !isPresentingEntrySheet,
      !isPresentingEdit,
      confirmation == nil,
      presentation?.actions.contains(.addProgress) == true,
      let first = presentation?.appendDestinations.first?.destination
    else { return }
    entryText = ""
    selectedAppendDestination = first
    isPresentingEntrySheet = true
  }

  func selectAppendDestination(_ destination: GoalProgressDestination) {
    guard
      isPresentingEntrySheet,
      canMutate,
      presentation?.appendDestinations.contains(where: { $0.destination == destination }) == true
    else { return }
    selectedAppendDestination = destination
  }

  func cancelEntrySheet() {
    guard !isOperationInFlight, operationFailure == nil else { return }
    dismissEntrySheet()
  }

  func saveEntry() {
    guard
      canSaveEntry,
      let presentation,
      let destination = selectedAppendDestination,
      let value = parsedEntry(for: presentation.kind)
    else { return }
    let request: MutationRequest = .append(
      kind: presentation.kind,
      value: value,
      destination: destination
    )
    perform(MutationEnvelope(request: request, context: makeContext()))
  }

  func presentEdit() {
    guard
      canMutate,
      !isPresentingEntrySheet,
      confirmation == nil,
      presentation?.actions.contains(.edit) == true
    else { return }
    isPresentingEdit = true
  }

  func editCancelled() {
    guard !isOperationInFlight else { return }
    isPresentingEdit = false
  }

  func editSaved() {
    guard isPresentingEdit, !isOperationInFlight else { return }
    isPresentingEdit = false
    load(using: makeContext())
  }

  func requestConfirmation(_ requested: GoalDetailConfirmation) {
    guard
      canMutate,
      !isPresentingEntrySheet,
      !isPresentingEdit,
      confirmation == nil,
      isAuthorized(requested)
    else { return }
    confirmation = requested
  }

  func requestHistoryDeletion(_ id: GoalDetailHistoryID) {
    requestConfirmation(.deleteHistory(id))
  }

  func cancelConfirmation() {
    guard !isOperationInFlight, operationFailure == nil else { return }
    confirmation = nil
  }

  func confirmPendingAction() {
    guard canMutate, let confirmation else { return }
    let request: MutationRequest
    switch confirmation {
    case .harvest:
      request = .close(.harvested)
    case .letGo:
      request = .close(.letGo)
    case .reopen:
      request = .reopen
    case .deleteGoal:
      request = .deleteGoal
    case .deleteHistory(let id):
      request = .deleteHistory(id)
    }
    perform(MutationEnvelope(request: request, context: makeContext()))
  }

  func retryOperation() {
    guard !isOperationInFlight, let retryState else { return }
    switch retryState {
    case .mutation(let envelope):
      perform(envelope, isRetry: true)
    case .reload(let committed):
      reloadCommitted(committed)
    }
  }

  func cancelOperationFailure() {
    guard
      !isOperationInFlight,
      operationFailure?.canCancel == true,
      case .mutation(let envelope) = retryState
    else { return }

    clearInteraction(for: envelope.request)
    retryState = nil
    operationFailure = nil
  }

  private func perform(_ envelope: MutationEnvelope, isRetry: Bool = false) {
    guard !isOperationInFlight, !isDeleted else { return }
    if isRetry {
      guard case .mutation = retryState else { return }
    } else {
      guard operationFailure == nil, loadFailure == nil else { return }
    }
    guard isAuthorized(envelope.request) else { return }

    isOperationInFlight = true
    defer { isOperationInFlight = false }

    do {
      let didCommit = try dispatch(envelope)
      retryState = nil
      operationFailure = nil

      if envelope.request == .deleteGoal {
        isDeleted = true
        confirmation = nil
        return
      }

      if didCommit {
        reloadCommitted(
          CommittedMutation(request: envelope.request, context: envelope.context),
          alreadyInFlight: true
        )
      } else {
        load(using: envelope.context, alreadyInFlight: true)
      }
    } catch {
      retryState = .mutation(envelope)
      operationFailure = failure(for: envelope.request, locale: envelope.context.locale)
    }
  }

  private func dispatch(_ envelope: MutationEnvelope) throws -> Bool {
    switch envelope.request {
    case .append(let kind, let value, let destination):
      switch kind {
      case .accumulate:
        try operations.appendAmount(
          value,
          goal,
          destination,
          envelope.context.instant,
          envelope.context.timeZone
        )
      case .measure:
        try operations.appendValue(
          value,
          goal,
          destination,
          envelope.context.instant,
          envelope.context.timeZone
        )
      }
      return true
    case .deleteHistory(let id):
      let result = try operations.deleteHistory(
        id,
        goal,
        envelope.context.instant,
        envelope.context.timeZone
      )
      guard result == .deleted else {
        throw MutationDispatchError.rejectedHistoryIdentity
      }
      return true
    case .close(let closure):
      try operations.close(goal, closure)
      return true
    case .reopen:
      try operations.reopen(goal)
      return true
    case .deleteGoal:
      try operations.deleteGoal(goal)
      return true
    }
  }

  private func reloadCommitted(
    _ committed: CommittedMutation,
    alreadyInFlight: Bool = false
  ) {
    guard !isOperationInFlight || alreadyInFlight else { return }
    if !alreadyInFlight {
      isOperationInFlight = true
    }
    defer {
      if !alreadyInFlight {
        isOperationInFlight = false
      }
    }

    do {
      let replacement = try replacementPresentation(using: committed.context)
      presentation = replacement
      loadFailure = nil
      retryState = nil
      operationFailure = nil
      clearInteraction(for: committed.request)
    } catch {
      retryState = .reload(committed)
      operationFailure = reloadFailure(locale: committed.context.locale)
    }
  }

  private func load(using context: LoadContext, alreadyInFlight: Bool = false) {
    guard !isOperationInFlight || alreadyInFlight else { return }
    if !alreadyInFlight {
      isOperationInFlight = true
    }
    defer {
      if !alreadyInFlight {
        isOperationInFlight = false
      }
    }

    do {
      let replacement = try replacementPresentation(using: context)
      presentation = replacement
      reconcileInteractions(with: replacement)
      loadFailure = nil
    } catch {
      loadFailure = GoalDetailLoadFailure(
        message: String(
          localized: "This goal is unavailable right now.",
          locale: context.locale
        ),
        retryTitle: String(localized: "Try again", locale: context.locale)
      )
    }
  }

  private func replacementPresentation(using context: LoadContext) throws -> GoalDetailPresentation {
    let snapshot = try operations.snapshot(
      goal,
      context.instant,
      context.calendar,
      context.timeZone
    )
    return try GoalDetailPresentationBuilder(
      goalID: goalID,
      instant: context.instant,
      calendar: context.calendar,
      timeZone: context.timeZone,
      locale: context.locale
    ).presentation(from: snapshot)
  }

  private func isAuthorized(_ confirmation: GoalDetailConfirmation) -> Bool {
    guard let presentation else { return false }
    switch confirmation {
    case .harvest:
      return presentation.actions.contains(.harvest)
    case .letGo:
      return presentation.actions.contains(.letGo)
    case .reopen:
      return presentation.actions.contains(.reopen)
    case .deleteGoal:
      return presentation.actions.contains(.deleteGoal)
    case .deleteHistory(let id):
      return presentation.history.contains { $0.id == id && $0.isDeleteEligible }
    }
  }

  private func isAuthorized(_ request: MutationRequest) -> Bool {
    guard let presentation else { return false }
    switch request {
    case .append(let kind, _, let destination):
      return presentation.kind == kind
        && presentation.actions.contains(.addProgress)
        && presentation.appendDestinations.contains { $0.destination == destination }
    case .deleteHistory(let id):
      return presentation.history.contains { $0.id == id && $0.isDeleteEligible }
    case .close(.harvested):
      return presentation.actions.contains(.harvest)
    case .close(.letGo):
      return presentation.actions.contains(.letGo)
    case .reopen:
      return presentation.actions.contains(.reopen)
    case .deleteGoal:
      return presentation.actions.contains(.deleteGoal)
    }
  }

  private func failure(
    for request: MutationRequest,
    locale: Locale
  ) -> GoalDetailOperationFailure {
    let message: String
    let placement: GoalDetailOperationFailure.Placement
    switch request {
    case .append:
      message = String(localized: "This progress could not be saved.", locale: locale)
      placement = .entrySheet
    case .deleteHistory:
      message = String(localized: "This history item could not be deleted.", locale: locale)
      placement = .history
    case .close:
      message = String(localized: "This goal could not be closed.", locale: locale)
      placement = .lifecycle
    case .reopen:
      message = String(localized: "This goal could not be reopened.", locale: locale)
      placement = .lifecycle
    case .deleteGoal:
      message = String(localized: "This goal could not be deleted.", locale: locale)
      placement = .goalDeletion
    }
    return GoalDetailOperationFailure(
      message: message,
      retryTitle: String(localized: "Try again", locale: locale),
      cancelTitle: String(localized: "Cancel", locale: locale),
      placement: placement
    )
  }

  private func reloadFailure(locale: Locale) -> GoalDetailOperationFailure {
    GoalDetailOperationFailure(
      message: String(
        localized: "Your change was saved, but this goal could not be refreshed.",
        locale: locale
      ),
      retryTitle: String(localized: "Try again", locale: locale),
      cancelTitle: nil,
      placement: .reload
    )
  }

  private func reconcileInteractions(with replacement: GoalDetailPresentation) {
    if let confirmation, !isAuthorized(confirmation) {
      self.confirmation = nil
    }
    if isPresentingEntrySheet {
      guard
        replacement.actions.contains(.addProgress),
        let selectedAppendDestination,
        replacement.appendDestinations.contains(where: {
          $0.destination == selectedAppendDestination
        })
      else {
        dismissEntrySheet()
        return
      }
    }
    if isPresentingEdit, !replacement.actions.contains(.edit) {
      isPresentingEdit = false
    }
  }

  private func clearInteraction(for request: MutationRequest) {
    switch request {
    case .append:
      dismissEntrySheet()
    case .deleteHistory, .close, .reopen, .deleteGoal:
      confirmation = nil
    }
  }

  private func dismissEntrySheet() {
    isPresentingEntrySheet = false
    entryText = ""
    selectedAppendDestination = nil
  }

  private func parsedEntry(for kind: GoalKind) -> Int? {
    guard let value = Int(entryText) else { return nil }
    switch kind {
    case .accumulate:
      guard value > 0, entryText == String(value) else { return nil }
    case .measure:
      guard entryText == String(value) else { return nil }
    }
    return value
  }

  private func makeContext() -> LoadContext {
    let sampledTimeZone = timeZone()
    let fixedTimeZone = TimeZone(identifier: sampledTimeZone.identifier) ?? sampledTimeZone
    let sampledLocale = locale()
    let fixedLocale = Locale(identifier: sampledLocale.identifier)
    var fixedCalendar = calendar()
    if fixedCalendar.identifier != .gregorian {
      fixedCalendar = Calendar(identifier: .gregorian)
    }
    fixedCalendar.timeZone = fixedTimeZone
    fixedCalendar.locale = fixedLocale
    return LoadContext(
      instant: now(),
      calendar: fixedCalendar,
      timeZone: fixedTimeZone,
      locale: fixedLocale
    )
  }
}

extension GoalDetailModel {
  fileprivate enum MutationRequest: Equatable {
    case append(kind: GoalKind, value: Int, destination: GoalProgressDestination)
    case deleteHistory(GoalDetailHistoryID)
    case close(GoalClosure)
    case reopen
    case deleteGoal
  }

  fileprivate struct LoadContext {
    let instant: Date
    let calendar: Calendar
    let timeZone: TimeZone
    let locale: Locale
  }

  fileprivate struct MutationEnvelope {
    let request: MutationRequest
    let context: LoadContext
  }

  fileprivate struct CommittedMutation {
    let request: MutationRequest
    let context: LoadContext
  }

  fileprivate enum RetryState {
    case mutation(MutationEnvelope)
    case reload(CommittedMutation)
  }

  fileprivate enum MutationDispatchError: Error {
    case rejectedHistoryIdentity
  }
}

private struct GoalDetailPresentationBuilder {
  let goalID: UUID
  let instant: Date
  let calendar: Calendar
  let timeZone: TimeZone
  let locale: Locale
  private let dateFormatter: DateFormatter

  init(
    goalID: UUID,
    instant: Date,
    calendar: Calendar,
    timeZone: TimeZone,
    locale: Locale
  ) {
    self.goalID = goalID
    self.instant = instant
    self.calendar = calendar
    self.timeZone = timeZone
    self.locale = locale
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.locale = locale
    dateFormatter.timeZone = timeZone
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .none
    self.dateFormatter = dateFormatter
  }

  func presentation(from snapshot: GoalDetailSnapshot) throws -> GoalDetailPresentation {
    guard snapshot.metadata.id == goalID else {
      throw ProjectionError.unexpectedGoal(snapshot.metadata.id)
    }

    let progress = try progressFact(snapshot)
    let standing = try standingFact(
      snapshot,
      normalizedProgress: normalizedProgress(in: progress)
    )
    let history = try snapshot.history.map { try historyFact($0, metadata: snapshot.metadata) }
    let appendDestinations = snapshot.availableAppendDestinations.map {
      GoalDetailAppendDestination(destination: $0, title: destinationTitle($0))
    }
    let actions: [GoalDetailAction]
    if snapshot.metadata.closure == nil {
      actions = [.edit]
        + (appendDestinations.isEmpty ? [] : [.addProgress])
        + [.harvest, .letGo, .deleteGoal]
    } else {
      actions = [.edit, .reopen, .deleteGoal]
    }

    return GoalDetailPresentation(
      goalID: goalID,
      name: snapshot.metadata.name,
      kind: snapshot.metadata.kind,
      progress: progress,
      progressText: progressText(progress),
      deadlineText: deadlineText(snapshot.metadata.deadline),
      standing: standing?.standing,
      expectedNormalizedProgress: standing?.expectedNormalizedProgress,
      standingText: standingText(standing?.standing),
      closure: snapshot.metadata.closure,
      closureText: closureText(snapshot.metadata.closure),
      appendDestinations: appendDestinations,
      history: history,
      actions: actions
    )
  }

  private func progressFact(_ snapshot: GoalDetailSnapshot) throws -> GoalDetailProgressFact {
    switch (snapshot.metadata.kind, snapshot.progress) {
    case (.accumulate, .accumulate(let progress)):
      guard
        progress.target == snapshot.metadata.target,
        progress.unit == snapshot.metadata.unit,
        progress.normalizedProgress.isFinite
      else { throw ProjectionError.inconsistentProgress }
      return .accumulate(
        total: progress.total,
        target: progress.target,
        unit: progress.unit,
        normalizedProgress: progress.normalizedProgress
      )
    case (.measure, .measure(let progress)):
      guard
        progress.baseline == snapshot.metadata.baseline,
        progress.target == snapshot.metadata.target,
        progress.unit == snapshot.metadata.unit,
        progress.normalizedProgress.isFinite
      else { throw ProjectionError.inconsistentProgress }
      return .measure(
        baseline: progress.baseline,
        target: progress.target,
        current: progress.currentValue,
        completedDistance: progress.completedDistance,
        totalDistance: progress.totalDistance,
        direction: progress.target > progress.baseline ? .increasing : .decreasing,
        unit: progress.unit,
        normalizedProgress: progress.normalizedProgress
      )
    default:
      throw ProjectionError.inconsistentProgress
    }
  }

  private func standingFact(
    _ snapshot: GoalDetailSnapshot,
    normalizedProgress: Double
  ) throws -> GoalStandingSnapshot? {
    switch (snapshot.metadata.closure, snapshot.standing) {
    case (nil, .some(let standing)):
      let actual = standing.actualNormalizedProgress
      guard
        actual.isFinite,
        actual >= 0,
        actual == normalizedProgress
      else { throw ProjectionError.inconsistentStanding }

      guard snapshot.metadata.deadline != nil else {
        guard
          standing.standing == .onPace,
          standing.expectedNormalizedProgress == nil,
          standing.deadlineBoundary == nil
        else { throw ProjectionError.inconsistentStanding }
        return standing
      }

      guard
        let expected = standing.expectedNormalizedProgress,
        expected.isFinite,
        (0...1).contains(expected),
        let boundary = standing.deadlineBoundary,
        boundary.timeIntervalSinceReferenceDate.isFinite
      else { throw ProjectionError.inconsistentStanding }

      if instant < boundary {
        let expectedStanding: GoalStanding =
          actual >= expected ? .onPace : .behind
        guard standing.standing == expectedStanding else {
          throw ProjectionError.inconsistentStanding
        }
      } else {
        guard standing.standing == .pastDue, expected == 1 else {
          throw ProjectionError.inconsistentStanding
        }
      }
      return standing
    case (.some, nil):
      return nil
    case (nil, nil), (.some, .some):
      throw ProjectionError.inconsistentStanding
    }
  }

  private func normalizedProgress(in progress: GoalDetailProgressFact) -> Double {
    switch progress {
    case .accumulate(_, _, _, let normalizedProgress),
      .measure(_, _, _, _, _, _, _, let normalizedProgress):
      normalizedProgress
    }
  }

  private func historyFact(
    _ item: GoalDetailHistoryItem,
    metadata: GoalDetailMetadata
  ) throws -> GoalDetailHistoryFact {
    switch item {
    case .entry(let entry):
      guard metadata.kind == .accumulate else { throw ProjectionError.inconsistentHistory }
      return GoalDetailHistoryFact(
        id: .entry(entry.id),
        assignedDate: entry.assignedDate,
        value: entry.amount,
        dateText: dayText(entry.assignedDate),
        valueText: quantity(entry.amount, unit: metadata.unit),
        isEffective: false,
        isDeleteEligible: entry.isDeleteEligible
      )
    case .reading(let reading):
      guard metadata.kind == .measure else { throw ProjectionError.inconsistentHistory }
      return GoalDetailHistoryFact(
        id: .reading(reading.id),
        assignedDate: reading.assignedDate,
        value: reading.value,
        dateText: dayText(reading.assignedDate),
        valueText: quantity(reading.value, unit: metadata.unit),
        isEffective: reading.isEffective,
        isDeleteEligible: reading.isDeleteEligible
      )
    }
  }

  private func progressText(_ progress: GoalDetailProgressFact) -> String {
    switch progress {
    case .accumulate(let total, let target, let unit, _):
      return "\(number(total)) of \(number(target)) \(unit)"
    case .measure(_, _, let current, let completed, let total, _, let unit, _):
      return "\(number(current)) \(unit) now · \(number(completed)) of \(number(total)) \(unit)"
    }
  }

  private func deadlineText(_ deadline: GoalDate?) -> String {
    guard let deadline else {
      return String(localized: "No deadline", locale: locale)
    }
    let formattedDeadline = formatted(deadline)
    guard
      let today = localGoalDate(instant),
      let todayStart = try? today.start(in: timeZone),
      let deadlineStart = try? deadline.start(in: timeZone),
      let dayDistance = calendar.dateComponents(
        [.day],
        from: todayStart,
        to: deadlineStart
      ).day
    else {
      return String(
        format: String(localized: "Due %@", locale: locale),
        locale: locale,
        formattedDeadline
      )
    }

    let context: String
    switch dayDistance {
    case 0:
      context = String(localized: "Due today", locale: locale)
    case 1:
      context = String(localized: "1 day remaining", locale: locale)
    case 2...:
      context = String(
        format: String(localized: "%lld days remaining", locale: locale),
        locale: locale,
        Int64(dayDistance)
      )
    case -1:
      context = String(localized: "1 day past due", locale: locale)
    default:
      context = String(
        format: String(localized: "%lld days past due", locale: locale),
        locale: locale,
        Int64(-dayDistance)
      )
    }
    let format =
      dayDistance == 0
      ? String(localized: "%@ · %@", locale: locale)
      : String(localized: "%@ · Due %@", locale: locale)
    return String(
      format: format,
      locale: locale,
      context,
      formattedDeadline
    )
  }

  private func standingText(_ standing: GoalStanding?) -> String? {
    switch standing {
    case .onPace: String(localized: "On pace", locale: locale)
    case .behind: String(localized: "Behind", locale: locale)
    case .pastDue: String(localized: "Past due", locale: locale)
    case nil: nil
    }
  }

  private func closureText(_ closure: GoalClosure?) -> String? {
    switch closure {
    case .harvested: String(localized: "Harvested", locale: locale)
    case .letGo: String(localized: "Let go", locale: locale)
    case nil: nil
    }
  }

  private func destinationTitle(_ destination: GoalProgressDestination) -> String {
    switch destination {
    case .today: String(localized: "Today", locale: locale)
    case .yesterday: String(localized: "Yesterday", locale: locale)
    }
  }

  private func dayText(_ assignedDate: GoalDate) -> String {
    guard let today = localGoalDate(instant) else { return formatted(assignedDate) }
    if assignedDate == today {
      return String(localized: "Today", locale: locale)
    }
    if assignedDate == (try? today.previous()) {
      return String(localized: "Yesterday", locale: locale)
    }
    return formatted(assignedDate)
  }

  private func localGoalDate(_ date: Date) -> GoalDate? {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard
      let year = components.year,
      let month = components.month,
      let day = components.day
    else { return nil }
    return GoalDate(year: year, month: month, day: day)
  }

  private func formatted(_ goalDate: GoalDate) -> String {
    guard let date = try? goalDate.start(in: timeZone) else { return goalDate.rawValue }
    return dateFormatter.string(from: date)
  }

  private func quantity(_ value: Int, unit: String) -> String {
    "\(number(value)) \(unit)"
  }

  private func number(_ value: Int) -> String {
    value.formatted(.number.locale(locale))
  }

  private enum ProjectionError: Error {
    case unexpectedGoal(UUID)
    case inconsistentProgress
    case inconsistentHistory
    case inconsistentStanding
  }
}

