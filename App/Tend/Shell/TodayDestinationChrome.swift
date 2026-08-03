import SwiftData
import SwiftUI
import TendCore

struct TodayDestinationChrome: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.locale) private var locale
  @Environment(\.timeZone) private var timeZone
  @Query private var habits: [Habit]
  @State private var isPresentingNewHabit = false
  private let fixedDate: Date?

  init(date: Date? = nil) {
    fixedDate = date
  }

  @ViewBuilder
  var body: some View {
    if let fixedDate {
      content(for: fixedDate)
    } else {
      TimelineView(LocalDayTimelineSchedule(calendar: localCalendar)) { context in
        content(for: context.date)
      }
    }
  }

  private var localCalendar: Calendar {
    var localCalendar = calendar
    localCalendar.timeZone = timeZone
    return localCalendar
  }

  private func content(for date: Date) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(verbatim: dateEyebrow(for: date))
        .almanacTextStyle(.label)

      Text("Today")
        .almanacTextStyle(.screenTitle)
        .padding(.top, 6)

      ScrollView {
        if habits.isEmpty {
          introduction
            .padding(.top, AlmanacMetrics.spacingExtraLarge)
            .padding(.bottom, AlmanacMetrics.tabPillHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .frame(maxWidth: .infinity)
    }
    .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Today")
    .accessibilityIdentifier("shell.destination.today")
    .sheet(isPresented: $isPresentingNewHabit) {
      HabitFormView(mode: .new)
    }
  }

  private var introduction: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
      Text("Tend is a quiet place to grow the habits you want to keep.")
        .almanacTextStyle(.body)
        .fixedSize(horizontal: false, vertical: true)

      Button("Plant a habit") {
        isPresentingNewHabit = true
      }
      .buttonStyle(AlmanacPrimaryButtonStyle())
      .accessibilityHint("Opens the new habit form.")
      .accessibilityIdentifier("today.plant-habit")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("today.empty")
  }

  private func dateEyebrow(for date: Date) -> String {
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

    let weekday = date.formatted(weekdayStyle)
    let monthDay = date.formatted(monthDayStyle)
    return "\(weekday) · \(monthDay)".uppercased(with: locale)
  }
}
