import Foundation
import TendCore

enum JournalMonthCellState: Equatable, Sendable {
  case absent
  case written(entryID: UUID)
}

struct JournalMonthCell: Equatable, Identifiable, Sendable {
  let day: LocalDate
  let state: JournalMonthCellState
  let isToday: Bool

  var id: LocalDate { day }
}

struct JournalMonthProjection: Equatable, Sendable {
  let earliestMonth: LocalDate
  let selectedMonth: LocalDate
  let latestMonth: LocalDate
  let monthTitle: String
  let cells: [JournalMonthCell]
  let leadingFillerCount: Int
  let trailingFillerCount: Int
}
