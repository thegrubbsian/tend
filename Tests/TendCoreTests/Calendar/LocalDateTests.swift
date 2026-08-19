import Foundation
import Testing

@testable import TendCore

@Suite("Local date")
struct LocalDateTests {
  @Test("local dates validate and round-trip one chronological key")
  func localDatesValidateAndRoundTrip() throws {
    let leapDay = try #require(LocalDate(year: 2024, month: 2, day: 29))

    #expect(leapDay.year == 2024)
    #expect(leapDay.month == 2)
    #expect(leapDay.day == 29)
    #expect(leapDay.rawValue == "2024-02-29")
    #expect(LocalDate(rawValue: leapDay.rawValue) == leapDay)
    #expect(LocalDate(year: 1, month: 1, day: 1)?.rawValue == "0001-01-01")
    #expect(LocalDate(year: 9_999, month: 12, day: 31)?.rawValue == "9999-12-31")

    let encoded = try JSONEncoder().encode(leapDay)
    #expect(String(decoding: encoded, as: UTF8.self) == "\"2024-02-29\"")
    #expect(try JSONDecoder().decode(LocalDate.self, from: encoded) == leapDay)
  }

  @Test("local dates reject malformed, impossible, and unsupported keys")
  func localDatesRejectInvalidKeys() {
    let malformed = [
      "2024-2-29", "2024-02-9", "24-02-29", "2024/02/29", "2024-02-29Z",
      "abcd-ef-gh", "", " 2024-02-29",
    ]
    for key in malformed {
      #expect(LocalDate(rawValue: key) == nil)
    }

    let impossible = [
      "0000-01-01", "10000-01-01", "2023-02-29", "2024-02-30", "2024-04-31",
      "2024-00-01", "2024-13-01", "2024-01-00", "2024-01-32",
    ]
    for key in impossible {
      #expect(LocalDate(rawValue: key) == nil)
    }

    #expect(LocalDate(year: 0, month: 1, day: 1) == nil)
    #expect(LocalDate(year: 10_000, month: 1, day: 1) == nil)
    #expect(LocalDate(year: 2023, month: 2, day: 29) == nil)
    #expect(throws: LocalDateError.malformedKey("2024-2-29")) {
      try LocalDate(validating: "2024-2-29")
    }
    #expect(throws: LocalDateError.invalidDate("2023-02-29")) {
      try LocalDate(validating: "2023-02-29")
    }
  }

  @Test("local date comparison is chronological across the supported range")
  func localDateComparisonIsChronological() throws {
    let dates = try [
      #require(LocalDate(rawValue: "9999-12-31")),
      #require(LocalDate(rawValue: "2024-02-29")),
      #require(LocalDate(rawValue: "2024-02-28")),
      #require(LocalDate(rawValue: "0001-01-01")),
      #require(LocalDate(rawValue: "2025-01-01")),
    ]
    let sorted = dates.sorted()

    #expect(
      sorted.map(\.rawValue) == [
        "0001-01-01", "2024-02-28", "2024-02-29", "2025-01-01", "9999-12-31",
      ])
    #expect(sorted.map(\.rawValue) == dates.map(\.rawValue).sorted())
  }

  @Test("adjacent local dates cross month, year, and leap boundaries")
  func adjacentLocalDatesCrossCalendarBoundaries() throws {
    let marchFirst = try #require(LocalDate(rawValue: "2024-03-01"))
    #expect(try marchFirst.previous().rawValue == "2024-02-29")
    #expect(try marchFirst.next().rawValue == "2024-03-02")

    let newYearsEve = try #require(LocalDate(rawValue: "2024-12-31"))
    #expect(try newYearsEve.next().rawValue == "2025-01-01")
    #expect(try newYearsEve.next().previous() == newYearsEve)

    let nonLeapFebruary = try #require(LocalDate(rawValue: "2023-02-28"))
    #expect(try nonLeapFebruary.next().rawValue == "2023-03-01")
  }

  @Test("local dates use proleptic Gregorian leap-year rules")
  func localDatesUseProlepticGregorianLeapYearRules() throws {
    #expect(LocalDate(rawValue: "1500-02-29") == nil)
    #expect(LocalDate(rawValue: "1600-02-29") != nil)

    let march1500 = try #require(LocalDate(rawValue: "1500-03-01"))
    let march1600 = try #require(LocalDate(rawValue: "1600-03-01"))
    #expect(try march1500.previous().rawValue == "1500-02-28")
    #expect(try march1600.previous().rawValue == "1600-02-29")
  }

  @Test("local dates remain continuous across the historical Gregorian cutover")
  func localDatesRemainContinuousAcrossHistoricalCutover() throws {
    let utc = try #require(TimeZone(identifier: "UTC"))
    let dates = try (4...15).map { day in
      try #require(LocalDate(rawValue: String(format: "1582-10-%02d", day)))
    }

    for index in dates.indices.dropLast() {
      #expect(try dates[index].next() == dates[index + 1])
      #expect(try dates[index + 1].previous() == dates[index])
      let start = try dates[index].start(in: utc)
      let nextStart = try dates[index + 1].start(in: utc)
      #expect(nextStart.timeIntervalSince(start) == 24 * 60 * 60)
    }
    #expect(
      try dates[0].start(in: utc)
        == Date(timeIntervalSince1970: -12_220_243_200)
    )
    #expect(
      try dates[dates.count - 1].start(in: utc)
        == Date(timeIntervalSince1970: -12_219_292_800)
    )
  }

  @Test("local date resolution uses an explicit time zone without changing its key")
  func localDateResolutionUsesExplicitTimeZone() throws {
    let localDate = try #require(LocalDate(rawValue: "2024-07-04"))
    let utc = try #require(TimeZone(identifier: "UTC"))
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))

    let utcStart = try localDate.start(in: utc)
    let losAngelesStart = try localDate.start(in: losAngeles)
    let tokyoStart = try localDate.start(in: tokyo)

    #expect(utcStart != losAngelesStart)
    #expect(utcStart != tokyoStart)
    #expect(dateComponents(of: utcStart, in: utc) == DateComponents(year: 2024, month: 7, day: 4))
    #expect(
      dateComponents(of: losAngelesStart, in: losAngeles)
        == DateComponents(year: 2024, month: 7, day: 4)
    )
    #expect(
      dateComponents(of: tokyoStart, in: tokyo) == DateComponents(year: 2024, month: 7, day: 4))
    #expect(localDate.rawValue == "2024-07-04")
  }

  @Test("adjacent local dates resolve across daylight-saving boundaries")
  func adjacentLocalDatesResolveAcrossDaylightSavingBoundaries() throws {
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let springForward = try #require(LocalDate(rawValue: "2024-03-10"))
    let springNext = try springForward.next()
    let fallBack = try #require(LocalDate(rawValue: "2024-11-03"))
    let fallNext = try fallBack.next()

    #expect(springNext.rawValue == "2024-03-11")
    #expect(
      try springNext.start(in: losAngeles).timeIntervalSince(springForward.start(in: losAngeles))
        == 23 * 60 * 60
    )
    #expect(fallNext.rawValue == "2024-11-04")
    #expect(
      try fallNext.start(in: losAngeles).timeIntervalSince(fallBack.start(in: losAngeles))
        == 25 * 60 * 60
    )
  }

  private func dateComponents(of date: Date, in timeZone: TimeZone) -> DateComponents {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    return calendar.dateComponents([.year, .month, .day], from: date)
  }
}
