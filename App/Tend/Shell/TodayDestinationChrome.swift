import Foundation
import SwiftData
import SwiftUI
import TendCore

struct TodayDestinationChrome: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  @Query private var habits: [Habit]
  @State private var isPresentingNewHabit = false
  private let fixedDate: Date?

  init(date: Date? = nil) {
    #if DEBUG
      fixedDate =
        date
        ?? TendUITestStore.fixedInstant(arguments: ProcessInfo.processInfo.arguments)
    #else
      fixedDate = date
    #endif
  }

  @ViewBuilder
  var body: some View {
    if let fixedDate {
      content(for: fixedDate)
    } else {
      TimelineView(LocalDayTimelineSchedule(calendar: localCalendar)) { _ in
        // The schedule entry invalidates at midnight; mutations still need the current instant.
        content(for: .now)
      }
    }
  }

  private var localCalendar: Calendar {
    var localCalendar = calendar
    localCalendar.timeZone = timeZone
    return localCalendar
  }

  private func content(for date: Date) -> some View {
    Group {
      if habits.isEmpty {
        TodayFirstLaunchView(
          instant: date,
          onPlantHabit: {
            isPresentingNewHabit = true
          }
        )
      } else {
        TodayView(
          habits: habits,
          instant: date,
          fixedOperationInstant: fixedDate,
          onPlantHabit: {
            isPresentingNewHabit = true
          }
        )
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Today")
    .accessibilityIdentifier("shell.destination.today")
    .sheet(isPresented: $isPresentingNewHabit) {
      HabitFormView(mode: .new)
    }
  }
}
