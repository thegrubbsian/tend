import Foundation
import SwiftData
import TendCore
import Testing

@testable import Tend

@MainActor
@Suite("Habit form model")
struct HabitFormModelTests {
  @Test("New mode starts from explicit documented defaults")
  func newModeStartsFromDocumentedDefaults() {
    let model = HabitFormModel(mode: .new)

    #expect(model.title == "New habit")
    #expect(model.name.isEmpty)
    #expect(model.cadence == .daily)
    #expect(model.targetText == "1")
    #expect(model.unit == "times")
    #expect(model.pinnedWeekdays == .none)
    #expect(!model.hasReminder)
    #expect(!model.isCadenceLocked)
    #expect(model.persistenceError == nil)
  }

  @Test("field errors appear only after interaction")
  func fieldErrorsAppearOnlyAfterInteraction() {
    let model = HabitFormModel(mode: .new)
    model.name = "   "
    model.targetText = "0"
    model.unit = "\n\t"

    #expect(model.error(for: .name) == nil)
    #expect(model.error(for: .target) == nil)
    #expect(model.error(for: .unit) == nil)

    model.markInteracted(with: .name)
    model.markInteracted(with: .target)
    model.markInteracted(with: .unit)

    #expect(model.error(for: .name) == .emptyName)
    #expect(model.error(for: .target) == .invalidTarget)
    #expect(model.error(for: .unit) == .emptyUnit)
  }

  @Test(
    "target accepts only base-ten positive integers",
    arguments: ["", "0", "-1", "+1", "1.5", "1,000", "999999999999999999999999"]
  )
  func targetRejectsNonPositiveOrNonBaseTenValues(_ value: String) {
    let model = HabitFormModel(mode: .new)
    model.targetText = value
    model.markInteracted(with: .target)

    #expect(model.error(for: .target) == .invalidTarget)
  }

  @Test("valid submission trims only surrounding name and unit whitespace")
  func validSubmissionTrimsSurroundingWhitespace() throws {
    let model = HabitFormModel(mode: .new)
    model.name = "  Morning   walk  "
    model.targetText = "8000"
    model.unit = "  steps per day  "

    let fields = try model.validatedFields()

    #expect(fields.name == "Morning   walk")
    #expect(fields.target == 8000)
    #expect(fields.unit == "steps per day")
  }

  @Test("Daily cadence clears pins even when weekday controls are hidden")
  func dailyCadenceClearsHiddenPins() throws {
    let model = HabitFormModel(mode: .new)
    model.name = "Walk"
    model.selectCadence(.weekly)
    model.togglePinnedWeekday(.monday)
    model.togglePinnedWeekday(.sunday)

    #expect(model.showsPinnedWeekdays)
    #expect(model.pinnedWeekdays.contains(.monday))
    #expect(model.pinnedWeekdays.contains(.sunday))

    model.selectCadence(.daily)
    model.togglePinnedWeekday(.friday)

    #expect(!model.showsPinnedWeekdays)
    #expect(model.pinnedWeekdays == .none)
    #expect(try model.validatedFields().pinnedWeekdays == .none)
  }

  @Test("weekday controls run Monday through Sunday with full localized labels")
  func weekdayControlsAreMondayFirstAndFullyLocalized() {
    let locale = Locale(identifier: "en_US")
    let calendar = Calendar(identifier: .gregorian)

    let labels = HabitFormWeekday.localizedLabels(calendar: calendar, locale: locale)
    #expect(labels.map(\.short) == ["M", "T", "W", "T", "F", "S", "S"])
    #expect(
      labels.map(\.accessibility) == [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
      ])
  }

  @Test("weekday controls honor an injected non-Gregorian calendar and locale")
  func weekdayControlsHonorInjectedCalendarAndLocale() {
    let locale = Locale(identifier: "ar_SA")
    let calendar = Calendar(identifier: .islamicUmmAlQura)

    let labels = HabitFormWeekday.localizedLabels(calendar: calendar, locale: locale)

    #expect(labels.map(\.short) == ["ن", "ث", "ر", "خ", "ج", "س", "ح"])
    #expect(
      labels.map(\.accessibility) == [
        "الاثنين",
        "الثلاثاء",
        "الأربعاء",
        "الخميس",
        "الجمعة",
        "السبت",
        "الأحد",
      ])
  }

  @Test("reminder preserves local-day bounds across calendars and time zones")
  func reminderPreservesLocalDayBoundsAcrossCalendarsAndTimeZones() throws {
    let model = HabitFormModel(mode: .new)
    model.setReminderEnabled(true)
    #expect(model.reminderTime == ReminderTime(hour: 9, minute: 0))

    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let riyadh = try #require(TimeZone(identifier: "Asia/Riyadh"))
    let configurations = [
      (Calendar(identifier: .gregorian), losAngeles),
      (Calendar(identifier: .islamicUmmAlQura), riyadh),
    ]
    let bounds = [
      try #require(ReminderTime(hour: 0, minute: 0)),
      try #require(ReminderTime(hour: 23, minute: 59)),
    ]

    for (calendar, timeZone) in configurations {
      for expectedTime in bounds {
        let date = HabitFormReminderDateAdapter.date(
          for: expectedTime,
          calendar: calendar,
          timeZone: timeZone
        )
        #expect(
          HabitFormReminderDateAdapter.reminderTime(
            from: date,
            calendar: calendar,
            timeZone: timeZone
          ) == expectedTime)
      }

      let defaultDate = HabitFormReminderDateAdapter.date(
        for: nil,
        calendar: calendar,
        timeZone: timeZone
      )
      #expect(
        HabitFormReminderDateAdapter.reminderTime(
          from: defaultDate,
          calendar: calendar,
          timeZone: timeZone
        ) == ReminderTime(hour: 9, minute: 0))
    }
  }

  @Test("weekly reminder without pins warns but remains valid")
  func weeklyReminderWithoutPinsWarnsButRemainsValid() throws {
    let model = HabitFormModel(mode: .new)
    model.name = "Walk"
    model.selectCadence(.weekly)
    model.setReminderEnabled(true)

    #expect(model.showsUnscheduledReminderWarning)
    let fields = try model.validatedFields()
    #expect(fields.pinnedWeekdays == .none)
    #expect(fields.reminderTime == ReminderTime(hour: 9, minute: 0))
  }

  @Test("clearing a reminder preserves weekly pinned days")
  func clearingReminderPreservesPinnedDays() {
    let model = HabitFormModel(mode: .new)
    model.selectCadence(.weekly)
    model.togglePinnedWeekday(.wednesday)
    model.setReminderEnabled(true)

    model.setReminderEnabled(false)

    #expect(model.reminderTime == nil)
    #expect(model.pinnedWeekdays == .wednesday)
    #expect(!model.showsUnscheduledReminderWarning)
  }

  @Test("Edit mode copies persisted values once and locks cadence")
  func editModeCopiesValuesOnceAndLocksCadence() throws {
    let reminder = try #require(ReminderTime(hour: 7, minute: 45))
    let habit = Habit(
      name: "Read",
      cadence: .weekly,
      target: 3,
      unit: "chapters",
      pinnedWeekdays: .monday,
      reminderTime: reminder
    )

    let model = HabitFormModel(mode: .edit(habit))

    #expect(model.title == "Edit habit")
    #expect(model.name == "Read")
    #expect(model.cadence == .weekly)
    #expect(model.targetText == "3")
    #expect(model.unit == "chapters")
    #expect(model.pinnedWeekdays == .monday)
    #expect(model.reminderTime == reminder)
    #expect(model.isCadenceLocked)

    model.name = "Morning reading"
    habit.unit = "externally changed"
    model.selectCadence(.daily)

    #expect(habit.name == "Read")
    #expect(model.unit == "chapters")
    #expect(model.cadence == .weekly)
  }

  @Test("Edit rejects unsupported imported configuration without guessing a replacement")
  func editRejectsUnsupportedImportedConfiguration() throws {
    let habit = Habit(name: "Read", cadence: .daily, target: 1)
    habit.cadenceRawValue = "fortnightly"
    habit.reminderMinuteOfDay = 450
    let model = HabitFormModel(mode: .edit(habit))
    var persistenceCallCount = 0
    let persistence = HabitFormPersistence(
      create: { _, _, _, _ in
        persistenceCallCount += 1
        return habit
      },
      update: { _, _, _, _ in
        persistenceCallCount += 1
      }
    )

    #expect(model.cadenceDisplayName == "Unsupported cadence")
    #expect(
      model.configurationErrorMessage
        == "This habit has an unsupported stored cadence and can’t be edited.")
    #expect(model.reminderTime == ReminderTime(hour: 7, minute: 30))
    #expect(model.showsReminderControl)
    #expect(!model.canSave)
    #expect(model.save(using: persistence, at: .now, timeZone: .gmt) == nil)
    #expect(persistenceCallCount == 0)
  }

  @Test("Edit rejects invalid imported pinned days and reminder time")
  func editRejectsInvalidImportedPinnedDaysAndReminderTime() {
    let invalidPinsHabit = Habit(name: "Read", cadence: .weekly, target: 1)
    invalidPinsHabit.pinnedWeekdaysRawValue = 1 << 7
    invalidPinsHabit.reminderMinuteOfDay = 450
    let invalidPinsModel = HabitFormModel(mode: .edit(invalidPinsHabit))

    #expect(
      invalidPinsModel.configurationErrorMessage
        == "This habit has invalid stored pinned days and can’t be edited.")
    #expect(invalidPinsModel.reminderTime == ReminderTime(hour: 7, minute: 30))
    #expect(invalidPinsModel.showsReminderControl)
    #expect(!invalidPinsModel.showsPinnedWeekdays)
    #expect(!invalidPinsModel.canSave)

    let invalidReminderHabit = Habit(name: "Walk", cadence: .daily, target: 1)
    invalidReminderHabit.reminderMinuteOfDay = 24 * 60
    let invalidReminderModel = HabitFormModel(mode: .edit(invalidReminderHabit))

    #expect(
      invalidReminderModel.configurationErrorMessage
        == "This habit has an invalid stored reminder time and can’t be edited.")
    #expect(!invalidReminderModel.showsReminderControl)
    #expect(!invalidReminderModel.canSave)

    let multipleErrorsHabit = Habit(name: "Stretch", cadence: .weekly, target: 1)
    multipleErrorsHabit.pinnedWeekdaysRawValue = 1 << 7
    multipleErrorsHabit.reminderMinuteOfDay = 24 * 60
    let multipleErrorsModel = HabitFormModel(mode: .edit(multipleErrorsHabit))

    #expect(
      multipleErrorsModel.configurationErrorMessage
        == "This habit has invalid stored pinned days and can’t be edited. "
        + "This habit has an invalid stored reminder time and can’t be edited.")
    #expect(!multipleErrorsModel.showsPinnedWeekdays)
    #expect(!multipleErrorsModel.showsReminderControl)
    #expect(!multipleErrorsModel.canSave)
  }

  @Test("reminder permission gesture honors draft provenance exactly once")
  func reminderPermissionGestureHonorsDraftProvenanceExactlyOnce() {
    let newModel = HabitFormModel(mode: .new)

    #expect(newModel.setReminderEnabled(true))
    newModel.setReminderEnabled(false)
    #expect(!newModel.setReminderEnabled(true))

    let remindedHabit = Habit(
      name: "Walk",
      cadence: .daily,
      target: 1,
      reminderTime: ReminderTime(hour: 9, minute: 0)
    )
    let editModel = HabitFormModel(mode: .edit(remindedHabit))
    editModel.setReminderEnabled(false)

    #expect(!editModel.setReminderEnabled(true))
    #expect(editModel.reminderTime == ReminderTime(hour: 9, minute: 0))
    #expect(editModel.canSave)
  }

  @Test("successful create and update signal reminder refresh exactly once")
  func successfulSavesSignalReminderRefreshExactlyOnce() throws {
    let instant = Date(timeIntervalSince1970: 1_725_214_400)
    let timeZone = try #require(TimeZone(identifier: "UTC"))
    let createdHabit = Habit(name: "Walk", cadence: .daily, target: 1)
    var createRefreshCount = 0
    let createModel = HabitFormModel(
      mode: .new,
      reminderRefresh: { createRefreshCount += 1 }
    )
    createModel.name = "Walk"
    let createPersistence = HabitFormPersistence(
      create: { _, _, _, _ in createdHabit },
      update: { _, _, _, _ in
        Issue.record("Create must not dispatch update")
      }
    )

    #expect(
      createModel.save(
        using: createPersistence,
        at: instant,
        timeZone: timeZone
      ) === createdHabit)
    #expect(createRefreshCount == 1)

    var updateRefreshCount = 0
    let updateModel = HabitFormModel(
      mode: .edit(createdHabit),
      reminderRefresh: { updateRefreshCount += 1 }
    )
    let updatePersistence = HabitFormPersistence(
      create: { _, _, _, _ in
        Issue.record("Update must not dispatch create")
        return createdHabit
      },
      update: { _, _, _, _ in }
    )

    #expect(
      updateModel.save(
        using: updatePersistence,
        at: instant,
        timeZone: timeZone
      ) === createdHabit)
    #expect(updateRefreshCount == 1)
  }

  @Test("invalid and failed saves signal only after retry succeeds")
  func invalidAndFailedSavesSignalOnlyAfterRetrySucceeds() {
    var refreshCount = 0
    var saveAttempts = 0
    let expectedHabit = Habit(name: "Walk", cadence: .daily, target: 1)
    let persistence = HabitFormPersistence(
      create: { _, _, _, _ in
        saveAttempts += 1
        if saveAttempts == 1 {
          throw TestSaveFailure.expected
        }
        return expectedHabit
      },
      update: { _, _, _, _ in }
    )
    let model = HabitFormModel(
      mode: .new,
      reminderRefresh: { refreshCount += 1 }
    )

    #expect(model.save(using: persistence, at: .now, timeZone: .gmt) == nil)
    #expect(saveAttempts == 0)
    #expect(refreshCount == 0)

    model.name = "Walk"
    #expect(model.save(using: persistence, at: .now, timeZone: .gmt) == nil)
    #expect(saveAttempts == 1)
    #expect(refreshCount == 0)

    #expect(model.save(using: persistence, at: .now, timeZone: .gmt) === expectedHabit)
    #expect(saveAttempts == 2)
    #expect(refreshCount == 1)
  }

  @Test("New Save dispatches create exactly once with the current boundary values")
  func newSaveDispatchesCreateExactlyOnce() throws {
    let instant = Date(timeIntervalSince1970: 1_725_214_400)
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let expectedHabit = Habit(name: "Walk", cadence: .daily, target: 1)
    var createCallCount = 0
    var receivedFields: HabitEditableFields?
    var receivedCadence: HabitCadence?
    var receivedInstant: Date?
    var receivedTimeZone: TimeZone?
    let persistence = HabitFormPersistence(
      create: { fields, cadence, actualInstant, actualTimeZone in
        createCallCount += 1
        receivedFields = fields
        receivedCadence = cadence
        receivedInstant = actualInstant
        receivedTimeZone = actualTimeZone
        return expectedHabit
      },
      update: { _, _, _, _ in
        Issue.record("New Save must not dispatch update")
      }
    )
    let model = HabitFormModel(mode: .new)
    model.name = "  Walk  "
    model.targetText = "2"
    model.unit = "  laps  "

    _ = model.title
    _ = try model.validatedFields()
    #expect(createCallCount == 0)

    let savedHabit = model.save(using: persistence, at: instant, timeZone: timeZone)

    #expect(savedHabit === expectedHabit)
    #expect(createCallCount == 1)
    #expect(receivedFields == HabitEditableFields(name: "Walk", target: 2, unit: "laps"))
    #expect(receivedCadence == .daily)
    #expect(receivedInstant == instant)
    #expect(receivedTimeZone?.identifier == timeZone.identifier)
    #expect(model.persistenceError == nil)
  }

  @Test("Edit Save dispatches update for the original habit without cadence input")
  func editSaveDispatchesUpdateForOriginalHabit() throws {
    let instant = Date(timeIntervalSince1970: 1_725_214_400)
    let timeZone = try #require(TimeZone(identifier: "UTC"))
    let habit = Habit(
      name: "Read",
      cadence: .weekly,
      target: 1,
      unit: "chapter",
      pinnedWeekdays: .wednesday
    )
    var createCallCount = 0
    var updateCallCount = 0
    var receivedHabit: Habit?
    var receivedFields: HabitEditableFields?
    let persistence = HabitFormPersistence(
      create: { _, _, _, _ in
        createCallCount += 1
        return habit
      },
      update: { actualHabit, fields, actualInstant, actualTimeZone in
        updateCallCount += 1
        receivedHabit = actualHabit
        receivedFields = fields
        #expect(actualInstant == instant)
        #expect(actualTimeZone.identifier == timeZone.identifier)
      }
    )
    let model = HabitFormModel(mode: .edit(habit))
    model.name = "Read fiction"
    model.targetText = "2"
    model.unit = "chapters"

    let savedHabit = model.save(using: persistence, at: instant, timeZone: timeZone)

    #expect(savedHabit === habit)
    #expect(receivedHabit === habit)
    #expect(
      receivedFields
        == HabitEditableFields(
          name: "Read fiction",
          target: 2,
          unit: "chapters",
          pinnedWeekdays: .wednesday
        ))
    #expect(createCallCount == 0)
    #expect(updateCallCount == 1)
    #expect(habit.cadenceRawValue == HabitCadence.weekly.rawValue)
  }

  @Test("New Save persists through the live TendCore boundary")
  func newSavePersistsThroughLiveTendCoreBoundary() throws {
    let container = try TendModelContainer.inMemory()
    let context = container.mainContext
    let instant = Date(timeIntervalSince1970: 1_725_214_400)
    let model = HabitFormModel(mode: .new)
    model.name = "Strength"
    model.targetText = "3"
    model.unit = "sets"
    model.selectCadence(.weekly)
    model.togglePinnedWeekday(.monday)
    model.setReminderEnabled(true)
    model.reminderTime = ReminderTime(hour: 7, minute: 30)

    let savedHabit = try #require(
      model.save(
        using: .live(context: context),
        at: instant,
        timeZone: .gmt
      ))
    let persistedHabits = try context.fetch(FetchDescriptor<Habit>())
    let persistedHabit = try #require(persistedHabits.first)

    #expect(persistedHabits.count == 1)
    #expect(savedHabit === persistedHabit)
    #expect(persistedHabit.modelContext === context)
    #expect(persistedHabit.name == "Strength")
    #expect(persistedHabit.cadenceRawValue == HabitCadence.weekly.rawValue)
    #expect(persistedHabit.target == 3)
    #expect(persistedHabit.unit == "sets")
    #expect(persistedHabit.pinnedWeekdaysRawValue == PinnedWeekdays.monday.rawValue)
    #expect(persistedHabit.reminderMinuteOfDay == 450)
    #expect(persistedHabit.activityPeriods?.count == 1)
    #expect(persistedHabit.buckets?.isEmpty == false)
    #expect(model.persistenceError == nil)
  }

  @Test("Edit Save persists through the live TendCore boundary")
  func editSavePersistsThroughLiveTendCoreBoundary() throws {
    let container = try TendModelContainer.inMemory()
    let context = container.mainContext
    let instant = Date(timeIntervalSince1970: 1_725_214_400)
    let operations = HabitManagementOperations(context: context)
    let habit = try operations.create(
      fields: HabitEditableFields(
        name: "Read",
        target: 1,
        unit: "chapter",
        pinnedWeekdays: .wednesday
      ),
      cadence: .weekly,
      at: instant,
      timeZone: .gmt
    )
    let model = HabitFormModel(mode: .edit(habit))
    model.name = "Read fiction"
    model.targetText = "2"
    model.unit = "chapters"
    model.togglePinnedWeekday(.friday)

    let savedHabit = try #require(
      model.save(
        using: .live(context: context),
        at: instant.addingTimeInterval(60),
        timeZone: .gmt
      ))
    let persistedHabits = try context.fetch(FetchDescriptor<Habit>())
    let persistedHabit = try #require(persistedHabits.first)

    #expect(persistedHabits.count == 1)
    #expect(savedHabit === habit)
    #expect(persistedHabit === habit)
    #expect(persistedHabit.name == "Read fiction")
    #expect(persistedHabit.target == 2)
    #expect(persistedHabit.unit == "chapters")
    #expect(persistedHabit.cadenceRawValue == HabitCadence.weekly.rawValue)
    #expect(
      persistedHabit.pinnedWeekdaysRawValue == PinnedWeekdays.wednesday.rawValue
        | PinnedWeekdays.friday.rawValue)
    #expect(model.persistenceError == nil)
  }

  @Test("invalid Save reveals errors and performs no persistence")
  func invalidSaveRevealsErrorsWithoutPersistence() throws {
    let timeZone = try #require(TimeZone(identifier: "UTC"))
    var persistenceCallCount = 0
    let persistence = HabitFormPersistence(
      create: { _, _, _, _ in
        persistenceCallCount += 1
        return Habit(name: "Unexpected", cadence: .daily, target: 1)
      },
      update: { _, _, _, _ in
        persistenceCallCount += 1
      }
    )
    let model = HabitFormModel(mode: .new)
    model.targetText = "1.5"

    let savedHabit = model.save(using: persistence, at: .now, timeZone: timeZone)

    #expect(savedHabit == nil)
    #expect(model.error(for: .name) == .emptyName)
    #expect(model.error(for: .target) == .invalidTarget)
    #expect(model.persistenceError == nil)
    #expect(persistenceCallCount == 0)
  }

  @Test("failed Save retains every draft value and retries the same submission")
  func failedSaveRetainsEveryDraftValueAndRetriesSameSubmission() throws {
    let timeZone = try #require(TimeZone(identifier: "UTC"))
    let instant = Date(timeIntervalSince1970: 1_725_214_400)
    let pinnedWeekdays = try #require(
      PinnedWeekdays(
        rawValue: PinnedWeekdays.tuesday.rawValue | PinnedWeekdays.saturday.rawValue
      ))
    let reminderTime = try #require(ReminderTime(hour: 23, minute: 59))
    let expectedFields = HabitEditableFields(
      name: "Evening walk",
      target: 4,
      unit: "laps",
      pinnedWeekdays: pinnedWeekdays,
      reminderTime: reminderTime
    )
    let expectedHabit = Habit(
      name: expectedFields.name,
      cadence: .weekly,
      target: expectedFields.target,
      unit: expectedFields.unit,
      pinnedWeekdays: pinnedWeekdays,
      reminderTime: reminderTime
    )
    var saveAttempts = 0
    var receivedFields: [HabitEditableFields] = []
    var receivedCadences: [HabitCadence] = []
    let persistence = HabitFormPersistence(
      create: { fields, cadence, _, _ in
        saveAttempts += 1
        receivedFields.append(fields)
        receivedCadences.append(cadence)
        if saveAttempts == 1 {
          throw TestSaveFailure.expected
        }
        return expectedHabit
      },
      update: { _, _, _, _ in
        Issue.record("New Save must not dispatch update")
      }
    )
    let model = HabitFormModel(mode: .new)
    model.name = expectedFields.name
    model.targetText = String(expectedFields.target)
    model.unit = expectedFields.unit
    model.selectCadence(.weekly)
    model.togglePinnedWeekday(.tuesday)
    model.togglePinnedWeekday(.saturday)
    model.reminderTime = reminderTime

    #expect(model.save(using: persistence, at: instant, timeZone: timeZone) == nil)
    #expect(model.name == expectedFields.name)
    #expect(model.targetText == String(expectedFields.target))
    #expect(model.unit == expectedFields.unit)
    #expect(model.cadence == .weekly)
    #expect(model.pinnedWeekdays == pinnedWeekdays)
    #expect(model.reminderTime == reminderTime)
    #expect(model.persistenceError == "Unable to save right now.")
    #expect(saveAttempts == 1)

    _ = model.title
    _ = model.error(for: .name)
    #expect(saveAttempts == 1)

    #expect(model.save(using: persistence, at: instant, timeZone: timeZone) === expectedHabit)
    #expect(receivedFields == [expectedFields, expectedFields])
    #expect(receivedCadences == [.weekly, .weekly])
    #expect(model.persistenceError == nil)
    #expect(saveAttempts == 2)
  }

  @Test("discarding an unsaved draft performs no persistence")
  func discardingUnsavedDraftPerformsNoPersistence() {
    var persistenceCallCount = 0
    let persistence = HabitFormPersistence(
      create: { _, _, _, _ in
        persistenceCallCount += 1
        return Habit(name: "Unexpected", cadence: .daily, target: 1)
      },
      update: { _, _, _, _ in
        persistenceCallCount += 1
      }
    )

    do {
      let model = HabitFormModel(mode: .new)
      model.name = "Discard me"
      _ = model.title
      _ = persistence
    }

    #expect(persistenceCallCount == 0)
  }
}

private enum TestSaveFailure: LocalizedError {
  case expected

  var errorDescription: String? {
    "Unable to save right now."
  }
}
