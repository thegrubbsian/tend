import Foundation
import TendCore

enum JournalRoute: Equatable, Sendable {
  case overview
  case compose(LocalDate)
  case entry(UUID)
}
