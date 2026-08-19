import Foundation
import SwiftData

@Model
public final class JournalEntry {
  public var id: UUID = UUID()
  public var dayKey: String = ""
  public var body: String = ""
  public var createdAt: Date = Date()
  public var editedAt: Date = Date()

  public init(
    id: UUID = UUID(),
    day: LocalDate,
    body: String,
    createdAt: Date,
    editedAt: Date
  ) {
    self.id = id
    dayKey = day.rawValue
    self.body = body
    self.createdAt = createdAt
    self.editedAt = editedAt
  }
}
