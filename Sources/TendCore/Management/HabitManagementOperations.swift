import Foundation
import SwiftData

public struct HabitEditableFields: Equatable, Sendable {
  public let name: String
  public let target: Int
  public let unit: String
  public let pinnedWeekdays: PinnedWeekdays
  public let reminderTime: ReminderTime?

  public init(
    name: String,
    target: Int,
    unit: String = "times",
    pinnedWeekdays: PinnedWeekdays = .none,
    reminderTime: ReminderTime? = nil
  ) {
    self.name = name
    self.target = target
    self.unit = unit
    self.pinnedWeekdays = pinnedWeekdays
    self.reminderTime = reminderTime
  }
}

public enum HabitManagementOperationError: Error, Equatable, Sendable {
  case emptyName
  case invalidTarget(Int)
  case emptyUnit
  case detachedHabit
  case deletedHabit
  case foreignContext
}

@MainActor
public final class HabitManagementOperations {
  private let context: ModelContext
  private let saveContext: () throws -> Void
  private let reconciler: BucketReconciler

  public init(context: ModelContext) {
    self.context = context
    reconciler = BucketReconciler(context: context)
    saveContext = { try context.save() }
  }

  init(context: ModelContext, save: @escaping () throws -> Void) {
    self.context = context
    reconciler = BucketReconciler(context: context)
    saveContext = save
  }

  public func create(
    fields: HabitEditableFields,
    cadence: HabitCadence,
    at instant: Date,
    timeZone: TimeZone
  ) throws -> Habit {
    let fields = try validated(fields, cadence: cadence)
    let period = try CalendarBucketSchedule(timeZone: timeZone).period(
      containing: instant,
      cadence: cadence
    )
    let habit = Habit(
      name: fields.name,
      cadence: cadence,
      target: fields.target,
      unit: fields.unit,
      pinnedWeekdays: fields.pinnedWeekdays,
      reminderTime: fields.reminderTime,
      createdAt: instant
    )
    habit.activityPeriods = [
      HabitActivityPeriod(startedAt: instant, habit: habit)
    ]
    habit.buckets = [
      HabitBucket(
        periodKey: period.key,
        startAt: period.start,
        endAt: period.end,
        cadence: cadence,
        habit: habit
      )
    ]
    context.insert(habit)
    do {
      try saveContext()
      return habit
    } catch {
      context.rollback()
      throw error
    }
  }

  public func update(
    _ habit: Habit,
    fields: HabitEditableFields,
    at instant: Date,
    timeZone: TimeZone
  ) throws {
    try validateOwnership(of: habit)
    guard let cadence = HabitCadence(rawValue: habit.cadenceRawValue) else {
      throw BucketEvaluationError.unsupportedCadence(habit.cadenceRawValue)
    }
    let fields = try validated(fields, cadence: cadence)
    try reconciler.reconcile(habit: habit, at: instant, timeZone: timeZone)
    let previous = (
      name: habit.name,
      target: habit.target,
      unit: habit.unit,
      pinnedWeekdaysRawValue: habit.pinnedWeekdaysRawValue,
      reminderMinuteOfDay: habit.reminderMinuteOfDay
    )

    habit.name = fields.name
    habit.target = fields.target
    habit.unit = fields.unit
    habit.pinnedWeekdaysRawValue = fields.pinnedWeekdays.rawValue
    habit.reminderMinuteOfDay = fields.reminderTime?.rawValue
    do {
      try saveContext()
    } catch {
      habit.name = previous.name
      habit.target = previous.target
      habit.unit = previous.unit
      habit.pinnedWeekdaysRawValue = previous.pinnedWeekdaysRawValue
      habit.reminderMinuteOfDay = previous.reminderMinuteOfDay
      context.rollback()
      throw error
    }
  }

  public func delete(_ habit: Habit) throws {
    try validateOwnership(of: habit)
    let activityPeriods = habit.activityPeriods ?? []
    let buckets = habit.buckets ?? []
    let entries = habit.entries ?? []

    context.delete(habit)
    do {
      try saveContext()
    } catch {
      // SwiftData cannot roll back a deleted cascade while inverse
      // relationships still expose future backing data.
      habit.activityPeriods = []
      habit.buckets = []
      habit.entries = []
      for activityPeriod in activityPeriods {
        activityPeriod.habit = nil
      }
      for entry in entries {
        entry.habit = nil
        entry.bucket = nil
      }
      for bucket in buckets {
        bucket.habit = nil
        bucket.entries = []
      }
      context.rollback()
      throw error
    }
  }

  private func validateOwnership(of habit: Habit) throws {
    if habit.modelContext === context {
      guard !habit.isDeleted else {
        throw HabitManagementOperationError.deletedHabit
      }
      guard habit.persistentModelID.storeIdentifier != nil else {
        throw HabitManagementOperationError.detachedHabit
      }
      return
    }
    if habit.modelContext != nil {
      throw HabitManagementOperationError.foreignContext
    }
    if habit.persistentModelID.storeIdentifier != nil {
      throw HabitManagementOperationError.deletedHabit
    }
    throw HabitManagementOperationError.detachedHabit
  }

  private func validated(
    _ fields: HabitEditableFields,
    cadence: HabitCadence
  ) throws -> HabitEditableFields {
    let name = normalized(fields.name)
    guard !name.isEmpty else {
      throw HabitManagementOperationError.emptyName
    }
    guard fields.target > 0 else {
      throw HabitManagementOperationError.invalidTarget(fields.target)
    }
    let unit = normalized(fields.unit)
    guard !unit.isEmpty else {
      throw HabitManagementOperationError.emptyUnit
    }
    return HabitEditableFields(
      name: name,
      target: fields.target,
      unit: unit,
      pinnedWeekdays: cadence == .daily ? .none : fields.pinnedWeekdays,
      reminderTime: fields.reminderTime
    )
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
