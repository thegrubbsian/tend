import Foundation
import SwiftData

public enum JournalDayGardenState: Equatable, Sendable {
  case met
  case missed
  case open
  case grace
  case exempt
  case unavailable
}

public struct JournalDayGardenRow: Equatable, Sendable {
  public let habitID: UUID
  public let name: String
  public let cadence: HabitCadence?
  public let periodKey: String
  public let periodStart: Date
  public let periodEnd: Date
  public let state: JournalDayGardenState
  public let progress: Int?
  public let target: Int?
  public let unit: String?
  public let isRequirementMet: Bool?

  public init(
    habitID: UUID,
    name: String,
    cadence: HabitCadence?,
    periodKey: String,
    periodStart: Date,
    periodEnd: Date,
    state: JournalDayGardenState,
    progress: Int? = nil,
    target: Int? = nil,
    unit: String? = nil,
    isRequirementMet: Bool? = nil
  ) {
    self.habitID = habitID
    self.name = name
    self.cadence = cadence
    self.periodKey = periodKey
    self.periodStart = periodStart
    self.periodEnd = periodEnd
    self.state = state
    self.progress = progress
    self.target = target
    self.unit = unit
    self.isRequirementMet = isRequirementMet
  }
}

@MainActor
public final class JournalDayGardenQuery {
  private let context: ModelContext
  private let projector = HabitDayProjector()

  public init(context: ModelContext) {
    self.context = context
  }

  public func rows(
    for habits: [Habit],
    on day: LocalDate,
    at instant: Date,
    timeZone: TimeZone
  ) -> [JournalDayGardenRow] {
    guard let currentDay = try? localDate(containing: instant, timeZone: timeZone),
      day <= currentDay
    else {
      return []
    }

    let orderedHabits = habits.sorted(by: isOrdered)
    var rows: [JournalDayGardenRow] = []
    rows.reserveCapacity(orderedHabits.count)
    for habit in orderedHabits {
      do {
        if let row = try row(
          for: habit,
          on: day,
          at: instant,
          timeZone: timeZone
        ) {
          rows.append(row)
        }
      } catch {
        rows.append(unavailableRow(for: habit, on: day, at: instant, timeZone: timeZone))
      }
    }
    return rows
  }

  private func row(
    for habit: Habit,
    on day: LocalDate,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> JournalDayGardenRow? {
    guard isPersisted(habit) else {
      throw HabitStreakComputationError.detachedHabit
    }
    guard let cadence = HabitCadence(rawValue: habit.cadenceRawValue) else {
      throw BucketEvaluationError.unsupportedCadence(habit.cadenceRawValue)
    }
    guard habit.target > 0 else {
      throw BucketEvaluationError.invalidRequirement(habit.target)
    }

    let dayStart = try day.start(in: timeZone)
    let dayEnd = try day.next().start(in: timeZone)
    let activityPeriods = try validatedActivityPeriods(for: habit)
    guard
      activityPeriods.contains(where: {
        overlaps($0, start: dayStart, end: dayEnd)
      })
    else {
      return nil
    }

    try HabitRelationshipValidator(context: context).validateGraph(for: habit)
    let schedule = CalendarBucketSchedule(timeZone: timeZone)
    let period = try schedule.period(containing: dayStart, cadence: cadence)
    let creationPeriod = try schedule.period(containing: habit.createdAt, cadence: cadence)
    let bucket = try bucket(for: habit, periodKey: period.key)
    let projection = try projector.project(
      period,
      habit: habit,
      bucket: bucket,
      activityPeriods: activityPeriods,
      creationPeriod: creationPeriod,
      instant: instant,
      timeZone: timeZone
    )
    guard let state = gardenState(for: projection.state) else { return nil }
    return JournalDayGardenRow(
      habitID: habit.id,
      name: habit.name,
      cadence: cadence,
      periodKey: projection.periodKey,
      periodStart: projection.periodStart,
      periodEnd: projection.periodEnd,
      state: state,
      progress: projection.progress,
      target: projection.target,
      unit: projection.unit,
      isRequirementMet: projection.isRequirementMet
    )
  }

  private func bucket(for habit: Habit, periodKey: String) throws -> HabitBucket? {
    let habitIdentifier = habit.persistentModelID
    let descriptor = FetchDescriptor<HabitBucket>(
      predicate: #Predicate<HabitBucket> { bucket in
        bucket.habit?.persistentModelID == habitIdentifier
          && bucket.periodKey == periodKey
      })
    let buckets = try context.fetch(descriptor).sorted {
      $0.id.uuidString < $1.id.uuidString
    }
    guard buckets.count <= 1 else {
      throw HabitStreakComputationError.duplicatePeriodKey(periodKey)
    }
    return buckets.first
  }

  private func validatedActivityPeriods(for habit: Habit) throws -> [HabitActivityPeriod] {
    let habitIdentifier = habit.persistentModelID
    let descriptor = FetchDescriptor<HabitActivityPeriod>(
      predicate: #Predicate<HabitActivityPeriod> { period in
        period.habit?.persistentModelID == habitIdentifier
      })
    var periods = try context.fetch(descriptor)
    var identifiers = Set(periods.map(\.persistentModelID))
    for period in habit.activityPeriods ?? []
    where identifiers.insert(period.persistentModelID).inserted {
      periods.append(period)
    }
    periods.sort {
      if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
      if $0.endedAt != $1.endedAt {
        return ($0.endedAt ?? .distantFuture) < ($1.endedAt ?? .distantFuture)
      }
      return $0.id.uuidString < $1.id.uuidString
    }

    var previousEnd: Date?
    var foundOpen = false
    for period in periods {
      guard isPersisted(period),
        period.habit?.persistentModelID == habitIdentifier
      else {
        throw HabitActivityOperationError.invalidActivityChronology
      }
      if let endedAt = period.endedAt {
        guard endedAt >= period.startedAt,
          !foundOpen,
          previousEnd.map({ period.startedAt >= $0 }) ?? true
        else {
          throw HabitActivityOperationError.invalidActivityChronology
        }
        previousEnd = endedAt
      } else {
        guard !foundOpen,
          previousEnd.map({ period.startedAt >= $0 }) ?? true
        else {
          throw HabitActivityOperationError.multipleOpenActivityPeriods
        }
        foundOpen = true
      }
    }
    if habit.isActive, !foundOpen {
      throw HabitActivityOperationError.missingOpenActivityPeriod
    }
    if !habit.isActive, foundOpen {
      throw HabitActivityOperationError.unexpectedOpenActivityPeriod
    }
    return periods
  }

  private func gardenState(
    for state: HabitDayProjectionState
  ) -> JournalDayGardenState? {
    switch state {
    case .met: .met
    case .missed: .missed
    case .open: .open
    case .grace: .grace
    case .exempt: .exempt
    case .inactive, .beforeCreation, .future: nil
    }
  }

  private func unavailableRow(
    for habit: Habit,
    on day: LocalDate,
    at instant: Date,
    timeZone: TimeZone
  ) -> JournalDayGardenRow {
    let start = (try? day.start(in: timeZone)) ?? instant
    let end = (try? day.next().start(in: timeZone)) ?? start
    return JournalDayGardenRow(
      habitID: habit.id,
      name: habit.name,
      cadence: HabitCadence(rawValue: habit.cadenceRawValue),
      periodKey: "",
      periodStart: start,
      periodEnd: end,
      state: .unavailable
    )
  }

  private func localDate(containing instant: Date, timeZone: TimeZone) throws -> LocalDate {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.era, .year, .month, .day], from: instant)
    guard components.era == 1,
      let year = components.year,
      let month = components.month,
      let day = components.day,
      let localDate = LocalDate(year: year, month: month, day: day)
    else {
      throw LocalDateError.unrepresentableDate
    }
    return localDate
  }

  private func overlaps(
    _ activityPeriod: HabitActivityPeriod,
    start: Date,
    end: Date
  ) -> Bool {
    let activityEnd = activityPeriod.endedAt ?? .distantFuture
    guard activityEnd > activityPeriod.startedAt else { return false }
    return activityPeriod.startedAt < end && activityEnd > start
  }

  private func isOrdered(_ lhs: Habit, _ rhs: Habit) -> Bool {
    let nameOrder = lhs.name.compare(
      rhs.name,
      options: [.caseInsensitive, .diacriticInsensitive],
      range: nil,
      locale: Locale(identifier: "en_US_POSIX")
    )
    if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  private func isPersisted<T>(_ model: T) -> Bool where T: PersistentModel {
    model.modelContext == context && model.persistentModelID.storeIdentifier != nil
      && !model.isDeleted
  }
}
