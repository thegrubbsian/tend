#if DEBUG
  import Foundation
  import SwiftData
  import TendCore

  enum JournalExperienceUITestFixture {
    enum Scenario {
      case experience
      case loadFailure
    }

    static func seed(
      _ scenario: Scenario,
      context: ModelContext,
      at instant: Date,
      timeZone: TimeZone
    ) throws {
      switch scenario {
      case .experience:
        try seedExperience(context: context, at: instant, timeZone: timeZone)
      case .loadFailure:
        try seedLoadFailure(context: context, at: instant, timeZone: timeZone)
      }
    }

    private static func seedExperience(
      context: ModelContext,
      at instant: Date,
      timeZone: TimeZone
    ) throws {
      let today = try localDate("2026-08-05")
      let oldDay = try localDate("2026-07-10")
      let emptyDay = try localDate("2026-06-02")
      let entries = [
        JournalEntry(
          id: id("B1000000-0000-0000-0000-000000000001"),
          day: today,
          body: "Today among the tomatoes\nThe vines finally reached the trellis.",
          createdAt: instant,
          editedAt: instant
        ),
        JournalEntry(
          id: id("B1000000-0000-0000-0000-000000000002"),
          day: oldDay,
          body:
            "Rain settled across every seedling tray before the greenhouse doors opened\nA cool afternoon in the shed.",
          createdAt: instant.addingTimeInterval(-26 * 24 * 60 * 60),
          editedAt: instant.addingTimeInterval(-26 * 24 * 60 * 60)
        ),
        JournalEntry(
          id: id("B1000000-0000-0000-0000-000000000003"),
          day: emptyDay,
          body: "",
          createdAt: instant.addingTimeInterval(-64 * 24 * 60 * 60),
          editedAt: instant.addingTimeInterval(-64 * 24 * 60 * 60)
        ),
      ]
      for entry in entries {
        context.insert(entry)
      }

      let habit = try HabitManagementOperations(context: context).create(
        fields: HabitEditableFields(name: "Water seedlings", target: 1),
        cadence: .daily,
        at: instant,
        timeZone: timeZone
      )
      habit.id = id("B2000000-0000-0000-0000-000000000001")
      try context.save()
    }

    private static func seedLoadFailure(
      context: ModelContext,
      at instant: Date,
      timeZone: TimeZone
    ) throws {
      let day = try localDay(containing: instant, timeZone: timeZone)
      context.insert(
        JournalEntry(
          id: id("B3000000-0000-0000-0000-000000000001"),
          day: day,
          body: "First conflicting page",
          createdAt: instant,
          editedAt: instant
        )
      )
      context.insert(
        JournalEntry(
          id: id("B3000000-0000-0000-0000-000000000002"),
          day: day,
          body: "Second conflicting page",
          createdAt: instant,
          editedAt: instant
        )
      )
      try context.save()
    }

    private static func localDay(
      containing instant: Date,
      timeZone: TimeZone
    ) throws -> LocalDate {
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
        throw JournalExperienceFixtureError.invalidInstant
      }
      return localDate
    }

    private static func localDate(_ key: String) throws -> LocalDate {
      try LocalDate(validating: key)
    }

    private static func id(_ value: String) -> UUID {
      UUID(uuidString: value)!
    }
  }

  private enum JournalExperienceFixtureError: Error {
    case invalidInstant
  }
#endif
