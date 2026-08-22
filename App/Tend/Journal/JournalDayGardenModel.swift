import Foundation
import Observation
import SwiftData
import TendCore

struct JournalDayGardenRefreshContext: Equatable, Sendable {
  let instant: Date
  let timeZone: TimeZone
  let locale: Locale
}

@MainActor
struct JournalDayGardenOperations {
  typealias Project = (
    _ habits: [Habit],
    _ day: LocalDate,
    _ instant: Date,
    _ timeZone: TimeZone
  ) -> [JournalDayGardenRow]

  let project: Project

  init(_ project: @escaping Project) {
    self.project = project
  }

  static func live(context: ModelContext) -> Self {
    let query = JournalDayGardenQuery(context: context)
    return Self(query.rows)
  }
}

enum JournalDayGardenTone: Equatable, Sendable {
  case moss
  case withered
  case ochre
  case dormant
  case unavailable
}

struct JournalDayGardenPresentationRow: Equatable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let state: JournalDayGardenState
  let stateText: String
  let progressText: String
  let tone: JournalDayGardenTone
  let isLeafFilled: Bool
  let showsRetry: Bool
  let accessibilityValue: String
}

@MainActor
@Observable
final class JournalDayGardenModel {
  private(set) var rows: [JournalDayGardenPresentationRow] = []

  @ObservationIgnored private let operations: JournalDayGardenOperations
  @ObservationIgnored private var lastFingerprint: InputFingerprint?
  @ObservationIgnored private var lastRequest: RefreshRequest?

  convenience init(context: ModelContext) {
    self.init(operations: .live(context: context))
  }

  init(operations: JournalDayGardenOperations) {
    self.operations = operations
  }

  @discardableResult
  func refresh(
    day: LocalDate,
    habits: [Habit],
    context: JournalDayGardenRefreshContext,
    force: Bool = false
  ) -> Bool {
    let request = RefreshRequest(day: day, habits: habits, context: context)
    let fingerprint = InputFingerprint(day: day, habits: habits, context: context)
    guard force || fingerprint != lastFingerprint else { return false }

    let projected = operations.project(
      habits,
      day,
      context.instant,
      context.timeZone
    )
    rows = projected.map { PresentationFormatter(locale: context.locale).row(from: $0) }
    lastRequest = request
    lastFingerprint = fingerprint
    return true
  }

  func retry() {
    guard let lastRequest else { return }
    _ = refresh(
      day: lastRequest.day,
      habits: lastRequest.habits,
      context: lastRequest.context,
      force: true
    )
  }

  func clear() {
    rows = []
    lastRequest = nil
    lastFingerprint = nil
  }
}

extension JournalDayGardenModel {
  fileprivate struct RefreshRequest {
    let day: LocalDate
    let habits: [Habit]
    let context: JournalDayGardenRefreshContext
  }

  struct InputFingerprint: Equatable {
    let day: LocalDate
    let timeZoneIdentifier: String
    let localeIdentifier: String
    let habits: [HabitStamp]

    init(
      day: LocalDate,
      habits: [Habit],
      context: JournalDayGardenRefreshContext
    ) {
      self.day = day
      timeZoneIdentifier = context.timeZone.identifier
      localeIdentifier = context.locale.identifier
      self.habits = habits.map(HabitStamp.init).sorted {
        $0.id.uuidString < $1.id.uuidString
      }
    }
  }

  struct HabitStamp: Equatable {
    let id: UUID
    let name: String
    let cadenceRawValue: String
    let target: Int
    let unit: String
    let isActive: Bool
    let createdAt: Date
    let hasActivityPeriodsRelationship: Bool
    let activityPeriods: [ActivityPeriodStamp]
    let hasBucketsRelationship: Bool
    let buckets: [BucketStamp]
    let hasEntriesRelationship: Bool
    let entries: [EntryStamp]

    init(_ habit: Habit) {
      id = habit.id
      name = habit.name
      cadenceRawValue = habit.cadenceRawValue
      target = habit.target
      unit = habit.unit
      isActive = habit.isActive
      createdAt = habit.createdAt
      hasActivityPeriodsRelationship = habit.activityPeriods != nil
      activityPeriods = (habit.activityPeriods ?? []).map(ActivityPeriodStamp.init).sorted {
        $0.id.uuidString < $1.id.uuidString
      }
      hasBucketsRelationship = habit.buckets != nil
      buckets = (habit.buckets ?? []).map(BucketStamp.init).sorted {
        $0.id.uuidString < $1.id.uuidString
      }
      hasEntriesRelationship = habit.entries != nil
      entries = (habit.entries ?? []).map(EntryStamp.init).sorted {
        $0.id.uuidString < $1.id.uuidString
      }
    }
  }

  struct ActivityPeriodStamp: Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let habitID: UUID?

    init(_ period: HabitActivityPeriod) {
      id = period.id
      startedAt = period.startedAt
      endedAt = period.endedAt
      habitID = period.habit?.id
    }
  }

  struct BucketStamp: Equatable {
    let id: UUID
    let periodKey: String
    let startAt: Date
    let endAt: Date
    let cadenceRawValue: String
    let isExempt: Bool
    let finalizedAt: Date?
    let verdictRawValue: String?
    let targetSnapshot: Int?
    let unitSnapshot: String?
    let habitID: UUID?
    let hasEntriesRelationship: Bool
    let entryIDs: [UUID]

    init(_ bucket: HabitBucket) {
      id = bucket.id
      periodKey = bucket.periodKey
      startAt = bucket.startAt
      endAt = bucket.endAt
      cadenceRawValue = bucket.cadenceRawValue
      isExempt = bucket.isExempt
      finalizedAt = bucket.finalizedAt
      verdictRawValue = bucket.verdictRawValue
      targetSnapshot = bucket.targetSnapshot
      unitSnapshot = bucket.unitSnapshot
      habitID = bucket.habit?.id
      hasEntriesRelationship = bucket.entries != nil
      entryIDs = (bucket.entries ?? []).map(\.id).sorted {
        $0.uuidString < $1.uuidString
      }
    }
  }

  struct EntryStamp: Equatable {
    let id: UUID
    let timestamp: Date
    let amount: Int
    let habitID: UUID?
    let bucketID: UUID?

    init(_ entry: LogEntry) {
      id = entry.id
      timestamp = entry.timestamp
      amount = entry.amount
      habitID = entry.habit?.id
      bucketID = entry.bucket?.id
    }
  }

  fileprivate struct PresentationFormatter {
    let locale: Locale

    func row(from source: JournalDayGardenRow) -> JournalDayGardenPresentationRow {
      let stateText = stateText(source.state)
      let progressText = progressText(source)
      let showsRetry = source.state == .unavailable
      let accessibilityValue =
        showsRetry
        ? [stateText, progressText, "Try again"].joined(separator: ", ")
        : source.state == .exempt
          ? [stateText, progressText].joined(separator: ", ")
          : [progressText, stateText].joined(separator: ", ")
      return JournalDayGardenPresentationRow(
        id: source.habitID,
        name: source.name,
        state: source.state,
        stateText: stateText,
        progressText: progressText,
        tone: tone(source.state),
        isLeafFilled: isLeafFilled(source),
        showsRetry: showsRetry,
        accessibilityValue: accessibilityValue
      )
    }

    private func stateText(_ state: JournalDayGardenState) -> String {
      switch state {
      case .met: String(localized: "Met", locale: locale)
      case .missed: String(localized: "Missed", locale: locale)
      case .open: String(localized: "Open", locale: locale)
      case .grace: String(localized: "Grace", locale: locale)
      case .exempt: String(localized: "Exempt", locale: locale)
      case .unavailable: String(localized: "Unavailable", locale: locale)
      }
    }

    private func progressText(_ row: JournalDayGardenRow) -> String {
      if row.state == .exempt {
        return String(localized: "No requirement", locale: locale)
      }
      guard row.state != .unavailable,
        let progress = row.progress,
        let target = row.target,
        let unit = row.unit
      else {
        return String(localized: "Progress unavailable", locale: locale)
      }
      let displayedUnit = unit == "times" && target == 1 ? "time" : unit
      return String(
        localized: "\(integer(progress)) of \(integer(target)) \(displayedUnit)",
        locale: locale
      )
    }

    private func integer(_ value: Int) -> String {
      value.formatted(.number.locale(locale).grouping(.automatic))
    }

    private func tone(_ state: JournalDayGardenState) -> JournalDayGardenTone {
      switch state {
      case .met: .moss
      case .missed: .withered
      case .open, .grace: .ochre
      case .exempt: .dormant
      case .unavailable: .unavailable
      }
    }

    private func isLeafFilled(_ row: JournalDayGardenRow) -> Bool {
      switch row.state {
      case .met: true
      case .open, .grace: row.isRequirementMet == true
      case .missed, .exempt, .unavailable: false
      }
    }
  }
}
