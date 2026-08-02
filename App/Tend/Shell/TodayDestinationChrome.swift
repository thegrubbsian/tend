import SwiftUI

struct TodayDestinationChrome: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.locale) private var locale
  @Environment(\.timeZone) private var timeZone
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

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Today")
    .accessibilityIdentifier("shell.destination.today")
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
