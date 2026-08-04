import Foundation
import SwiftData
import TendCore

struct TodayPresentationFormatter {
  private let locale: Locale

  init(context: TodayRefreshContext) {
    locale = context.locale
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
    let progressText =
      "\(integer(snapshot.progress)) of \(integer(snapshot.target)) \(unit)"
    let streakText = streak(
      value: snapshot.currentStreak,
      cadence: snapshot.cadence
    )
    let riskText =
      snapshot.isAtRisk
      ? risk(value: snapshot.currentStreak, cadence: snapshot.cadence)
      : nil
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
    let failure = TodayHabitFailure(
      message: message(for: error),
      retryTitle: "Try again"
    )
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

  func isOrdered(_ lhs: TodayHabitRow, _ rhs: TodayHabitRow) -> Bool {
    let nameOrder = lhs.name.compare(
      rhs.name,
      options: [.caseInsensitive],
      range: nil,
      locale: locale
    )
    if nameOrder != .orderedSame {
      return nameOrder == .orderedAscending
    }
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt < rhs.createdAt
    }
    return lhs.id < rhs.id
  }

  func fraction(met: Int, active: Int) -> String {
    "\(integer(met)) of \(integer(active))"
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
    case .daily:
      unit = value == 1 ? "day" : "days"
    case .weekly:
      unit = value == 1 ? "week" : "weeks"
    }
    return "\(integer(value)) \(unit)"
  }

  private func risk(value: Int, cadence: HabitCadence) -> String {
    switch cadence {
    case .daily:
      "Yesterday open · \(integer(value)) day streak at risk"
    case .weekly:
      "Last week open · \(integer(value)) week streak at risk"
    }
  }

  private func integer(_ value: Int) -> String {
    value.formatted(.number.locale(locale))
  }

  private func message(for error: Error) -> String {
    if let formatterError = error as? TodayPresentationFormatterError {
      switch formatterError {
      case .invalidRequirement:
        return "Requirement unavailable."
      case .invalidProgress, .invalidStreak, .inconsistentSnapshot:
        return "Today facts unavailable."
      }
    }
    if let evaluationError = error as? BucketEvaluationError {
      switch evaluationError {
      case .unsupportedCadence:
        return "Cadence unavailable."
      case .invalidRequirement:
        return "Requirement unavailable."
      default:
        return "Today facts unavailable."
      }
    }
    if let localizedError = error as? LocalizedError,
      let description = localizedError.errorDescription,
      !description.isEmpty
    {
      return description
    }
    return "Today facts unavailable."
  }
}

private enum TodayPresentationFormatterError: Error {
  case invalidRequirement
  case invalidProgress
  case invalidStreak
  case inconsistentSnapshot
}
