import Foundation
import SwiftData
import Testing

@testable import TendCore

@MainActor
@Suite("Habit detail computation")
struct HabitDetailComputationTests {
  @Test("daily month uses local calendar days and keeps a three-month window")
  func dailyMonthUsesLocalCalendarDays() throws {
    let context = try makeContext()
    let zone = try timeZone("America/Los_Angeles")
    let now = try instant("2024-03-10T19:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Walk", target: 1),
      cadence: .daily,
      at: now,
      timeZone: zone
    )

    let snapshot = try HabitDetailComputation(context: context).snapshot(
      for: habit,
      selectedMonth: try instant("2024-03-20T12:00:00Z"),
      at: now,
      timeZone: zone
    )
    let expectedEarliest = try instant("2024-01-01T08:00:00Z")
    let expectedMarch = try instant("2024-03-01T08:00:00Z")

    #expect(snapshot.habitID == habit.id)
    #expect(snapshot.cadence == .daily)
    #expect(snapshot.monthRange.earliest == expectedEarliest)
    #expect(snapshot.monthRange.selected == expectedMarch)
    #expect(snapshot.monthRange.latest == expectedMarch)
    #expect(snapshot.history.count == 31)
    #expect(snapshot.history.first?.key == "day:2024-03-01")
    #expect(snapshot.history.last?.key == "day:2024-03-31")

    let springForward = try #require(
      snapshot.history.first { $0.key == "day:2024-03-10" }
    )
    #expect(springForward.end.timeIntervalSince(springForward.start) == 23 * 60 * 60)
    #expect(springForward.state == .open)
  }
  @Test("daily projection preserves the fall-back local day")
  func dailyProjectionPreservesFallBackLocalDay() throws {
    let context = try makeContext()
    let zone = try timeZone("America/Los_Angeles")
    let now = try instant("2024-11-03T20:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Walk", target: 1),
      cadence: .daily,
      at: now,
      timeZone: zone
    )

    let snapshot = try HabitDetailComputation(context: context).snapshot(
      for: habit,
      selectedMonth: now,
      at: now,
      timeZone: zone
    )
    let fallBack = try #require(
      snapshot.history.first { $0.key == "day:2024-11-03" }
    )

    #expect(fallBack.end.timeIntervalSince(fallBack.start) == 25 * 60 * 60)
    #expect(fallBack.state == .open)
  }

  @Test("projection uses the newly injected local schedule")
  func projectionUsesNewlyInjectedLocalSchedule() throws {
    let context = try makeContext()
    let utc = try timeZone("UTC")
    let losAngeles = try timeZone("America/Los_Angeles")
    let now = try instant("2024-01-01T00:30:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Walk", target: 1),
      cadence: .daily,
      at: now,
      timeZone: utc
    )
    try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: now,
      timeZone: utc
    )

    let snapshot = try HabitDetailComputation(context: context).snapshot(
      for: habit,
      selectedMonth: try instant("2023-12-15T12:00:00Z"),
      at: now,
      timeZone: losAngeles
    )
    let expectedDecember = try instant("2023-12-01T08:00:00Z")

    #expect(snapshot.monthRange.selected == expectedDecember)
    #expect(snapshot.history.last?.key == "day:2023-12-31")
    #expect(snapshot.history.last?.state == .open)
    #expect(snapshot.editableEntries.isEmpty)
  }
  @Test("closed history keeps its persisted coverage across a time-zone change")
  func closedHistoryKeepsPersistedCoverageAcrossTimeZoneChange() throws {
    let context = try makeContext()
    let utc = try timeZone("UTC")
    let losAngeles = try timeZone("America/Los_Angeles")
    let createdAt = try instant("2024-01-01T00:30:00Z")
    let deactivatedAt = try instant("2024-01-01T12:00:00Z")
    let now = try instant("2024-01-02T12:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Walk", target: 1),
      cadence: .daily,
      at: createdAt,
      timeZone: utc
    )
    let lifecycle = HabitActivityOperations(context: context)
    try lifecycle.deactivate(habit, at: deactivatedAt, timeZone: utc)
    try lifecycle.reactivate(habit, at: now, timeZone: losAngeles)

    let snapshot = try HabitDetailComputation(context: context).snapshot(
      for: habit,
      selectedMonth: now,
      at: now,
      timeZone: losAngeles
    )

    #expect(snapshot.history.first { $0.key == "day:2024-01-02" }?.state == .open)
  }
  @Test("open history keeps civil continuity across a time-zone change")
  func openHistoryKeepsCivilContinuityAcrossTimeZoneChange() throws {
    let context = try makeContext()
    let utc = try timeZone("UTC")
    let losAngeles = try timeZone("America/Los_Angeles")
    let createdAt = try instant("2024-01-01T12:00:00Z")
    let now = try instant("2024-01-03T12:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Walk", target: 1),
      cadence: .daily,
      at: createdAt,
      timeZone: utc
    )
    _ = try HabitStreakComputation(context: context).compute(
      habit: habit,
      at: now,
      timeZone: utc
    )

    let snapshot = try HabitDetailComputation(context: context).snapshot(
      for: habit,
      selectedMonth: now,
      at: now,
      timeZone: losAngeles
    )

    #expect(snapshot.history.first { $0.key == "day:2024-01-03" }?.state == .open)
  }

  @Test("weekly pages include every intersecting Monday bucket")
  func weeklyPagesIncludeIntersectingBuckets() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let now = try instant("2024-03-20T12:00:00Z")
    let habit = Habit(
      name: "Review",
      cadence: .weekly,
      target: 1,
      isActive: false,
      createdAt: try instant("2024-01-01T12:00:00Z")
    )
    context.insert(habit)
    try context.save()
    let computation = HabitDetailComputation(context: context)

    let march = try computation.snapshot(
      for: habit,
      selectedMonth: now,
      at: now,
      timeZone: zone
    )
    let february = try computation.snapshot(
      for: habit,
      selectedMonth: try instant("2024-02-10T12:00:00Z"),
      at: now,
      timeZone: zone
    )

    #expect(
      march.history.map(\.key)
        == [
          "week:2024-02-26",
          "week:2024-03-04",
          "week:2024-03-11",
          "week:2024-03-18",
          "week:2024-03-25",
        ])
    #expect(february.history.last?.key == "week:2024-02-26")
    #expect(march.history.first == february.history.last)
  }
  @Test("mid-week creation keeps its whole creation bucket")
  func midWeekCreationKeepsItsWholeCreationBucket() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-03T12:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Review", target: 1),
      cadence: .weekly,
      at: now,
      timeZone: zone
    )
    let computation = HabitDetailComputation(context: context)

    let january = try computation.snapshot(
      for: habit,
      selectedMonth: now,
      at: now,
      timeZone: zone
    )
    let december = try computation.snapshot(
      for: habit,
      selectedMonth: try instant("2023-12-15T12:00:00Z"),
      at: now,
      timeZone: zone
    )

    #expect(january.history.first?.key == "week:2024-01-01")
    #expect(january.history.first?.state == .open)
    #expect(december.history.last?.key == "week:2023-12-25")
    #expect(december.history.last?.state == .beforeCreation)
  }

  @Test("selected month clamps to the supported lifetime")
  func selectedMonthClampsToSupportedLifetime() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let now = try instant("2024-06-15T12:00:00Z")
    let habit = Habit(
      name: "Read",
      cadence: .daily,
      target: 1,
      isActive: false,
      createdAt: try instant("2024-01-20T12:00:00Z")
    )
    context.insert(habit)
    try context.save()
    let computation = HabitDetailComputation(context: context)

    let before = try computation.snapshot(
      for: habit,
      selectedMonth: try instant("2023-01-01T12:00:00Z"),
      at: now,
      timeZone: zone
    )
    let after = try computation.snapshot(
      for: habit,
      selectedMonth: try instant("2025-01-01T12:00:00Z"),
      at: now,
      timeZone: zone
    )
    let expectedEarliest = try instant("2024-01-01T00:00:00Z")
    let expectedLatest = try instant("2024-06-01T00:00:00Z")

    #expect(before.monthRange.earliest == expectedEarliest)
    #expect(before.monthRange.selected == before.monthRange.earliest)
    #expect(after.monthRange.latest == expectedLatest)
    #expect(after.monthRange.selected == after.monthRange.latest)
    #expect(before.history.first?.state == .beforeCreation)
    #expect(
      before.history.first { $0.key == "day:2024-01-19" }?.state == .beforeCreation
    )
  }
  @Test("persisted buckets keep final facts and provisional progress distinct")
  func persistedBucketsKeepFinalAndProvisionalFactsDistinct() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let createdAt = try instant("2024-01-01T12:00:00Z")
    let now = try instant("2024-01-04T12:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Read", target: 2, unit: "pages"),
      cadence: .daily,
      at: createdAt,
      timeZone: zone
    )
    let logging = LogEntryOperations(context: context)
    try logging.append(
      amount: 2,
      to: habit,
      at: createdAt,
      timeZone: zone
    )
    try logging.append(
      amount: 1,
      to: habit,
      destination: .periodKey("day:2024-01-03"),
      at: now,
      timeZone: zone
    )
    try logging.append(
      amount: 2,
      to: habit,
      at: now,
      timeZone: zone
    )

    let snapshot = try HabitDetailComputation(context: context).snapshot(
      for: habit,
      selectedMonth: createdAt,
      at: now,
      timeZone: zone
    )
    let periods = Dictionary(uniqueKeysWithValues: snapshot.history.map { ($0.key, $0) })
    let met = try #require(periods["day:2024-01-01"])
    let missed = try #require(periods["day:2024-01-02"])
    let grace = try #require(periods["day:2024-01-03"])
    let open = try #require(periods["day:2024-01-04"])

    #expect(met.state == .met)
    #expect(met.progress == nil)
    #expect(met.target == 2)
    #expect(met.unit == "pages")
    #expect(met.isRequirementMet == nil)
    #expect(missed.state == .missed)
    #expect(missed.progress == nil)
    #expect(missed.target == 2)
    #expect(grace.state == .grace)
    #expect(grace.progress == 1)
    #expect(grace.target == 2)
    #expect(grace.unit == "pages")
    #expect(grace.isRequirementMet == false)
    #expect(open.state == .open)
    #expect(open.progress == 2)
    #expect(open.isRequirementMet == true)
    #expect(
      snapshot.streak
        == HabitStreakState(
          currentStreak: 1,
          bestStreak: 1,
          isAtRisk: true,
          cadence: .daily
        ))
    #expect(
      Set(snapshot.editableEntries.map(\.bucketKey))
        == Set(["day:2024-01-04", "day:2024-01-03"])
    )
    #expect(habit.bestStreak == 1)
  }
  @Test("exempt buckets and inactive gaps carry no requirement facts")
  func exemptBucketsAndInactiveGapsCarryNoRequirementFacts() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let createdAt = try instant("2024-01-01T12:00:00Z")
    let loggedAt = try instant("2024-01-02T12:00:00Z")
    let deactivatedAt = try instant("2024-01-03T12:00:00Z")
    let now = try instant("2024-01-05T12:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Train", target: 3, unit: "sets"),
      cadence: .daily,
      at: createdAt,
      timeZone: zone
    )
    try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: loggedAt,
      timeZone: zone
    )
    let lifecycle = HabitActivityOperations(context: context)
    try lifecycle.deactivate(habit, at: deactivatedAt, timeZone: zone)
    try lifecycle.reactivate(habit, at: now, timeZone: zone)

    let snapshot = try HabitDetailComputation(context: context).snapshot(
      for: habit,
      selectedMonth: createdAt,
      at: now,
      timeZone: zone
    )
    let periods = Dictionary(uniqueKeysWithValues: snapshot.history.map { ($0.key, $0) })

    for key in ["day:2024-01-02", "day:2024-01-03", "day:2024-01-04"] {
      let inactive = try #require(periods[key])
      #expect(inactive.state == .inactive)
      #expect(inactive.progress == nil)
      #expect(inactive.target == nil)
      #expect(inactive.unit == nil)
      #expect(inactive.isRequirementMet == nil)
    }
    #expect(periods["day:2024-01-05"]?.state == .open)
    #expect(periods["day:2024-01-06"]?.state == .future)
    #expect(snapshot.editableEntries.isEmpty)
  }
  @Test("open and grace requirements report both provisional outcomes")
  func openAndGraceRequirementsReportBothProvisionalOutcomes() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let createdAt = try instant("2024-01-01T12:00:00Z")
    let now = try instant("2024-01-02T12:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Read", target: 2),
      cadence: .daily,
      at: createdAt,
      timeZone: zone
    )
    let logging = LogEntryOperations(context: context)
    try logging.append(amount: 2, to: habit, at: createdAt, timeZone: zone)
    try logging.append(amount: 1, to: habit, at: now, timeZone: zone)

    let snapshot = try HabitDetailComputation(context: context).snapshot(
      for: habit,
      selectedMonth: createdAt,
      at: now,
      timeZone: zone
    )
    let periods = Dictionary(uniqueKeysWithValues: snapshot.history.map { ($0.key, $0) })

    #expect(periods["day:2024-01-01"]?.state == .grace)
    #expect(periods["day:2024-01-01"]?.progress == 2)
    #expect(periods["day:2024-01-01"]?.isRequirementMet == true)
    #expect(periods["day:2024-01-02"]?.state == .open)
    #expect(periods["day:2024-01-02"]?.progress == 1)
    #expect(periods["day:2024-01-02"]?.isRequirementMet == false)
  }

  @Test("editable entries follow bucket authorization and deterministic order")
  func editableEntriesFollowBucketAuthorizationAndOrder() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let createdAt = try instant("2024-01-01T12:00:00Z")
    let now = try instant("2024-01-02T12:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Drink", target: 8, unit: "oz"),
      cadence: .daily,
      at: createdAt,
      timeZone: zone
    )
    let logging = LogEntryOperations(context: context)
    let older = try logging.append(
      amount: 1,
      to: habit,
      at: createdAt,
      timeZone: zone
    )
    let grace = try logging.append(
      amount: 2,
      to: habit,
      destination: .periodKey("day:2024-01-01"),
      at: now,
      timeZone: zone
    )
    let current = try logging.append(
      amount: 3,
      to: habit,
      at: now,
      timeZone: zone
    )
    current.id = try #require(
      UUID(uuidString: "00000000-0000-0000-0000-000000000001")
    )
    grace.id = try #require(
      UUID(uuidString: "00000000-0000-0000-0000-000000000002")
    )
    try context.save()

    let snapshot = try HabitDetailComputation(context: context).snapshot(
      for: habit,
      selectedMonth: createdAt,
      at: now,
      timeZone: zone
    )
    let expectedBucketStart = try instant("2024-01-01T00:00:00Z")
    let expectedBucketEnd = try instant("2024-01-02T00:00:00Z")

    let entries = snapshot.editableEntries
    #expect(entries.map(\.id) == [current.id, grace.id, older.id])
    #expect(entries.map(\.amount) == [3, 2, 1])
    #expect(entries.map(\.unit) == ["oz", "oz", "oz"])
    let first = try #require(entries.first)
    let second = try #require(entries.dropFirst().first)
    #expect(first.bucketKey == "day:2024-01-02")
    #expect(second.bucketKey == "day:2024-01-01")
    #expect(second.timestamp == now)
    #expect(second.bucketStart == expectedBucketStart)
    #expect(second.bucketEnd == expectedBucketEnd)
  }
  @Test("inactive open records are not exposed as editable")
  func inactiveOpenRecordsAreNotExposedAsEditable() throws {
    let context = try makeContext()
    let now = try instant("2024-01-01T12:00:00Z")
    let habit = try makeInactiveHabit(in: context)
    let bucket = try insertOpenBucket(in: context, habit: habit)
    context.insert(
      LogEntry(
        timestamp: now,
        amount: 1,
        habit: habit,
        bucket: bucket
      ))
    try context.save()

    let snapshot = try HabitDetailComputation(context: context).snapshot(
      for: habit,
      selectedMonth: now,
      at: now,
      timeZone: try timeZone("UTC")
    )

    #expect(snapshot.editableEntries.isEmpty)
  }

  @Test("editable entries are independent of the selected history page")
  func editableEntriesAreIndependentOfSelectedHistoryPage() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let createdAt = try instant("2024-01-01T12:00:00Z")
    let now = try instant("2024-03-02T12:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Drink", target: 8, unit: "oz"),
      cadence: .daily,
      at: createdAt,
      timeZone: zone
    )
    let logging = LogEntryOperations(context: context)
    let grace = try logging.append(
      amount: 2,
      to: habit,
      destination: .periodKey("day:2024-03-01"),
      at: now,
      timeZone: zone
    )
    let current = try logging.append(
      amount: 3,
      to: habit,
      at: now,
      timeZone: zone
    )
    current.id = try #require(
      UUID(uuidString: "00000000-0000-0000-0000-000000000001")
    )
    grace.id = try #require(
      UUID(uuidString: "00000000-0000-0000-0000-000000000002")
    )
    try context.save()

    let snapshot = try HabitDetailComputation(context: context).snapshot(
      for: habit,
      selectedMonth: createdAt,
      at: now,
      timeZone: zone
    )
    let expectedSelectedMonth = try instant("2024-01-01T00:00:00Z")

    #expect(snapshot.monthRange.selected == expectedSelectedMonth)
    #expect(snapshot.editableEntries.map(\.id) == [current.id, grace.id])
    #expect(
      snapshot.editableEntries.map(\.bucketKey)
        == ["day:2024-03-02", "day:2024-03-01"]
    )
  }

  @Test("missing persisted buckets inside active lifetime fail explicitly")
  func missingPersistedBucketsInsideActiveLifetimeFailExplicitly() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let createdAt = try instant("2024-01-01T12:00:00Z")
    let deactivatedAt = try instant("2024-01-03T12:00:00Z")
    let now = try instant("2024-06-15T12:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Write", target: 1),
      cadence: .daily,
      at: createdAt,
      timeZone: zone
    )
    let lifecycle = HabitActivityOperations(context: context)
    try lifecycle.deactivate(habit, at: deactivatedAt, timeZone: zone)
    try lifecycle.reactivate(habit, at: now, timeZone: zone)
    let buckets = try context.fetch(FetchDescriptor<HabitBucket>())
    let missing = try #require(buckets.first { $0.periodKey == "day:2024-01-01" })
    context.delete(missing)
    try context.save()

    try expectError(HabitDetailComputationError.missingActiveBucket("day:2024-01-01")) {
      _ = try HabitDetailComputation(context: context).snapshot(
        for: habit,
        selectedMonth: now,
        at: now,
        timeZone: zone
      )
    }
  }

  @Test("duplicate entry identifiers are rejected")
  func duplicateEntryIdentifiersAreRejected() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T12:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Drink", target: 8),
      cadence: .daily,
      at: now,
      timeZone: zone
    )
    let logging = LogEntryOperations(context: context)
    let first = try logging.append(amount: 1, to: habit, at: now, timeZone: zone)
    let second = try logging.append(amount: 1, to: habit, at: now, timeZone: zone)
    let duplicateID = try #require(
      UUID(uuidString: "00000000-0000-0000-0000-000000000099")
    )
    first.id = duplicateID
    second.id = duplicateID
    try context.save()

    try expectError(HabitDetailComputationError.duplicateEntryID(duplicateID)) {
      _ = try HabitDetailComputation(context: context).snapshot(
        for: habit,
        selectedMonth: now,
        at: now,
        timeZone: zone
      )
    }
  }

  @Test("entry relationship corruption is rejected")
  func entryRelationshipCorruptionIsRejected() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let now = try instant("2024-01-01T12:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Drink", target: 8),
      cadence: .daily,
      at: now,
      timeZone: zone
    )
    let entry = try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: now,
      timeZone: zone
    )
    entry.bucket = nil
    try context.save()

    try expectError(HabitDetailComputationError.invalidEntryRelationship(entry.id)) {
      _ = try HabitDetailComputation(context: context).snapshot(
        for: habit,
        selectedMonth: now,
        at: now,
        timeZone: zone
      )
    }
    let missingHabitContext = try makeContext()
    let missingHabit = try HabitManagementOperations(context: missingHabitContext).create(
      fields: HabitEditableFields(name: "Drink", target: 8),
      cadence: .daily,
      at: now,
      timeZone: zone
    )
    let missingHabitEntry = try LogEntryOperations(context: missingHabitContext).append(
      amount: 1,
      to: missingHabit,
      at: now,
      timeZone: zone
    )
    missingHabitEntry.habit = nil
    try missingHabitContext.save()

    try expectError(
      HabitDetailComputationError.invalidEntryRelationship(missingHabitEntry.id)
    ) {
      _ = try HabitDetailComputation(context: missingHabitContext).snapshot(
        for: missingHabit,
        selectedMonth: now,
        at: now,
        timeZone: zone
      )
    }
  }

  @Test("read-only derived output does not save")
  func readOnlyDerivedOutputDoesNotSave() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let createdAt = try instant("2024-01-01T12:00:00Z")
    let now = try instant("2024-01-03T12:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Walk", target: 1),
      cadence: .daily,
      at: createdAt,
      timeZone: zone
    )
    try HabitActivityOperations(context: context).deactivate(
      habit,
      at: now,
      timeZone: zone
    )
    var saveCount = 0

    let snapshot = try HabitDetailComputation(context: context) {
      saveCount += 1
      try context.save()
    }.snapshot(
      for: habit,
      selectedMonth: createdAt,
      at: now,
      timeZone: zone
    )

    #expect(saveCount == 0)
    #expect(snapshot.streak.bestStreak == 0)
    let activeContext = try makeContext()
    let activeHabit = try HabitManagementOperations(context: activeContext).create(
      fields: HabitEditableFields(name: "Read", target: 1),
      cadence: .daily,
      at: now,
      timeZone: zone
    )
    var activeSaveCount = 0
    _ = try HabitDetailComputation(context: activeContext) {
      activeSaveCount += 1
      try activeContext.save()
    }.snapshot(
      for: activeHabit,
      selectedMonth: now,
      at: now,
      timeZone: zone
    )
    #expect(activeSaveCount == 0)
  }

  @Test("best-streak save failures roll back and propagate")
  func bestStreakSaveFailuresRollBackAndPropagate() throws {
    let context = try makeContext()
    let zone = try timeZone("UTC")
    let createdAt = try instant("2024-01-01T12:00:00Z")
    let now = try instant("2024-01-03T12:00:00Z")
    let habit = try HabitManagementOperations(context: context).create(
      fields: HabitEditableFields(name: "Walk", target: 1),
      cadence: .daily,
      at: createdAt,
      timeZone: zone
    )
    try LogEntryOperations(context: context).append(
      amount: 1,
      to: habit,
      at: createdAt,
      timeZone: zone
    )
    try HabitActivityOperations(context: context).deactivate(
      habit,
      at: now,
      timeZone: zone
    )
    var saveCount = 0
    let computation = HabitDetailComputation(context: context) {
      saveCount += 1
      throw DetailSaveFailure.expected
    }

    try expectError(DetailSaveFailure.expected) {
      _ = try computation.snapshot(
        for: habit,
        selectedMonth: createdAt,
        at: now,
        timeZone: zone
      )
    }
    #expect(saveCount == 1)
    #expect(habit.bestStreak == 0)
  }
  @Test("later integrity failures cannot persist a better streak")
  func laterIntegrityFailuresCannotPersistBetterStreak() throws {
    let context = try makeContext()
    let habit = try makeInactiveHabit(in: context)
    let bucket = try insertOpenBucket(in: context, habit: habit)
    try settle(bucket)
    let entry = LogEntry(
      timestamp: try instant("2024-01-01T12:00:00Z"),
      amount: 1,
      bucket: bucket
    )
    context.insert(entry)
    try context.save()
    var saveCount = 0
    let computation = HabitDetailComputation(context: context) {
      saveCount += 1
      try context.save()
    }

    try expectError(HabitDetailComputationError.invalidEntryRelationship(entry.id)) {
      _ = try computation.snapshot(
        for: habit,
        selectedMonth: try instant("2024-01-01T12:00:00Z"),
        at: try instant("2024-01-04T12:00:00Z"),
        timeZone: try timeZone("UTC")
      )
    }
    #expect(saveCount == 0)
    #expect(habit.bestStreak == 0)
  }

  @Test("detached foreign deleted and malformed habits are rejected")
  func detachedForeignDeletedAndMalformedHabitsAreRejected() throws {
    let context = try makeContext()
    let now = try instant("2024-01-01T12:00:00Z")
    let detached = Habit(name: "Detached", cadence: .daily, target: 1)
    try expectSnapshotError(
      HabitStreakComputationError.detachedHabit,
      context: context,
      habit: detached,
      at: now
    )

    let foreignContext = try makeContext()
    let foreign = try makeInactiveHabit(in: foreignContext)
    try expectSnapshotError(
      HabitStreakComputationError.detachedHabit,
      context: context,
      habit: foreign,
      at: now
    )

    let deleted = try makeInactiveHabit(in: context)
    context.delete(deleted)
    try expectSnapshotError(
      HabitStreakComputationError.detachedHabit,
      context: context,
      habit: deleted,
      at: now
    )

    let unsupportedContext = try makeContext()
    let unsupported = try makeInactiveHabit(in: unsupportedContext)
    unsupported.cadenceRawValue = "monthly"
    try unsupportedContext.save()
    try expectSnapshotError(
      BucketEvaluationError.unsupportedCadence("monthly"),
      context: unsupportedContext,
      habit: unsupported,
      at: now
    )

    let targetContext = try makeContext()
    let invalidTarget = try makeInactiveHabit(in: targetContext, target: 0)
    try expectSnapshotError(
      BucketEvaluationError.invalidRequirement(0),
      context: targetContext,
      habit: invalidTarget,
      at: now
    )
  }

  @Test("malformed activity graphs are rejected")
  func malformedActivityGraphsAreRejected() throws {
    let context = try makeContext()
    let habit = try makeInactiveHabit(in: context)
    let now = try instant("2024-01-01T12:00:00Z")
    context.insert(
      HabitActivityPeriod(
        startedAt: try instant("2024-01-01T00:00:00Z"),
        habit: habit
      ))
    try context.save()

    try expectSnapshotError(
      HabitActivityOperationError.unexpectedOpenActivityPeriod,
      context: context,
      habit: habit,
      at: now
    )
  }

  @Test("bucket integrity failures propagate unchanged")
  func bucketIntegrityFailuresPropagateUnchanged() throws {
    let now = try instant("2024-01-01T12:00:00Z")

    let duplicateContext = try makeContext()
    let duplicateHabit = try makeInactiveHabit(in: duplicateContext)
    _ = try insertOpenBucket(in: duplicateContext, habit: duplicateHabit)
    _ = try insertOpenBucket(in: duplicateContext, habit: duplicateHabit)
    try expectSnapshotError(
      HabitStreakComputationError.duplicatePeriodKey("day:2024-01-01"),
      context: duplicateContext,
      habit: duplicateHabit,
      at: now
    )

    let calendarContext = try makeContext()
    let calendarHabit = try makeInactiveHabit(in: calendarContext)
    let malformed = try insertOpenBucket(in: calendarContext, habit: calendarHabit)
    malformed.periodKey = "not-a-period"
    try calendarContext.save()
    try expectSnapshotError(
      BucketEvaluationError.calendar(.malformedKey("not-a-period")),
      context: calendarContext,
      habit: calendarHabit,
      at: now
    )

    let partialContext = try makeContext()
    let partialHabit = try makeInactiveHabit(in: partialContext)
    let partial = try insertOpenBucket(in: partialContext, habit: partialHabit)
    partial.finalizedAt = try instant("2024-01-03T00:00:00Z")
    try partialContext.save()
    try expectSnapshotError(
      BucketEvaluationError.partialFinality,
      context: partialContext,
      habit: partialHabit,
      at: try instant("2024-01-04T12:00:00Z")
    )
    let finalKeyContext = try makeContext()
    let finalKeyHabit = try makeInactiveHabit(in: finalKeyContext)
    let malformedFinal = try insertOpenBucket(
      in: finalKeyContext,
      habit: finalKeyHabit
    )
    try settle(malformedFinal)
    malformedFinal.periodKey = "not-a-period"
    try finalKeyContext.save()
    try expectSnapshotError(
      BucketEvaluationError.calendar(.malformedKey("not-a-period")),
      context: finalKeyContext,
      habit: finalKeyHabit,
      at: try instant("2024-01-04T12:00:00Z")
    )

    let finalCadenceContext = try makeContext()
    let finalCadenceHabit = try makeInactiveHabit(in: finalCadenceContext)
    let unsupportedFinal = try insertOpenBucket(
      in: finalCadenceContext,
      habit: finalCadenceHabit
    )
    try settle(unsupportedFinal)
    unsupportedFinal.cadenceRawValue = "monthly"
    try finalCadenceContext.save()
    try expectSnapshotError(
      BucketEvaluationError.unsupportedCadence("monthly"),
      context: finalCadenceContext,
      habit: finalCadenceHabit,
      at: try instant("2024-01-04T12:00:00Z")
    )
  }

  @Test("invalid and overflowing entry totals propagate unchanged")
  func invalidAndOverflowingEntryTotalsPropagateUnchanged() throws {
    let now = try instant("2024-01-01T12:00:00Z")

    let invalidContext = try makeContext()
    let invalidHabit = try makeInactiveHabit(in: invalidContext)
    let invalidBucket = try insertOpenBucket(in: invalidContext, habit: invalidHabit)
    try settle(invalidBucket)
    invalidContext.insert(
      LogEntry(
        timestamp: now,
        amount: 0,
        habit: invalidHabit,
        bucket: invalidBucket
      ))
    try invalidContext.save()
    try expectSnapshotError(
      BucketEvaluationError.invalidEntryAmount(0),
      context: invalidContext,
      habit: invalidHabit,
      at: now
    )

    let overflowContext = try makeContext()
    let overflowHabit = try makeInactiveHabit(in: overflowContext)
    let overflowBucket = try insertOpenBucket(in: overflowContext, habit: overflowHabit)
    try settle(overflowBucket)
    overflowContext.insert(
      LogEntry(
        timestamp: now,
        amount: Int.max,
        habit: overflowHabit,
        bucket: overflowBucket
      ))
    overflowContext.insert(
      LogEntry(
        timestamp: now,
        amount: 1,
        habit: overflowHabit,
        bucket: overflowBucket
      ))
    try overflowContext.save()
    try expectSnapshotError(
      BucketEvaluationError.progressOverflow,
      context: overflowContext,
      habit: overflowHabit,
      at: now
    )
  }

  private func settle(_ bucket: HabitBucket) throws {
    bucket.finalizedAt = try instant("2024-01-03T00:00:00Z")
    bucket.verdictRawValue = BucketVerdict.met.rawValue
    bucket.targetSnapshot = 1
    bucket.unitSnapshot = "times"
  }

  private func expectSnapshotError<E>(
    _ expected: E,
    context: ModelContext,
    habit: Habit,
    at instant: Date
  ) throws where E: Error & Equatable {
    try expectError(expected) {
      _ = try HabitDetailComputation(context: context).snapshot(
        for: habit,
        selectedMonth: instant,
        at: instant,
        timeZone: try timeZone("UTC")
      )
    }
  }

  private func makeInactiveHabit(
    in context: ModelContext,
    target: Int = 1
  ) throws -> Habit {
    let habit = Habit(
      name: "Fixture",
      cadence: .daily,
      target: target,
      isActive: false,
      createdAt: try instant("2024-01-01T00:00:00Z")
    )
    context.insert(habit)
    try context.save()
    return habit
  }

  private func insertOpenBucket(
    in context: ModelContext,
    habit: Habit
  ) throws -> HabitBucket {
    let period = try CalendarBucketSchedule(timeZone: timeZone("UTC")).period(
      containing: try instant("2024-01-01T12:00:00Z"),
      cadence: .daily
    )
    let bucket = HabitBucket(
      periodKey: period.key,
      startAt: period.start,
      endAt: period.end,
      cadence: .daily,
      habit: habit
    )
    context.insert(bucket)
    try context.save()
    return bucket
  }

  private func expectError<E>(
    _ expected: E,
    performing operation: () throws -> Void
  ) throws where E: Error & Equatable {
    do {
      try operation()
      Issue.record("Expected \(expected)")
    } catch let error as E {
      #expect(error == expected)
    }
  }

  private func makeContext() throws -> ModelContext {
    ModelContext(try TendModelContainer.inMemory())
  }

  private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }

  private func timeZone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }
}

private enum DetailSaveFailure: Error, Equatable {
  case expected
}
