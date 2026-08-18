import Foundation
import SwiftData
import SwiftUI
import TendCore

struct TodayDestinationChrome: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  @Query private var habits: [Habit]
  @Query private var goals: [Goal]
  @State private var isPresentingNewHabit = false
  @State private var nextGoalTransition: Date?
  @State private var timelineDate: Date?
  private let reminders: any ReminderRuntimeClient
  private let fixedDate: Date?

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

  @ViewBuilder
  var body: some View {
    if let fixedDate {
      content(for: fixedDate)
    } else {
      ZStack {
        if let timelineDate {
          content(for: timelineDate)
        } else {
          Color.clear
            .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
            .accessibilityHidden(true)
        }

        // Reset only the schedule iterator so Today logging state survives transition changes.
        TimelineView(
          LocalDayTimelineSchedule(
            calendar: localCalendar,
            earlierTransition: nextGoalTransition
          )
        ) { timeline in
          Color.clear
            .task(id: timeline.date) {
              updateTimelineDate(timeline.date)
            }
        }
        .id(nextGoalTransition)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
      if habits.isEmpty && goals.isEmpty {
        TodayFirstLaunchView(
          instant: date,
          onPlantHabit: {
            isPresentingNewHabit = true
          }
        )
        .onAppear {
          updateGoalTransition(nil)
        }
      } else {
        TodayView(
          habits: habits,
          goals: goals,
          instant: date,
          fixedOperationInstant: fixedDate,
          onPlantHabit: {
            isPresentingNewHabit = true
          },
          onGoalTransitionChange: updateGoalTransition,
          reminderRefresh: {
            reminders.refresh()
          }
        )
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Today")
    .accessibilityIdentifier("shell.destination.today")
    .sheet(isPresented: $isPresentingNewHabit) {
      HabitFormView(
        mode: .new,
        reminderRefresh: {
          reminders.refresh()
        },
        requestReminderAuthorization: {
          await reminders.requestAuthorizationIfNeeded()
        }
      )
    }
  }

  private func updateGoalTransition(_ transition: Date?) {
    guard fixedDate == nil, nextGoalTransition != transition else { return }
    nextGoalTransition = transition
  }

  private func updateTimelineDate(_ date: Date) {
    guard timelineDate != date else { return }
    timelineDate = date
  }
}
