#if DEBUG
  import Foundation
  import SwiftData
  import TendCore

  @MainActor
  enum TodayJournalInvitationUITestFixture {
    enum Variant {
      case eligible
      case complete
      case unavailable
      case firstLaunch
      case inactive
      case allTended
      case journey
    }

    static func seed(
      _ variant: Variant,
      context: ModelContext,
      at instant: Date,
      timeZone: TimeZone
    ) throws {
      switch variant {
      case .eligible, .complete, .unavailable:
        try TodayGoalUITestFixture.seed(
          .mixed,
          context: context,
          at: instant,
          timeZone: timeZone
        )
      case .firstLaunch:
        break
      case .inactive:
        try TodayDashboardUITestFixture.seed(
          .inactive,
          context: context,
          at: instant,
          timeZone: timeZone
        )
      case .allTended:
        try TodayDashboardUITestFixture.seed(
          .allTended,
          context: context,
          at: instant,
          timeZone: timeZone
        )
      case .journey:
        try TodayDashboardUITestFixture.seed(
          .mixed,
          context: context,
          at: instant,
          timeZone: timeZone
        )
      }

      switch variant {
      case .complete:
        _ = try insertEntry(
          in: context,
          day: localDay(for: instant, timeZone: timeZone),
          body: "",
          instant: instant
        )
      case .unavailable:
        let entry = try insertEntry(
          in: context,
          day: localDay(for: instant, timeZone: timeZone),
          body: "Malformed Journal fixture",
          instant: instant
        )
        entry.dayKey = "not-a-local-day"
        try context.save()
      case .eligible, .firstLaunch, .inactive, .allTended, .journey:
        break
      }
    }

    private static func insertEntry(
      in context: ModelContext,
      day: LocalDate,
      body: String,
      instant: Date
    ) throws -> JournalEntry {
      let entry = JournalEntry(
        id: id("C1000000-0000-0000-0000-000000000001"),
        day: day,
        body: body,
        createdAt: instant,
        editedAt: instant
      )
      context.insert(entry)
      try context.save()
      return entry
    }

    private static func localDay(for instant: Date, timeZone: TimeZone) throws -> LocalDate {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = timeZone
      let components = calendar.dateComponents([.year, .month, .day], from: instant)
      guard
        let year = components.year,
        let month = components.month,
        let day = components.day,
        let localDay = LocalDate(year: year, month: month, day: day)
      else {
        throw FixtureError.invalidInstant
      }
      return localDay
    }

    private static func id(_ value: String) -> UUID {
      UUID(uuidString: value)!
    }

    private enum FixtureError: Error {
      case invalidInstant
    }
  }
#endif
