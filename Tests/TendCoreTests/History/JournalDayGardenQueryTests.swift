import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Journal day garden query")
struct JournalDayGardenQueryTests {
  @Test("daily rows report final results and partial progress without finalizing")
  func dailyRowsReportFinalResultsWithoutMutation() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let day = try localDate("2024-01-01")
    let now = try instant("2024-01-03T12:00:00Z")
    let met = try insertHabit(
      context: context,
      id: uuid(2),
      name: "Build",
      cadence: .daily,
      target: 2,
      unit: "sessions",
      day: day,
      timeZone: zone,
      progress: 2,
      activityEnd: try instant("2024-01-02T00:00:00Z")
    )
    let missed = try insertHabit(
      context: context,
      id: uuid(1),
      name: "Read",
      cadence: .daily,
      target: 3,
      unit: "pages",
      day: day,
      timeZone: zone,
      progress: 1,
      activityEnd: try instant("2024-01-02T00:00:00Z")
    )
    let finalizedAt = try instant("2024-01-02T00:00:00Z")
    met.bucket.finalizedAt = finalizedAt
    met.bucket.verdictRawValue = BucketVerdict.met.rawValue
    met.bucket.targetSnapshot = 2
    met.bucket.unitSnapshot = "sessions"
    try context.save()
    let bucketCount = try context.fetchCount(FetchDescriptor<HabitBucket>())
    let entryCount = try context.fetchCount(FetchDescriptor<LogEntry>())
    #expect(context.hasChanges == false)

    let rows = JournalDayGardenQuery(context: context).rows(
      for: [missed.habit, met.habit],
      on: day,
      at: now,
      timeZone: zone
    )

    #expect(rows.map(\.habitID) == [met.habit.id, missed.habit.id])
    #expect(rows.map(\.state) == [.met, .missed])
    #expect(rows.map(\.progress) == [2, 1])
    #expect(rows.map(\.target) == [2, 3])
    #expect(rows.map(\.unit) == ["sessions", "pages"])
    #expect(rows.map(\.isRequirementMet) == [true, false])
    #expect(met.bucket.finalizedAt == finalizedAt)
    #expect(met.bucket.verdictRawValue == BucketVerdict.met.rawValue)
    #expect(met.bucket.targetSnapshot == 2)
    #expect(met.bucket.unitSnapshot == "sessions")
    #expect(missed.bucket.finalizedAt == nil)
    #expect(missed.bucket.verdictRawValue == nil)
    #expect(try context.fetchCount(FetchDescriptor<HabitBucket>()) == bucketCount)
    #expect(try context.fetchCount(FetchDescriptor<LogEntry>()) == entryCount)
    #expect(context.hasChanges == false)
  }

  @Test("open, grace, and exempt rows retain their truthful Almanac state")
  func provisionalAndExemptRowsKeepTheirState() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let first = try localDate("2024-01-01")
    let second = try localDate("2024-01-02")
    let grace = try insertHabit(
      context: context,
      id: uuid(1),
      name: "Grace",
      cadence: .daily,
      target: 2,
      unit: "times",
      day: first,
      timeZone: zone,
      progress: 1,
      activityEnd: try instant("2024-01-02T00:00:00Z")
    )
    let open = try insertHabit(
      context: context,
      id: uuid(2),
      name: "Open",
      cadence: .daily,
      target: 2,
      unit: "times",
      day: second,
      timeZone: zone,
      progress: 2
    )
    let exempt = try insertHabit(
      context: context,
      id: uuid(3),
      name: "Exempt",
      cadence: .daily,
      target: 1,
      unit: "time",
      day: second,
      timeZone: zone,
      progress: 0,
      activityEnd: try instant("2024-01-02T18:00:00Z"),
      isExempt: true
    )
    let now = try instant("2024-01-02T12:00:00Z")
    let query = JournalDayGardenQuery(context: context)

    let graceRows = query.rows(
      for: [grace.habit], on: first, at: now, timeZone: zone)
    let currentRows = query.rows(
      for: [open.habit, exempt.habit], on: second, at: now, timeZone: zone)

    #expect(graceRows.map(\.state) == [.grace])
    #expect(graceRows.first?.progress == 1)
    #expect(graceRows.first?.isRequirementMet == false)
    #expect(currentRows.map(\.state) == [.exempt, .open])
    #expect(currentRows.first?.progress == nil)
    #expect(currentRows.first?.target == nil)
    #expect(currentRows.last?.progress == 2)
    #expect(currentRows.last?.isRequirementMet == true)
  }

  @Test("weekly rows use the bucket containing the written day")
  func weeklyRowsUseContainingBucket() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let monday = try localDate("2024-01-01")
    let wednesday = try localDate("2024-01-03")
    let weekly = try insertHabit(
      context: context,
      id: uuid(1),
      name: "Publish",
      cadence: .weekly,
      target: 3,
      unit: "posts",
      day: monday,
      timeZone: zone,
      progress: 2
    )

    let row = try #require(
      JournalDayGardenQuery(context: context).rows(
        for: [weekly.habit],
        on: wednesday,
        at: try instant("2024-01-04T12:00:00Z"),
        timeZone: zone
      ).first
    )

    #expect(row.cadence == .weekly)
    #expect(row.periodKey == "week:2024-01-01")
    #expect(row.state == .open)
    #expect(row.progress == 2)
    #expect(row.target == 3)
    #expect(row.isRequirementMet == false)
  }

  @Test("inactive, before-creation, and future days produce no rows")
  func nonActiveDaysAreExcluded() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-05T12:00:00Z")
    let inactiveDay = try localDate("2024-01-03")
    let futureDay = try localDate("2024-01-06")
    let habit = Habit(
      id: uuid(1),
      name: "Walk",
      cadence: .daily,
      target: 1,
      isActive: true,
      createdAt: try instant("2024-01-02T12:00:00Z")
    )
    let firstPeriod = HabitActivityPeriod(
      startedAt: try instant("2024-01-02T12:00:00Z"),
      endedAt: try instant("2024-01-03T00:00:00Z"),
      habit: habit
    )
    let secondPeriod = HabitActivityPeriod(
      startedAt: try instant("2024-01-04T00:00:00Z"),
      habit: habit
    )
    context.insert(habit)
    context.insert(firstPeriod)
    context.insert(secondPeriod)
    habit.activityPeriods = [firstPeriod, secondPeriod]
    try context.save()
    let query = JournalDayGardenQuery(context: context)

    #expect(
      query.rows(
        for: [habit],
        on: try localDate("2024-01-01"),
        at: now,
        timeZone: zone
      ).isEmpty
    )
    #expect(query.rows(for: [habit], on: inactiveDay, at: now, timeZone: zone).isEmpty)
    #expect(query.rows(for: [habit], on: futureDay, at: now, timeZone: zone).isEmpty)
  }

  @Test("a malformed Habit becomes unavailable without suppressing valid siblings")
  func malformedHabitIsIsolated() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let day = try localDate("2024-01-01")
    let now = try instant("2024-01-01T12:00:00Z")
    let valid = try insertHabit(
      context: context,
      id: uuid(2),
      name: "Breathe",
      cadence: .daily,
      target: 1,
      unit: "time",
      day: day,
      timeZone: zone,
      progress: 0
    )
    let malformed = Habit(
      id: uuid(1),
      name: "Stretch",
      cadence: .daily,
      target: 1,
      isActive: true,
      createdAt: now
    )
    let activity = HabitActivityPeriod(startedAt: now, habit: malformed)
    context.insert(malformed)
    context.insert(activity)
    malformed.activityPeriods = [activity]
    try context.save()

    let rows = JournalDayGardenQuery(context: context).rows(
      for: [malformed, valid.habit],
      on: day,
      at: now,
      timeZone: zone
    )

    #expect(rows.map(\.name) == ["Breathe", "Stretch"])
    #expect(rows.map(\.state) == [.open, .unavailable])
    #expect(rows.last?.progress == nil)
    #expect(rows.last?.target == nil)
  }

  @Test("DST and time-zone changes reproject the same civil bucket")
  func localContextChangesReprojectCivilBucket() throws {
    let context = try makeContext()
    let losAngeles = try timeZone("America/Los_Angeles")
    let utc = try timeZone("UTC")
    let day = try localDate("2023-12-31")
    let now = try instant("2024-01-01T00:30:00Z")
    let habit = try insertHabit(
      context: context,
      id: uuid(1),
      name: "Reflect",
      cadence: .daily,
      target: 1,
      unit: "time",
      day: day,
      timeZone: losAngeles,
      progress: 0
    )
    let springDay = try localDate("2024-03-10")
    let spring = try insertHabit(
      context: context,
      id: uuid(2),
      name: "Spring walk",
      cadence: .daily,
      target: 1,
      unit: "time",
      day: springDay,
      timeZone: losAngeles,
      progress: 0
    )
    let query = JournalDayGardenQuery(context: context)

    let pacific = try #require(
      query.rows(for: [habit.habit], on: day, at: now, timeZone: losAngeles).first)
    let universal = try #require(
      query.rows(for: [habit.habit], on: day, at: now, timeZone: utc).first)
    let springRow = try #require(
      query.rows(
        for: [spring.habit],
        on: springDay,
        at: try instant("2024-03-10T19:00:00Z"),
        timeZone: losAngeles
      ).first
    )

    #expect(pacific.state == .open)
    #expect(universal.state == .grace)
    #expect(springRow.periodEnd.timeIntervalSince(springRow.periodStart) == 23 * 60 * 60)
  }

  private struct InsertedHabit {
    let habit: Habit
    let bucket: HabitBucket
  }

  private func insertHabit(
    context: ModelContext,
    id: UUID,
    name: String,
    cadence: HabitCadence,
    target: Int,
    unit: String,
    day: LocalDate,
    timeZone: TimeZone,
    progress: Int,
    activityEnd: Date? = nil,
    isExempt: Bool = false
  ) throws -> InsertedHabit {
    let period = try CalendarBucketSchedule(timeZone: timeZone).period(
      containing: day.start(in: timeZone),
      cadence: cadence
    )
    let activityStart = period.start.addingTimeInterval(60)
    let habit = Habit(
      id: id,
      name: name,
      cadence: cadence,
      target: target,
      unit: unit,
      isActive: activityEnd == nil,
      createdAt: activityStart
    )
    let activity = HabitActivityPeriod(
      startedAt: activityStart,
      endedAt: activityEnd,
      habit: habit
    )
    let bucket = HabitBucket(
      periodKey: period.key,
      startAt: period.start,
      endAt: period.end,
      cadence: cadence,
      isExempt: isExempt,
      habit: habit
    )
    var entries: [LogEntry] = []
    if progress > 0 {
      let entry = LogEntry(
        timestamp: activityStart,
        amount: progress,
        habit: habit,
        bucket: bucket
      )
      entries.append(entry)
      context.insert(entry)
    }
    context.insert(habit)
    context.insert(activity)
    context.insert(bucket)
    habit.activityPeriods = [activity]
    habit.buckets = [bucket]
    habit.entries = entries
    bucket.entries = entries
    try context.save()
    return InsertedHabit(habit: habit, bucket: bucket)
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func localDate(_ value: String) throws -> LocalDate {
    try LocalDate(validating: value)
  }

  private func instant(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return try #require(formatter.date(from: value))
  }

  private func timeZone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }

  private func uuid(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
  }
}
