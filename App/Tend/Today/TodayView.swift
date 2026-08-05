import Foundation
import SwiftData
import SwiftUI
import TendCore

struct TodayView: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.locale) private var locale
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.timeZone) private var timeZone

  let habits: [Habit]
  let instant: Date
  let onPlantHabit: () -> Void

  @State private var model: TodayModel?

  var body: some View {
    Group {
      if let presentation = model?.presentation {
        presentationView(presentation)
      } else {
        Color.clear
          .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
          .accessibilityHidden(true)
      }
    }
    .task(id: refreshStamp) {
      refresh()
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else {
        return
      }
      refresh()
    }
  }

  private var refreshContext: TodayRefreshContext {
    var localCalendar = calendar
    localCalendar.timeZone = timeZone
    return TodayRefreshContext(
      instant: instant,
      timeZone: timeZone,
      calendar: localCalendar,
      locale: locale
    )
  }

  private var refreshStamp: TodayViewRefreshStamp {
    TodayViewRefreshStamp(
      habits: habits,
      context: refreshContext
    )
  }

  @ViewBuilder
  private func presentationView(_ presentation: TodayPresentation) -> some View {
    switch presentation {
    case .firstLaunch:
      TodayFirstLaunchView(
        instant: instant,
        onPlantHabit: onPlantHabit
      )
    case .inactiveOnly:
      scrollSurface(identifier: "today.inactive") {
        TodayDashboardHeader(
          instant: instant,
          title: "Today",
          fractionText: nil,
          message: "No active habits."
        )
      }
    case .dashboard(let dashboard):
      scrollSurface(identifier: "today.dashboard") {
        TodayDashboardHeader(
          instant: instant,
          title: "Today",
          fractionText: dashboard.fractionText,
          message: nil
        )

        if dashboard.showsAllTended {
          Text("All tended.")
            .almanacTextStyle(.meaningfulNumeral(.title3))
            .foregroundStyle(AlmanacPalette.moss)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("today.all-tended")
        }

        if !dashboard.toTendRows.isEmpty {
          TodayDashboardSection(
            title: "TO TEND",
            identifier: "today.section.to-tend",
            rows: dashboard.toTendRows,
            retry: retry
          )
        }

        if !dashboard.tendedRows.isEmpty {
          TodayDashboardSection(
            title: "TENDED",
            identifier: "today.section.tended",
            rows: dashboard.tendedRows,
            retry: retry
          )
        }
      }
    }
  }

  private func scrollSurface<Content: View>(
    identifier: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
        content()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(maxWidth: AlmanacMetrics.readableContentWidth)
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.horizontal, AlmanacMetrics.screenPadding)
      .padding(.top, AlmanacMetrics.spacingSmall)
      .padding(.bottom, AlmanacMetrics.spacingLarge)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(identifier)
    }
    .scrollIndicators(.hidden)
    .overlay {
      GeometryReader { geometry in
        VStack(spacing: 0) {
          AlmanacPalette.paper
            .frame(height: geometry.safeAreaInsets.top)
          Spacer(minLength: 0)
        }
        .ignoresSafeArea()
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
    .background(AlmanacPalette.paper)
  }

  private func refresh() {
    let currentModel: TodayModel
    if let model {
      currentModel = model
    } else {
      let createdModel = TodayModel(context: modelContext)
      model = createdModel
      currentModel = createdModel
    }
    currentModel.refresh(
      habits: habits,
      context: refreshContext
    )
  }

  private func retry(_ row: TodayHabitRow) {
    model?.retry(
      habitID: row.id,
      habits: habits,
      context: refreshContext
    )
  }
}

struct TodayFirstLaunchView: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.locale) private var locale
  @Environment(\.timeZone) private var timeZone

  let instant: Date
  let onPlantHabit: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(verbatim: dateEyebrow)
        .almanacTextStyle(.label)

      Text("Today")
        .almanacTextStyle(.screenTitle)
        .padding(.top, 6)

      ScrollView {
        introduction
          .padding(.top, AlmanacMetrics.spacingExtraLarge)
          .padding(.bottom, AlmanacMetrics.tabPillHeight)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity)
    }
    .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
  }

  private var introduction: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
      Text("Tend is a quiet place to grow the habits you want to keep.")
        .almanacTextStyle(.body)
        .fixedSize(horizontal: false, vertical: true)

      Button("Plant a habit", action: onPlantHabit)
        .buttonStyle(AlmanacPrimaryButtonStyle())
        .accessibilityHint("Opens the new habit form.")
        .accessibilityIdentifier("today.plant-habit")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("today.empty")
  }

  private var dateEyebrow: String {
    let weekdayStyle = Date.FormatStyle(
      locale: locale,
      calendar: calendar,
      timeZone: timeZone
    )
    .weekday(.wide)
    let monthDayStyle = Date.FormatStyle(
      locale: locale,
      calendar: calendar,
      timeZone: timeZone
    )
    .month(.wide)
    .day()

    let weekday = instant.formatted(weekdayStyle)
    let monthDay = instant.formatted(monthDayStyle)
    return "\(weekday) · \(monthDay)".uppercased(with: locale)
  }
}

private struct TodayDashboardHeader: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let instant: Date
  let title: String
  let fractionText: String?
  let message: String?

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(instant, format: .dateTime.weekday(.wide).month(.wide).day()).almanacTextStyle(.label)
        .foregroundStyle(AlmanacPalette.inkMuted)
        .textCase(.uppercase)
        .accessibilityAddTraits(.isHeader)

      heading

      if let message {
        Text(message).almanacTextStyle(.body)
          .foregroundStyle(AlmanacPalette.inkMuted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private var heading: some View {
    if let fractionText {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
          titleText
          fractionTextView(fractionText)
        }
      } else {
        HStack(alignment: .firstTextBaseline, spacing: AlmanacMetrics.spacingMedium) {
          titleText
          Spacer(minLength: AlmanacMetrics.spacingMedium)
          fractionTextView(fractionText)
        }
      }
    } else {
      titleText
    }
  }

  private var titleText: some View {
    Text(title).almanacTextStyle(.screenTitle)
      .foregroundStyle(AlmanacPalette.ink)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("today.title")
      .accessibilityAddTraits(.isHeader)
  }

  private func fractionTextView(_ fractionText: String) -> some View {
    Text(fractionText).almanacTextStyle(.meaningfulNumeral(.title))
      .foregroundStyle(AlmanacPalette.moss)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel(fractionText)
      .accessibilityIdentifier("today.summary")
  }
}

private struct TodayDashboardSection: View {
  let title: String
  let identifier: String
  let rows: [TodayHabitRow]
  let retry: (TodayHabitRow) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(title).almanacTextStyle(.label)
        .foregroundStyle(AlmanacPalette.inkMuted)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(.isHeader)

      VStack(spacing: AlmanacMetrics.spacingSmall) {
        ForEach(rows) { row in
          TodayHabitCard(row: row) {
            retry(row)
          }
        }
      }
    }
  }
}

private struct TodayHabitCard: View {

  let row: TodayHabitRow
  let retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      facts

      if let failure = row.failure {
        Button(failure.retryTitle, action: retry)
          .buttonStyle(AlmanacPrimaryButtonStyle())
          .accessibilityLabel("Retry \(row.name)")
          .accessibilityIdentifier("today.retry.\(row.name)")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(row.isMet ? 12 : AlmanacMetrics.spacingMedium)
    .background(AlmanacPalette.paperRaised)
    .clipShape(
      RoundedRectangle(
        cornerRadius: AlmanacMetrics.cardRadius,
        style: .continuous
      )
    )
    .overlay {
      RoundedRectangle(
        cornerRadius: AlmanacMetrics.cardRadius,
        style: .continuous
      )
      .stroke(AlmanacPalette.hairline, lineWidth: 1)
    }
  }

  private var facts: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      HStack(alignment: .top, spacing: AlmanacMetrics.spacingMedium) {
        identity
        Spacer(minLength: AlmanacMetrics.spacingSmall)
        ring
      }

      if let riskText = row.riskText {
        HStack(alignment: .firstTextBaseline, spacing: AlmanacMetrics.spacingSmall) {
          Circle()
            .fill(AlmanacPalette.ochreDeep)
            .frame(width: 8, height: 8)
          Text(riskText).almanacTextStyle(.secondary)
            .fontWeight(.semibold)
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AlmanacPalette.ochreDeep)
      }

      if !row.isMet {

        if let facts = row.facts {
          TodayProgressTrack(fraction: facts.visualProgressFraction)
          Text(row.progressText).almanacTextStyle(.body)
            .foregroundStyle(AlmanacPalette.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
        } else if let failure = row.failure {
          Text(row.progressText).almanacTextStyle(.body)
            .foregroundStyle(AlmanacPalette.inkMuted)
          Text(failure.message).almanacTextStyle(.secondary)
            .foregroundStyle(AlmanacPalette.ochreDeep)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(row.accessibilityLabel)
    .accessibilityValue(row.accessibilityValue)
    .accessibilityIdentifier("today.row.\(row.name)")
  }

  private var identity: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall / 2) {
      Text(row.name).almanacTextStyle(.body)
        .fontWeight(.semibold)
        .foregroundStyle(AlmanacPalette.ink)
        .fixedSize(horizontal: false, vertical: true)

      if row.failure != nil {
        Text(row.requirementText).almanacTextStyle(.secondary)
          .foregroundStyle(AlmanacPalette.inkMuted)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityHidden(true)
      }

      Group {
        if row.isMet || row.failure != nil {
          Text(row.streakText)
            .almanacTextStyle(.secondary)
        } else {
          Text(row.streakText)
            .almanacTextStyle(.meaningfulNumeral(.title3))
        }
      }
      .foregroundStyle(streakColor)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityHidden(true)
    }
  }

  private var streakColor: Color {
    if row.isMet {
      return AlmanacPalette.moss
    }
    if row.riskText != nil {
      return AlmanacPalette.ochreDeep
    }
    return AlmanacPalette.inkMuted
  }

  private var ring: some View {
    TodayProgressRing(row: row)
      .frame(width: row.isMet ? 44 : 52, height: row.isMet ? 44 : 52)
      .fixedSize()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

private struct TodayProgressTrack: View {
  let fraction: Double

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(AlmanacPalette.paperSunken)
        Capsule()
          .fill(AlmanacPalette.moss)
          .frame(width: geometry.size.width * min(max(fraction, 0), 1))
      }
    }
    .frame(height: 8)
  }
}

private struct TodayProgressRing: View {
  let row: TodayHabitRow

  var body: some View {
    if row.isMet {
      Circle()
        .fill(AlmanacPalette.moss)
        .overlay {
          Image(systemName: "checkmark")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(AlmanacPalette.paper)
        }
    } else if let fraction = row.facts?.visualProgressFraction {
      if fraction == 0 {
        Circle()
          .stroke(AlmanacPalette.moss, lineWidth: 1.5)
      } else {
        ZStack {
          Circle()
            .stroke(AlmanacPalette.paperSunken, lineWidth: 4)
          Circle()
            .trim(from: 0, to: min(max(fraction, 0), 1))
            .stroke(
              AlmanacPalette.moss,
              style: StrokeStyle(lineWidth: 4, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
        }
      }
    } else {
      Circle()
        .fill(AlmanacPalette.paperSunken)
        .overlay {
          Circle()
            .stroke(AlmanacPalette.hairline, lineWidth: 1)
        }
    }
  }
}

private struct TodayViewRefreshStamp: Equatable {
  let instant: Date
  let timeZoneIdentifier: String
  let calendarIdentifier: String
  let localeIdentifier: String
  let habits: [HabitStamp]

  init(habits: [Habit], context: TodayRefreshContext) {
    instant = context.instant
    timeZoneIdentifier = context.timeZone.identifier
    calendarIdentifier = String(describing: context.calendar.identifier)
    localeIdentifier = context.locale.identifier
    self.habits =
      habits
      .map(HabitStamp.init)
      .sorted { $0.persistentID < $1.persistentID }
  }

  struct HabitStamp: Equatable {
    let persistentID: PersistentIdentifier
    let publicID: UUID
    let name: String
    let cadenceRawValue: String
    let target: Int
    let unit: String
    let pinnedWeekdaysRawValue: Int
    let reminderMinuteOfDay: Int?
    let isActive: Bool
    let createdAt: Date
    let bestStreak: Int
    let activityPeriods: [ActivityPeriodStamp]
    let buckets: [BucketStamp]
    let entries: [EntryStamp]

    init(_ habit: Habit) {
      persistentID = habit.persistentModelID
      publicID = habit.id
      name = habit.name
      cadenceRawValue = habit.cadenceRawValue
      target = habit.target
      unit = habit.unit
      pinnedWeekdaysRawValue = habit.pinnedWeekdaysRawValue
      reminderMinuteOfDay = habit.reminderMinuteOfDay
      isActive = habit.isActive
      createdAt = habit.createdAt
      bestStreak = habit.bestStreak
      activityPeriods = (habit.activityPeriods ?? [])
        .map(ActivityPeriodStamp.init)
        .sorted { $0.id.uuidString < $1.id.uuidString }
      buckets = (habit.buckets ?? [])
        .map(BucketStamp.init)
        .sorted { $0.id.uuidString < $1.id.uuidString }
      entries = (habit.entries ?? [])
        .map(EntryStamp.init)
        .sorted { $0.id.uuidString < $1.id.uuidString }
    }
  }

  struct ActivityPeriodStamp: Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?

    init(_ period: HabitActivityPeriod) {
      id = period.id
      startedAt = period.startedAt
      endedAt = period.endedAt
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
      entryIDs = (bucket.entries ?? []).map(\.id).sorted { $0.uuidString < $1.uuidString }
    }
  }

  struct EntryStamp: Equatable {
    let id: UUID
    let timestamp: Date
    let amount: Int
    let bucketID: UUID?

    init(_ entry: LogEntry) {
      id = entry.id
      timestamp = entry.timestamp
      amount = entry.amount
      bucketID = entry.bucket?.id
    }
  }
}
