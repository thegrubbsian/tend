import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Normative bucket evaluation examples")
struct BucketEvaluationExampleTests {
  @Test("grace save settles the back-filled Tuesday as met")
  func graceSaveSettlesBackFilledTuesdayAsMet() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      name: "Piano",
      cadence: .daily,
      target: 30,
      unit: "min",
      activityStart: "2024-01-01T00:00:00Z"
    )

    try reconcile(habit, in: context, at: "2024-01-01T12:00:00Z")
    try addEntry(
      amount: 30,
      timestamp: "2024-01-01T18:00:00Z",
      to: bucket("day:2024-01-01", for: habit, in: context),
      habit: habit,
      context: context
    )
    try reconcile(habit, in: context, at: "2024-01-03T08:00:00Z")
    try addEntry(
      amount: 30,
      timestamp: "2024-01-03T08:00:00Z",
      to: bucket("day:2024-01-02", for: habit, in: context),
      habit: habit,
      context: context
    )
    try reconcile(habit, in: context, at: "2024-01-04T00:00:00Z")

    let monday = try bucket("day:2024-01-01", for: habit, in: context)
    let tuesday = try bucket("day:2024-01-02", for: habit, in: context)
    #expect(monday.verdictRawValue == BucketVerdict.met.rawValue)
    #expect(monday.finalizedAt == (try instant("2024-01-03T00:00:00Z")))
    #expect(tuesday.verdictRawValue == BucketVerdict.met.rawValue)
    #expect(tuesday.finalizedAt == (try instant("2024-01-04T00:00:00Z")))
    #expect(tuesday.targetSnapshot == 30)
    #expect(tuesday.unitSnapshot == "min")
  }

  @Test("fossilized miss never changes after Tuesday settles")
  func fossilizedMissNeverChangesAfterTuesdaySettles() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      name: "Piano",
      cadence: .daily,
      target: 30,
      unit: "min",
      activityStart: "2024-01-02T00:00:00Z"
    )

    try reconcile(habit, in: context, at: "2024-01-04T00:00:00Z")
    let tuesday = try bucket("day:2024-01-02", for: habit, in: context)
    let settledAt = tuesday.finalizedAt
    let verdict = tuesday.verdictRawValue
    let target = tuesday.targetSnapshot
    let unit = tuesday.unitSnapshot
    try reconcile(habit, in: context, at: "2024-01-05T12:00:00Z")

    #expect(verdict == BucketVerdict.missed.rawValue)
    #expect(settledAt == (try instant("2024-01-04T00:00:00Z")))
    #expect(tuesday.verdictRawValue == verdict)
    #expect(tuesday.finalizedAt == settledAt)
    #expect(tuesday.targetSnapshot == target)
    #expect(tuesday.unitSnapshot == unit)
  }

  @Test("multi-count bucket misses when two of three are logged")
  func multiCountBucketMissesWhenTwoOfThreeAreLogged() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      name: "Meditation",
      cadence: .daily,
      target: 3,
      unit: "times",
      activityStart: "2024-01-01T00:00:00Z"
    )

    try reconcile(habit, in: context, at: "2024-01-01T12:00:00Z")
    let monday = try bucket("day:2024-01-01", for: habit, in: context)
    try addEntry(
      amount: 1,
      timestamp: "2024-01-01T08:00:00Z",
      to: monday,
      habit: habit,
      context: context
    )
    try addEntry(
      amount: 1,
      timestamp: "2024-01-01T20:00:00Z",
      to: monday,
      habit: habit,
      context: context
    )
    try reconcile(habit, in: context, at: "2024-01-03T00:00:00Z")

    #expect(monday.entries?.map(\.amount).reduce(0, +) == 2)
    #expect(monday.verdictRawValue == BucketVerdict.missed.rawValue)
    #expect(monday.targetSnapshot == 3)
    #expect(monday.finalizedAt == (try instant("2024-01-03T00:00:00Z")))
  }

  @Test("weekly completion accepts a Thursday entry despite Wednesday pinning")
  func weeklyCompletionAcceptsThursdayEntryDespiteWednesdayPinning() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      name: "LinkedIn",
      cadence: .weekly,
      target: 1,
      unit: "post",
      pinnedWeekdays: .wednesday,
      activityStart: "2024-01-01T00:00:00Z"
    )

    try reconcile(habit, in: context, at: "2024-01-04T12:00:00Z")
    let week = try bucket("week:2024-01-01", for: habit, in: context)
    try addEntry(
      amount: 1,
      timestamp: "2024-01-04T12:00:00Z",
      to: week,
      habit: habit,
      context: context
    )
    try reconcile(habit, in: context, at: "2024-01-09T00:00:00Z")

    #expect(habit.pinnedWeekdaysRawValue == PinnedWeekdays.wednesday.rawValue)
    #expect(week.verdictRawValue == BucketVerdict.met.rawValue)
    #expect(week.targetSnapshot == 1)
    #expect(week.finalizedAt == (try instant("2024-01-09T00:00:00Z")))
  }

  @Test("target raise preserves old finals and governs the ninth in grace")
  func targetRaisePreservesOldFinalsAndGovernsNinthInGrace() throws {
    let context = try makeContext()
    let habit = try insertHabit(
      in: context,
      name: "Piano",
      cadence: .daily,
      target: 20,
      unit: "min",
      activityStart: "2024-01-08T00:00:00Z"
    )

    try reconcile(habit, in: context, at: "2024-01-08T12:00:00Z")
    let eighth = try bucket("day:2024-01-08", for: habit, in: context)
    try addEntry(
      amount: 20,
      timestamp: "2024-01-08T12:00:00Z",
      to: eighth,
      habit: habit,
      context: context
    )
    try reconcile(habit, in: context, at: "2024-01-10T12:00:00Z")

    habit.target = 30
    try context.save()
    let ninth = try bucket("day:2024-01-09", for: habit, in: context)
    try addEntry(
      amount: 25,
      timestamp: "2024-01-10T13:00:00Z",
      to: ninth,
      habit: habit,
      context: context
    )
    try reconcile(habit, in: context, at: "2024-01-11T00:00:00Z")

    #expect(eighth.verdictRawValue == BucketVerdict.met.rawValue)
    #expect(eighth.targetSnapshot == 20)
    #expect(eighth.unitSnapshot == "min")
    #expect(ninth.verdictRawValue == BucketVerdict.missed.rawValue)
    #expect(ninth.targetSnapshot == 30)
    #expect(ninth.unitSnapshot == "min")
    #expect(ninth.finalizedAt == (try instant("2024-01-11T00:00:00Z")))
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func insertHabit(
    in context: ModelContext,
    name: String,
    cadence: HabitCadence,
    target: Int,
    unit: String,
    pinnedWeekdays: PinnedWeekdays = .none,
    activityStart: String
  ) throws -> Habit {
    let habit = Habit(
      name: name,
      cadence: cadence,
      target: target,
      unit: unit,
      pinnedWeekdays: pinnedWeekdays
    )
    habit.activityPeriods = [
      HabitActivityPeriod(startedAt: try instant(activityStart))
    ]
    context.insert(habit)
    try context.save()
    return habit
  }

  private func reconcile(
    _ habit: Habit,
    in context: ModelContext,
    at value: String
  ) throws {
    try BucketReconciler(context: context).reconcile(
      habit: habit,
      at: instant(value),
      timeZone: timeZone("UTC")
    )
  }

  private func addEntry(
    amount: Int,
    timestamp: String,
    to bucket: HabitBucket,
    habit: Habit,
    context: ModelContext
  ) throws {
    context.insert(
      LogEntry(
        timestamp: try instant(timestamp),
        amount: amount,
        habit: habit,
        bucket: bucket
      ))
    try context.save()
  }

  private func bucket(
    _ key: String,
    for habit: Habit,
    in context: ModelContext
  ) throws -> HabitBucket {
    let habitIdentifier = habit.persistentModelID
    return try #require(
      context.fetch(FetchDescriptor<HabitBucket>()).first {
        $0.habit?.persistentModelID == habitIdentifier && $0.periodKey == key
      })
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private func timeZone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }
}
