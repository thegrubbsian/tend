import Foundation
import Observation
import SwiftData
import TendCore

@MainActor
struct GoalRosterOperations {
  typealias FetchGoals = () throws -> [Goal]
  typealias Facts = (
    _ goal: Goal,
    _ instant: Date,
    _ calendar: Calendar,
    _ timeZone: TimeZone
  ) throws -> GoalRosterDomainFacts

  let fetchGoals: FetchGoals
  let facts: Facts

  static func live(context: ModelContext) -> Self {
    let progressComputation = GoalProgressComputation(context: context)
    let standingComputation = GoalStandingComputation()

    return Self(
      fetchGoals: {
        try context.fetch(FetchDescriptor<Goal>())
      },
      facts: { goal, instant, calendar, timeZone in
        let progress = try progressComputation.snapshot(for: goal)
        let standing = try standingComputation.snapshot(
          for: goal,
          progress: progress,
          at: instant,
          calendar: calendar,
          timeZone: timeZone
        )
        let closure = try goal.checkedClosure
        return GoalRosterDomainFacts(
          progress: progress,
          standing: standing,
          closure: closure
        )
      }
    )
  }
}

struct GoalRosterDomainFacts: Equatable, Sendable {
  let progress: GoalProgressSnapshot
  let standing: GoalStandingSnapshot?
  let closure: GoalClosure?
}

struct GoalRosterRow: Identifiable {
  let goal: Goal
  let name: String
  let progress: GoalDetailProgressFact
  let progressText: String
  let deadlineText: String
  let standing: GoalStanding?
  let expectedNormalizedProgress: Double?
  let stateText: String
  let closure: GoalClosure?
  let accessibilityLabel: String
  let accessibilityValue: String

  var id: PersistentIdentifier { goal.persistentModelID }
}

struct GoalRosterLoadFailure: Equatable, Sendable {
  let message: String
  let retryTitle: String
}

@MainActor
@Observable
final class GoalRosterModel {
  private(set) var openRows: [GoalRosterRow] = []
  private(set) var pastDueRows: [GoalRosterRow] = []
  private(set) var closedRows: [GoalRosterRow] = []
  private(set) var nextRefreshInstant: Date?
  private(set) var loadFailure: GoalRosterLoadFailure?
  var isClosedExpanded = false

  private let operations: GoalRosterOperations
  private var lastRefreshRequest: RefreshRequest?

  init(context: ModelContext) {
    operations = .live(context: context)
  }

  init(operations: GoalRosterOperations) {
    self.operations = operations
  }

  func refresh(
    at instant: Date,
    calendar: Calendar,
    timeZone: TimeZone,
    locale: Locale
  ) {
    let request = RefreshRequest(
      instant: instant,
      calendar: calendar,
      timeZone: timeZone,
      locale: locale
    )
    lastRefreshRequest = request

    do {
      let replacement = try replacementRoster(for: request)
      openRows = replacement.openRows
      pastDueRows = replacement.pastDueRows
      closedRows = replacement.closedRows
      nextRefreshInstant = replacement.nextRefreshInstant
      loadFailure = nil
    } catch {
      loadFailure = GoalRosterLoadFailure(
        message: String(localized: "Goals are unavailable right now.", locale: locale),
        retryTitle: String(localized: "Try again", locale: locale)
      )
    }
  }

  func retryRefresh() {
    guard let lastRefreshRequest else { return }
    refresh(
      at: lastRefreshRequest.instant,
      calendar: lastRefreshRequest.calendar,
      timeZone: lastRefreshRequest.timeZone,
      locale: lastRefreshRequest.locale
    )
  }

  func toggleClosedDisclosure() {
    isClosedExpanded.toggle()
  }

  private func replacementRoster(for request: RefreshRequest) throws -> ReplacementRoster {
    let goals = try operations.fetchGoals()
    let builder = GoalRosterRowBuilder(
      calendar: request.calendar,
      timeZone: request.timeZone,
      locale: request.locale
    )
    var openCandidates: [GoalRosterRowCandidate] = []
    var pastDueCandidates: [GoalRosterRowCandidate] = []
    var closedCandidates: [GoalRosterRowCandidate] = []
    var nextRefreshInstant: Date?

    for goal in goals {
      let facts = try operations.facts(
        goal,
        request.instant,
        request.calendar,
        request.timeZone
      )
      let candidate = try builder.candidate(goal: goal, facts: facts)

      switch (facts.closure, facts.standing?.standing) {
      case (.none, .onPace), (.none, .behind):
        openCandidates.append(candidate)
      case (.none, .pastDue):
        pastDueCandidates.append(candidate)
      case (.some, .none):
        closedCandidates.append(candidate)
      case (.none, .none), (.some, .some):
        throw ProjectionError.inconsistentLifecycle
      }

      if let transition = facts.standing?.nextTimeRefresh, transition > request.instant {
        nextRefreshInstant = nextRefreshInstant.map { min($0, transition) } ?? transition
      }
    }

    openCandidates.sort { openRowsAreOrdered($0, $1, locale: request.locale) }
    pastDueCandidates.sort { pastDueRowsAreOrdered($0, $1, locale: request.locale) }
    closedCandidates.sort { closedRowsAreOrdered($0, $1, locale: request.locale) }

    return ReplacementRoster(
      openRows: openCandidates.map(\.row),
      pastDueRows: pastDueCandidates.map(\.row),
      closedRows: closedCandidates.map(\.row),
      nextRefreshInstant: nextRefreshInstant
    )
  }

  private func openRowsAreOrdered(
    _ lhs: GoalRosterRowCandidate,
    _ rhs: GoalRosterRowCandidate,
    locale: Locale
  ) -> Bool {
    let lhsRank = openStandingRank(lhs.row.standing)
    let rhsRank = openStandingRank(rhs.row.standing)
    if lhsRank != rhsRank {
      return lhsRank < rhsRank
    }
    if lhs.deadline != rhs.deadline {
      return optionalDeadlineIsOrdered(lhs.deadline, before: rhs.deadline)
    }
    return deterministicTieBreak(lhs, rhs, locale: locale)
  }

  private func pastDueRowsAreOrdered(
    _ lhs: GoalRosterRowCandidate,
    _ rhs: GoalRosterRowCandidate,
    locale: Locale
  ) -> Bool {
    if lhs.deadline != rhs.deadline {
      return optionalDeadlineIsOrdered(lhs.deadline, before: rhs.deadline)
    }
    return deterministicTieBreak(lhs, rhs, locale: locale)
  }

  private func closedRowsAreOrdered(
    _ lhs: GoalRosterRowCandidate,
    _ rhs: GoalRosterRowCandidate,
    locale: Locale
  ) -> Bool {
    deterministicTieBreak(lhs, rhs, locale: locale)
  }

  private func deterministicTieBreak(
    _ lhs: GoalRosterRowCandidate,
    _ rhs: GoalRosterRowCandidate,
    locale: Locale
  ) -> Bool {
    let nameOrder = lhs.row.name.compare(
      rhs.row.name,
      options: [.caseInsensitive],
      range: nil,
      locale: locale
    )
    if nameOrder != .orderedSame {
      return nameOrder == .orderedAscending
    }
    if lhs.row.goal.createdAt != rhs.row.goal.createdAt {
      return lhs.row.goal.createdAt < rhs.row.goal.createdAt
    }
    return lhs.row.goal.id.uuidString < rhs.row.goal.id.uuidString
  }

  private func optionalDeadlineIsOrdered(
    _ lhs: LocalDate?,
    before rhs: LocalDate?
  ) -> Bool {
    switch (lhs, rhs) {
    case (.some(let lhs), .some(let rhs)): lhs < rhs
    case (.some, .none): true
    case (.none, .some), (.none, .none): false
    }
  }

  private func openStandingRank(_ standing: GoalStanding?) -> Int {
    switch standing {
    case .behind: 0
    case .onPace: 1
    case .pastDue, nil: 2
    }
  }

  private struct RefreshRequest {
    let instant: Date
    let calendar: Calendar
    let timeZone: TimeZone
    let locale: Locale
  }

  private struct ReplacementRoster {
    let openRows: [GoalRosterRow]
    let pastDueRows: [GoalRosterRow]
    let closedRows: [GoalRosterRow]
    let nextRefreshInstant: Date?
  }

  private enum ProjectionError: Error {
    case inconsistentLifecycle
  }
}

private struct GoalRosterRowCandidate {
  let row: GoalRosterRow
  let deadline: LocalDate?
}

private struct GoalRosterRowBuilder {
  let timeZone: TimeZone
  let locale: Locale
  private let dateFormatter: DateFormatter

  init(calendar: Calendar, timeZone: TimeZone, locale: Locale) {
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

  func candidate(goal: Goal, facts: GoalRosterDomainFacts) throws -> GoalRosterRowCandidate {
    let progress = progressFact(facts.progress)
    let progressText = progressText(progress)
    let deadline = try deadline(for: goal)
    let deadlineText = try deadlineText(deadline)
    let stateText = try stateText(standing: facts.standing?.standing, closure: facts.closure)
    let row = GoalRosterRow(
      goal: goal,
      name: goal.name,
      progress: progress,
      progressText: progressText,
      deadlineText: deadlineText,
      standing: facts.standing?.standing,
      expectedNormalizedProgress: facts.standing?.expectedNormalizedProgress,
      stateText: stateText,
      closure: facts.closure,
      accessibilityLabel: goal.name,
      accessibilityValue: "\(stateText), \(progressText), \(deadlineText)"
    )
    return GoalRosterRowCandidate(row: row, deadline: deadline)
  }

  private func progressFact(_ snapshot: GoalProgressSnapshot) -> GoalDetailProgressFact {
    switch snapshot {
    case .accumulate(let progress):
      .accumulate(
        total: progress.total,
        target: progress.target,
        unit: progress.unit,
        normalizedProgress: progress.normalizedProgress
      )
    case .measure(let progress):
      .measure(
        baseline: progress.baseline,
        target: progress.target,
        current: progress.currentValue,
        completedDistance: progress.completedDistance,
        totalDistance: progress.totalDistance,
        direction: progress.target > progress.baseline ? .increasing : .decreasing,
        unit: progress.unit,
        normalizedProgress: progress.normalizedProgress
      )
    }
  }

  private func progressText(_ progress: GoalDetailProgressFact) -> String {
    switch progress {
    case .accumulate(let total, let target, let unit, _):
      "\(number(total)) of \(number(target)) \(unit)"
    case .measure(_, _, let current, let completed, let total, _, let unit, _):
      "\(number(current)) \(unit) now · \(number(completed)) of \(number(total)) \(unit)"
    }
  }

  private func deadline(for goal: Goal) throws -> LocalDate? {
    guard let deadlineKey = goal.deadlineKey else { return nil }
    guard let deadline = LocalDate(rawValue: deadlineKey) else {
      throw ProjectionError.invalidDeadline
    }
    return deadline
  }

  private func deadlineText(_ deadline: LocalDate?) throws -> String {
    guard let deadline else {
      return String(localized: "No deadline", locale: locale)
    }
    return dateFormatter.string(from: try deadline.start(in: timeZone))
  }

  private func stateText(
    standing: GoalStanding?,
    closure: GoalClosure?
  ) throws -> String {
    switch (closure, standing) {
    case (.harvested, nil): String(localized: "Harvested", locale: locale)
    case (.letGo, nil): String(localized: "Let go", locale: locale)
    case (nil, .onPace): String(localized: "On pace", locale: locale)
    case (nil, .behind): String(localized: "Behind", locale: locale)
    case (nil, .pastDue): String(localized: "Past due", locale: locale)
    case (.some, .some), (nil, nil): throw ProjectionError.inconsistentLifecycle
    }
  }

  private func number(_ value: Int) -> String {
    value.formatted(.number.locale(locale))
  }

  private enum ProjectionError: Error {
    case inconsistentLifecycle
    case invalidDeadline
  }
}
