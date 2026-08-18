import Foundation
import SwiftData
import TendCore

struct TodayPresentationFormatter {
  private let context: TodayRefreshContext
  private let locale: Locale
  private let goalDateFormatter: DateFormatter

  init(context: TodayRefreshContext) {
    self.context = context
    locale = context.locale
    let formatter = DateFormatter()
    formatter.calendar = context.calendar
    formatter.locale = context.locale
    formatter.timeZone = context.timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    goalDateFormatter = formatter
  }

  func availableRow(
    for habit: Habit,
    id: PersistentIdentifier,
    snapshot: HabitTodaySnapshot
  ) throws -> TodayHabitRow {
    guard habit.target > 0, snapshot.target > 0 else {
      throw TodayPresentationFormatterError.invalidRequirement
    }
    guard snapshot.progress >= 0 else {
      throw TodayPresentationFormatterError.invalidProgress
    }
    guard snapshot.currentStreak >= 0 else {
      throw TodayPresentationFormatterError.invalidStreak
    }
    guard HabitCadence(rawValue: habit.cadenceRawValue) == snapshot.cadence,
      habit.target == snapshot.target,
      habit.unit == snapshot.unit
    else {
      throw TodayPresentationFormatterError.inconsistentSnapshot
    }

    let unit = displayedUnit(snapshot.unit, target: snapshot.target)
    let requirementText = "\(integer(snapshot.target)) \(unit)"
    let progressText = "\(integer(snapshot.progress)) of \(integer(snapshot.target)) \(unit)"
    let streakText = streak(value: snapshot.currentStreak, cadence: snapshot.cadence)
    let riskText = snapshot.isAtRisk ? risk(value: snapshot.currentStreak, cadence: snapshot.cadence) : nil
    let stateText = snapshot.isMet ? "Met" : "Unmet"
    let accessibilityValue = ([progressText, streakText, stateText] + [riskText].compactMap { $0 })
      .joined(separator: ", ")
    let fraction = Double(snapshot.progress) / Double(snapshot.target)

    return TodayHabitRow(
      id: id,
      habit: habit,
      name: habit.name,
      createdAt: habit.createdAt,
      requirementText: requirementText,
      progressText: progressText,
      streakText: streakText,
      riskText: riskText,
      facts: TodayHabitFacts(
        snapshot: snapshot,
        visualProgressFraction: min(max(fraction, 0), 1)
      ),
      failure: nil,
      accessibilityLabel: habit.name,
      accessibilityValue: accessibilityValue
    )
  }

  func unavailableRow(
    for habit: Habit,
    id: PersistentIdentifier,
    error: Error
  ) -> TodayHabitRow {
    let requirementText = requirement(target: habit.target, unit: habit.unit)
    let failure = TodayHabitFailure(message: habitMessage(for: error), retryTitle: "Try again")
    let progressText = "Progress unavailable"
    let streakText = "Streak unavailable"
    return TodayHabitRow(
      id: id,
      habit: habit,
      name: habit.name,
      createdAt: habit.createdAt,
      requirementText: requirementText,
      progressText: progressText,
      streakText: streakText,
      riskText: nil,
      facts: nil,
      failure: failure,
      accessibilityLabel: habit.name,
      accessibilityValue: [
        requirementText,
        progressText,
        streakText,
        failure.message,
        failure.retryTitle,
      ].joined(separator: ", ")
    )
  }

  func availableGoalRow(
    for goal: Goal,
    id: PersistentIdentifier,
    facts: TodayGoalFacts
  ) throws -> TodayGoalRow {
    let progress = try goalProgressFact(facts.progress, goal: goal)
    let normalizedProgress = normalizedProgress(in: progress)
    try validateStanding(facts.standing, normalizedProgress: normalizedProgress, deadline: facts.deadline)
    try validateDeadline(facts.deadline, goal: goal)

    let progressText = goalProgressText(progress)
    let deadlineText = try goalDeadlineText(facts.deadline)
    let standingText = goalStandingText(facts.standing.standing)
    return TodayGoalRow(
      id: id,
      goal: goal,
      name: goal.name,
      createdAt: goal.createdAt,
      deadline: facts.deadline,
      facts: facts,
      failure: nil,
      progress: progress,
      progressText: progressText,
      normalizedProgress: normalizedProgress,
      expectedNormalizedProgress: facts.standing.expectedNormalizedProgress,
      deadlineText: deadlineText,
      standingText: standingText,
      accessibilityLabel: goal.name,
      accessibilityValue: [progressText, deadlineText, standingText].joined(separator: ", ")
    )
  }

  func unavailableGoalRow(
    for goal: Goal,
    id: PersistentIdentifier,
    error: Error
  ) -> TodayGoalRow {
    let failure = TodayGoalFailure(message: goalMessage(for: error), retryTitle: "Try again")
    let progressText = "Progress unavailable"
    let deadlineText = "Deadline unavailable"
    let standingText = "Standing unavailable"
    return TodayGoalRow(
      id: id,
      goal: goal,
      name: goal.name,
      createdAt: goal.createdAt,
      deadline: goal.deadlineKey.flatMap(GoalDate.init(rawValue:)),
      facts: nil,
      failure: failure,
      progress: nil,
      progressText: progressText,
      normalizedProgress: nil,
      expectedNormalizedProgress: nil,
      deadlineText: deadlineText,
      standingText: standingText,
      accessibilityLabel: goal.name,
      accessibilityValue: [
        progressText,
        deadlineText,
        standingText,
        failure.message,
        failure.retryTitle,
      ].joined(separator: ", ")
    )
  }

  func isOrdered(_ lhs: TodayHabitRow, _ rhs: TodayHabitRow) -> Bool {
    let nameOrder = localizedNameOrder(lhs.name, rhs.name)
    if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
    return lhs.id < rhs.id
  }

  func areGoalsOrdered(_ lhs: TodayGoalRow, _ rhs: TodayGoalRow) -> Bool {
    let lhsUrgency = goalUrgency(lhs)
    let rhsUrgency = goalUrgency(rhs)
    if lhsUrgency != rhsUrgency { return lhsUrgency < rhsUrgency }
    if lhs.deadline != rhs.deadline {
      switch (lhs.deadline, rhs.deadline) {
      case (.some(let left), .some(let right)): return left < right
      case (.some, nil): return true
      case (nil, .some): return false
      case (nil, nil): break
      }
    }
    let nameOrder = localizedNameOrder(lhs.name, rhs.name)
    if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
    return lhs.id < rhs.id
  }

  func fraction(met: Int, active: Int) -> String {
    "\(integer(met)) of \(integer(active))"
  }

  private func goalProgressFact(
    _ snapshot: GoalProgressSnapshot,
    goal: Goal
  ) throws -> GoalDetailProgressFact {
    switch snapshot {
    case .accumulate(let progress):
      guard GoalKind(rawValue: goal.kindRawValue) == .accumulate,
        goal.baseline == nil,
        progress.target == goal.target,
        progress.unit == goal.unit,
        progress.target > 0,
        progress.total >= 0,
        progress.normalizedProgress.isFinite,
        progress.normalizedProgress >= 0,
        progress.normalizedProgress == Double(progress.total) / Double(progress.target)
      else { throw TodayPresentationFormatterError.inconsistentGoalProgress }
      return .accumulate(
        total: progress.total,
        target: progress.target,
        unit: progress.unit,
        normalizedProgress: progress.normalizedProgress
      )
    case .measure(let progress):
      let totalDistance = distance(progress.baseline, progress.target).flatMap { magnitude($0) }
      let traveled = progress.target > progress.baseline
        ? distance(progress.baseline, progress.currentValue)
        : distance(progress.currentValue, progress.baseline)
      let completed = min(max(traveled ?? -1, 0), totalDistance ?? -1)
      guard GoalKind(rawValue: goal.kindRawValue) == .measure,
        goal.baseline == progress.baseline,
        progress.target == goal.target,
        progress.unit == goal.unit,
        let totalDistance,
        totalDistance > 0,
        progress.totalDistance == totalDistance,
        completed >= 0,
        progress.completedDistance == completed,
        progress.normalizedProgress.isFinite,
        progress.normalizedProgress >= 0,
        progress.normalizedProgress == Double(completed) / Double(totalDistance)
      else { throw TodayPresentationFormatterError.inconsistentGoalProgress }
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
    }
  }

  private func validateStanding(
    _ standing: GoalStandingSnapshot,
    normalizedProgress: Double,
    deadline: GoalDate?
  ) throws {
    guard standing.actualNormalizedProgress.isFinite,
      standing.actualNormalizedProgress == normalizedProgress
    else { throw TodayPresentationFormatterError.inconsistentGoalStanding }
    if let expected = standing.expectedNormalizedProgress {
      guard expected.isFinite, (0...1).contains(expected) else {
        throw TodayPresentationFormatterError.inconsistentGoalStanding
      }
    }
    if deadline == nil {
      guard standing.expectedNormalizedProgress == nil, standing.deadlineBoundary == nil else {
        throw TodayPresentationFormatterError.inconsistentGoalStanding
      }
    } else {
      guard standing.expectedNormalizedProgress != nil, standing.deadlineBoundary != nil else {
        throw TodayPresentationFormatterError.inconsistentGoalStanding
      }
    }
    if let next = standing.nextTimeRefresh {
      guard next.timeIntervalSinceReferenceDate.isFinite else {
        throw TodayPresentationFormatterError.inconsistentGoalStanding
      }
    }
  }

  private func validateDeadline(_ deadline: GoalDate?, goal: Goal) throws {
    let persisted: GoalDate?
    if let key = goal.deadlineKey {
      guard let parsed = GoalDate(rawValue: key) else {
        throw TodayPresentationFormatterError.invalidGoalDeadline
      }
      persisted = parsed
    } else {
      persisted = nil
    }
    guard deadline == persisted else {
      throw TodayPresentationFormatterError.inconsistentGoalDeadline
    }
  }

  private func goalProgressText(_ progress: GoalDetailProgressFact) -> String {
    switch progress {
    case .accumulate(let total, let target, let unit, _):
      "\(integer(total)) of \(integer(target)) \(unit)"
    case .measure(_, _, let current, let completed, let total, _, let unit, _):
      "\(integer(current)) \(unit) now · \(integer(completed)) of \(integer(total)) \(unit)"
    }
  }

  private func normalizedProgress(in progress: GoalDetailProgressFact) -> Double {
    switch progress {
    case .accumulate(_, _, _, let value), .measure(_, _, _, _, _, _, _, let value): value
    }
  }

  private func goalDeadlineText(_ deadline: GoalDate?) throws -> String {
    guard let deadline else { return String(localized: "No deadline", locale: locale) }
    return String(
      format: String(localized: "Due %@", locale: locale),
      locale: locale,
      goalDateFormatter.string(from: try deadline.start(in: context.timeZone))
    )
  }

  private func goalStandingText(_ standing: GoalStanding) -> String {
    switch standing {
    case .onPace: String(localized: "On pace", locale: locale)
    case .behind: String(localized: "Behind", locale: locale)
    case .pastDue: String(localized: "Past due", locale: locale)
    }
  }

  private func goalUrgency(_ row: TodayGoalRow) -> Int {
    guard let facts = row.facts else { return 0 }
    switch facts.standing.standing {
    case .pastDue: return 1
    case .behind: return 2
    case .onPace: return 3
    }
  }

  private func localizedNameOrder(_ lhs: String, _ rhs: String) -> ComparisonResult {
    lhs.compare(rhs, options: [.caseInsensitive], range: nil, locale: locale)
  }

  private func distance(_ lower: Int, _ upper: Int) -> Int? {
    let result = upper.subtractingReportingOverflow(lower)
    return result.overflow ? nil : result.partialValue
  }

  private func magnitude(_ value: Int) -> Int? {
    if value >= 0 { return value }
    let result = 0.subtractingReportingOverflow(value)
    return result.overflow ? nil : result.partialValue
  }

  private func requirement(target: Int, unit: String) -> String {
    "\(integer(target)) \(displayedUnit(unit, target: target))"
  }

  private func displayedUnit(_ unit: String, target: Int) -> String {
    unit == "times" && target == 1 ? "time" : unit
  }

  private func streak(value: Int, cadence: HabitCadence) -> String {
    let unit: String
    switch cadence {
    case .daily: unit = value == 1 ? "day" : "days"
    case .weekly: unit = value == 1 ? "week" : "weeks"
    }
    return "\(integer(value)) \(unit)"
  }

  private func risk(value: Int, cadence: HabitCadence) -> String {
    switch cadence {
    case .daily: "Yesterday open · \(integer(value)) day streak at risk"
    case .weekly: "Last week open · \(integer(value)) week streak at risk"
    }
  }

  private func integer(_ value: Int) -> String {
    value.formatted(.number.locale(locale))
  }

  private func habitMessage(for error: Error) -> String {
    if let formatterError = error as? TodayPresentationFormatterError {
      switch formatterError {
      case .invalidRequirement: return "Requirement unavailable."
      case .invalidProgress, .invalidStreak, .inconsistentSnapshot: return "Today facts unavailable."
      default: return "Goal facts unavailable."
      }
    }
    if let evaluationError = error as? BucketEvaluationError {
      switch evaluationError {
      case .unsupportedCadence: return "Cadence unavailable."
      case .invalidRequirement: return "Requirement unavailable."
      default: return "Today facts unavailable."
      }
    }
    return localizedMessage(error, fallback: "Today facts unavailable.")
  }

  private func goalMessage(for error: Error) -> String {
    localizedMessage(error, fallback: "Goal facts unavailable.")
  }

  private func localizedMessage(_ error: Error, fallback: String) -> String {
    if let localizedError = error as? LocalizedError,
      let description = localizedError.errorDescription,
      !description.isEmpty
    {
      return description
    }
    return fallback
  }
}

private enum TodayPresentationFormatterError: Error {
  case invalidRequirement
  case invalidProgress
  case invalidStreak
  case inconsistentSnapshot
  case inconsistentGoalProgress
  case inconsistentGoalStanding
  case invalidGoalDeadline
  case inconsistentGoalDeadline
}
