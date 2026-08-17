import Foundation
import SwiftData

public struct GoalEntryIdentity: RawRepresentable, Equatable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }
}

public struct GoalReadingIdentity: RawRepresentable, Equatable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }
}

public struct GoalDetailMetadata: Equatable, Sendable {
  public let id: UUID
  public let name: String
  public let kind: GoalKind
  public let target: Int
  public let unit: String
  public let baseline: Int?
  public let deadline: GoalDate?
  public let createdAt: Date
  public let closure: GoalClosure?

  public init(
    id: UUID,
    name: String,
    kind: GoalKind,
    target: Int,
    unit: String,
    baseline: Int?,
    deadline: GoalDate?,
    createdAt: Date,
    closure: GoalClosure?
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.target = target
    self.unit = unit
    self.baseline = baseline
    self.deadline = deadline
    self.createdAt = createdAt
    self.closure = closure
  }
}

public struct GoalDetailEntry: Equatable, Sendable {
  public let id: GoalEntryIdentity
  public let assignedDate: GoalDate
  public let amount: Int
  public let appendedAt: Date
  public let appendSequence: Int
  public let isDeleteEligible: Bool

  public init(
    id: GoalEntryIdentity,
    assignedDate: GoalDate,
    amount: Int,
    appendedAt: Date,
    appendSequence: Int,
    isDeleteEligible: Bool
  ) {
    self.id = id
    self.assignedDate = assignedDate
    self.amount = amount
    self.appendedAt = appendedAt
    self.appendSequence = appendSequence
    self.isDeleteEligible = isDeleteEligible
  }
}

public struct GoalDetailReading: Equatable, Sendable {
  public let id: GoalReadingIdentity
  public let assignedDate: GoalDate
  public let value: Int
  public let appendedAt: Date
  public let appendSequence: Int
  public let isDeleteEligible: Bool
  public let isEffective: Bool

  public init(
    id: GoalReadingIdentity,
    assignedDate: GoalDate,
    value: Int,
    appendedAt: Date,
    appendSequence: Int,
    isDeleteEligible: Bool,
    isEffective: Bool
  ) {
    self.id = id
    self.assignedDate = assignedDate
    self.value = value
    self.appendedAt = appendedAt
    self.appendSequence = appendSequence
    self.isDeleteEligible = isDeleteEligible
    self.isEffective = isEffective
  }
}

public enum GoalDetailHistoryItem: Equatable, Sendable {
  case entry(GoalDetailEntry)
  case reading(GoalDetailReading)
}

public struct GoalDetailSnapshot: Equatable, Sendable {
  public let metadata: GoalDetailMetadata
  public let progress: GoalProgressSnapshot
  public let standing: GoalStandingSnapshot?
  public let availableAppendDestinations: [GoalProgressDestination]
  public let history: [GoalDetailHistoryItem]

  public init(
    metadata: GoalDetailMetadata,
    progress: GoalProgressSnapshot,
    standing: GoalStandingSnapshot?,
    availableAppendDestinations: [GoalProgressDestination],
    history: [GoalDetailHistoryItem]
  ) {
    self.metadata = metadata
    self.progress = progress
    self.standing = standing
    self.availableAppendDestinations = availableAppendDestinations
    self.history = history
  }
}

public enum GoalDetailQueryError: Error, Equatable, Sendable {
  case progress(GoalProgressComputationError)
  case standing(GoalStandingComputationError)
  case invalidLocalDay
  case duplicateEntryIdentity(GoalEntryIdentity)
  case duplicateReadingIdentity(GoalReadingIdentity)
  case invalidEntryAppendInstant(GoalEntryIdentity)
  case invalidReadingAppendInstant(GoalReadingIdentity)
  case historyBeforeCreation(GoalDate)
  case historyAfterEvaluation(GoalDate)
}

@MainActor
public final class GoalDetailQuery {
  private let context: ModelContext

  public init(context: ModelContext) {
    self.context = context
  }

  public func snapshot(
    for goal: Goal,
    at instant: Date,
    calendar: Calendar,
    timeZone: TimeZone
  ) throws -> GoalDetailSnapshot {
    let progress: GoalProgressSnapshot
    do {
      progress = try GoalProgressComputation(context: context).snapshot(for: goal)
    } catch let error as GoalProgressComputationError {
      throw GoalDetailQueryError.progress(error)
    }

    let standing: GoalStandingSnapshot?
    do {
      standing = try GoalStandingComputation().snapshot(
        for: goal,
        progress: progress,
        at: instant,
        calendar: calendar,
        timeZone: timeZone
      )
    } catch let error as GoalStandingComputationError {
      throw GoalDetailQueryError.standing(error)
    }

    let kind = try validatedKind(of: goal)
    let closure = try validatedClosure(of: goal)
    let deadline = goal.deadlineKey.flatMap(GoalDate.init(rawValue:))
    let localDays: GoalProgressLocalDayWindow
    do {
      localDays = try GoalProgressLocalDayEligibility.window(
        createdAt: goal.createdAt,
        at: instant,
        timeZone: timeZone
      )
    } catch {
      throw GoalDetailQueryError.invalidLocalDay
    }

    let isOpen = closure == nil
    let history = try validatedHistory(
      for: goal,
      kind: kind,
      progress: progress,
      localDays: localDays,
      mutationsAllowed: isOpen
    )

    return GoalDetailSnapshot(
      metadata: GoalDetailMetadata(
        id: goal.id,
        name: goal.name,
        kind: kind,
        target: goal.target,
        unit: goal.unit,
        baseline: goal.baseline,
        deadline: deadline,
        createdAt: goal.createdAt,
        closure: closure
      ),
      progress: progress,
      standing: standing,
      availableAppendDestinations: isOpen ? localDays.availableAppendDestinations : [],
      history: history
    )
  }

  private func validatedKind(of goal: Goal) throws -> GoalKind {
    guard let kind = GoalKind(rawValue: goal.kindRawValue) else {
      throw GoalDetailQueryError.progress(.invalidGoalKind(goal.kindRawValue))
    }
    return kind
  }

  private func validatedClosure(of goal: Goal) throws -> GoalClosure? {
    do {
      return try goal.checkedClosure
    } catch GoalClosureError.unsupportedRawValue(let rawValue) {
      throw GoalDetailQueryError.standing(.invalidClosure(rawValue))
    }
  }

  private func validatedHistory(
    for goal: Goal,
    kind: GoalKind,
    progress: GoalProgressSnapshot,
    localDays: GoalProgressLocalDayWindow,
    mutationsAllowed: Bool
  ) throws -> [GoalDetailHistoryItem] {
    switch kind {
    case .accumulate:
      return try validatedEntries(
        goal.entries ?? [],
        localDays: localDays,
        mutationsAllowed: mutationsAllowed
      ).map(GoalDetailHistoryItem.entry)
    case .measure:
      let effectiveID: UUID?
      if case .measure(let snapshot) = progress {
        effectiveID = snapshot.effectiveReadingID
      } else {
        effectiveID = nil
      }
      return try validatedReadings(
        goal.readings ?? [],
        effectiveID: effectiveID,
        localDays: localDays,
        mutationsAllowed: mutationsAllowed
      ).map(GoalDetailHistoryItem.reading)
    }
  }

  private func validatedEntries(
    _ entries: [GoalEntry],
    localDays: GoalProgressLocalDayWindow,
    mutationsAllowed: Bool
  ) throws -> [GoalDetailEntry] {
    var observed = Set<GoalEntryIdentity>()
    observed.reserveCapacity(entries.count)
    var result = [GoalDetailEntry]()
    result.reserveCapacity(entries.count)

    for entry in entries {
      let id = GoalEntryIdentity(rawValue: entry.id)
      guard observed.insert(id).inserted else {
        throw GoalDetailQueryError.duplicateEntryIdentity(id)
      }
      guard entry.appendedAt.timeIntervalSinceReferenceDate.isFinite else {
        throw GoalDetailQueryError.invalidEntryAppendInstant(id)
      }
      guard let assignedDate = GoalDate(rawValue: entry.assignedDateKey) else {
        throw GoalDetailQueryError.progress(.invalidAssignedDate(entry.assignedDateKey))
      }
      try validateChronology(assignedDate, localDays: localDays)
      result.append(
        GoalDetailEntry(
          id: id,
          assignedDate: assignedDate,
          amount: entry.amount,
          appendedAt: entry.appendedAt,
          appendSequence: entry.appendSequence,
          isDeleteEligible: mutationsAllowed && localDays.isDeleteEligible(assignedDate)
        ))
    }

    result.sort(by: historyPrecedes)
    return result
  }

  private func validatedReadings(
    _ readings: [GoalReading],
    effectiveID: UUID?,
    localDays: GoalProgressLocalDayWindow,
    mutationsAllowed: Bool
  ) throws -> [GoalDetailReading] {
    var observed = Set<GoalReadingIdentity>()
    observed.reserveCapacity(readings.count)
    var result = [GoalDetailReading]()
    result.reserveCapacity(readings.count)

    for reading in readings {
      let id = GoalReadingIdentity(rawValue: reading.id)
      guard observed.insert(id).inserted else {
        throw GoalDetailQueryError.duplicateReadingIdentity(id)
      }
      guard reading.appendedAt.timeIntervalSinceReferenceDate.isFinite else {
        throw GoalDetailQueryError.invalidReadingAppendInstant(id)
      }
      guard let assignedDate = GoalDate(rawValue: reading.assignedDateKey) else {
        throw GoalDetailQueryError.progress(.invalidAssignedDate(reading.assignedDateKey))
      }
      try validateChronology(assignedDate, localDays: localDays)
      result.append(
        GoalDetailReading(
          id: id,
          assignedDate: assignedDate,
          value: reading.value,
          appendedAt: reading.appendedAt,
          appendSequence: reading.appendSequence,
          isDeleteEligible: mutationsAllowed && localDays.isDeleteEligible(assignedDate),
          isEffective: reading.id == effectiveID
        ))
    }

    result.sort(by: historyPrecedes)
    return result
  }

  private func validateChronology(
    _ assignedDate: GoalDate,
    localDays: GoalProgressLocalDayWindow
  ) throws {
    guard assignedDate >= localDays.creationDate else {
      throw GoalDetailQueryError.historyBeforeCreation(assignedDate)
    }
    guard assignedDate <= localDays.today else {
      throw GoalDetailQueryError.historyAfterEvaluation(assignedDate)
    }
  }

  private func historyPrecedes(_ lhs: GoalDetailEntry, _ rhs: GoalDetailEntry) -> Bool {
    if lhs.assignedDate != rhs.assignedDate {
      return lhs.assignedDate > rhs.assignedDate
    }
    return lhs.appendSequence > rhs.appendSequence
  }

  private func historyPrecedes(_ lhs: GoalDetailReading, _ rhs: GoalDetailReading) -> Bool {
    if lhs.assignedDate != rhs.assignedDate {
      return lhs.assignedDate > rhs.assignedDate
    }
    return lhs.appendSequence > rhs.appendSequence
  }
}
