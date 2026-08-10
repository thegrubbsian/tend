import Foundation
import SwiftData
import SwiftUI

struct HabitsDestinationChrome: View {
  @Environment(\.modelContext) private var modelContext
  private let fixedDate: Date?
  private let reminders: any ReminderRuntimeClient

  init(
    reminders: any ReminderRuntimeClient,
    date: Date? = nil
  ) {
    self.reminders = reminders
    #if DEBUG
      fixedDate =
        date
        ?? TendUITestStore.fixedInstant(arguments: ProcessInfo.processInfo.arguments)
    #else
      fixedDate = date
    #endif
  }

  var body: some View {
    HabitRosterView(
      context: modelContext,
      reminders: reminders,
      date: fixedDate
    )
    .accessibilityIdentifier("shell.destination.habits")
  }
}
