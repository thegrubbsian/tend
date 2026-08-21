import Foundation

struct AlmanacMonthGridGeometry: Equatable, Sendable {
  let leadingFillerCount: Int
  let trailingFillerCount: Int

  init(monthStart: Date, dayCount: Int, calendar: Calendar) {
    precondition(dayCount >= 0)
    let weekday = calendar.component(.weekday, from: monthStart)
    let leading = (weekday - calendar.firstWeekday + 7) % 7
    leadingFillerCount = leading
    trailingFillerCount = (7 - ((leading + dayCount) % 7)) % 7
  }
}
