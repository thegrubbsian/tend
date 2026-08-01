import Foundation
import Testing

@testable import TendCore

@Suite("Persisted model values")
struct ModelValueTests {
  @Test("cadence raw values remain stable")
  func cadenceRawValuesRemainStable() {
    #expect(HabitCadence.daily.rawValue == "daily")
    #expect(HabitCadence.weekly.rawValue == "weekly")
    #expect(HabitCadence(rawValue: "monthly") == nil)
  }

  @Test("settled verdict raw values remain stable")
  func settledVerdictRawValuesRemainStable() {
    #expect(BucketVerdict.met.rawValue == "met")
    #expect(BucketVerdict.missed.rawValue == "missed")
    #expect(BucketVerdict(rawValue: "pending-met") == nil)
  }

  @Test("weekday masks preserve every supported day")
  func weekdayMasksPreserveEverySupportedDay() throws {
    #expect(PinnedWeekdays.none.rawValue == 0)
    #expect(PinnedWeekdays.monday.rawValue == 1)
    #expect(PinnedWeekdays.tuesday.rawValue == 2)
    #expect(PinnedWeekdays.wednesday.rawValue == 4)
    #expect(PinnedWeekdays.thursday.rawValue == 8)
    #expect(PinnedWeekdays.friday.rawValue == 16)
    #expect(PinnedWeekdays.saturday.rawValue == 32)
    #expect(PinnedWeekdays.sunday.rawValue == 64)
    let noWeekdays = try #require(PinnedWeekdays(rawValue: 0))
    #expect(noWeekdays == .none)

    let weekdays = try #require(PinnedWeekdays(rawValue: 31))
    #expect(weekdays.contains(.monday))
    #expect(weekdays.contains(.friday))
    #expect(!weekdays.contains(.saturday))

    #expect(PinnedWeekdays(rawValue: 127) != nil)
    #expect(PinnedWeekdays(rawValue: -1) == nil)
    #expect(PinnedWeekdays(rawValue: 128) == nil)
  }

  @Test("reminder time accepts the complete local-day range")
  func reminderTimeAcceptsTheCompleteLocalDayRange() throws {
    let midnight = try #require(ReminderTime(hour: 0, minute: 0))
    #expect(midnight.rawValue == 0)
    #expect(midnight.hour == 0)
    #expect(midnight.minute == 0)

    let finalMinute = try #require(ReminderTime(hour: 23, minute: 59))
    #expect(finalMinute.rawValue == 1_439)
    #expect(finalMinute.hour == 23)
    #expect(finalMinute.minute == 59)

    #expect(ReminderTime(rawValue: -1) == nil)
    #expect(ReminderTime(rawValue: 1_440) == nil)
    #expect(ReminderTime(hour: -1, minute: 0) == nil)
    #expect(ReminderTime(hour: 24, minute: 0) == nil)
    #expect(ReminderTime(hour: 12, minute: -1) == nil)
    #expect(ReminderTime(hour: 12, minute: 60) == nil)
  }
  @Test("persisted values encode as scalars and round-trip")
  func persistedValuesEncodeAsScalarsAndRoundTrip() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let cadence = try encoder.encode(HabitCadence.daily)
    #expect(String(decoding: cadence, as: UTF8.self) == "\"daily\"")
    #expect(try decoder.decode(HabitCadence.self, from: cadence) == .daily)

    let verdict = try encoder.encode(BucketVerdict.missed)
    #expect(String(decoding: verdict, as: UTF8.self) == "\"missed\"")
    #expect(try decoder.decode(BucketVerdict.self, from: verdict) == .missed)

    let weekdays = try encoder.encode(#require(PinnedWeekdays(rawValue: 31)))
    #expect(String(decoding: weekdays, as: UTF8.self) == "31")
    #expect(try decoder.decode(PinnedWeekdays.self, from: weekdays).rawValue == 31)

    let reminder = try encoder.encode(#require(ReminderTime(hour: 6, minute: 30)))
    #expect(String(decoding: reminder, as: UTF8.self) == "390")
    #expect(try decoder.decode(ReminderTime.self, from: reminder).rawValue == 390)
  }

  @Test("persisted integer values reject invalid decoded state")
  func persistedIntegerValuesRejectInvalidDecodedState() {
    do {
      _ = try JSONDecoder().decode(PinnedWeekdays.self, from: Data("128".utf8))
      Issue.record("Expected an unsupported weekday mask to fail decoding")
    } catch DecodingError.dataCorrupted {
      // Expected.
    } catch {
      Issue.record("Expected dataCorrupted, got \(error)")
    }

    do {
      _ = try JSONDecoder().decode(ReminderTime.self, from: Data("1440".utf8))
      Issue.record("Expected an out-of-range reminder time to fail decoding")
    } catch DecodingError.dataCorrupted {
      // Expected.
    } catch {
      Issue.record("Expected dataCorrupted, got \(error)")
    }
  }

}
