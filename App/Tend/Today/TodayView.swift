import Accessibility
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
  let goals: [Goal]
  let journalEntries: [JournalEntry]
  let instant: Date
  let fixedOperationInstant: Date?
  let onPlantHabit: () -> Void
  let onGoalTransitionChange: (Date?) -> Void
  let reminderRefresh: ReminderRefreshSignal

  init(
    habits: [Habit],
    goals: [Goal],
    journalEntries: [JournalEntry],
    instant: Date,
    fixedOperationInstant: Date?,
    onPlantHabit: @escaping () -> Void,
    onGoalTransitionChange: @escaping (Date?) -> Void,
    reminderRefresh: @escaping ReminderRefreshSignal = {}
  ) {
    self.habits = habits
    self.goals = goals
    self.journalEntries = journalEntries
    self.instant = instant
    self.fixedOperationInstant = fixedOperationInstant
    self.onPlantHabit = onPlantHabit
    self.onGoalTransitionChange = onGoalTransitionChange
    self.reminderRefresh = reminderRefresh
  }

  @State private var model: TodayModel?
  @State private var loggingModel: TodayLoggingModel?

  var body: some View {
    let isPresentingLogSheet = loggingModel?.state.sheet != nil
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
    .onChange(of: model?.nextGoalTransition) { _, transition in
      onGoalTransitionChange(transition)
    }
    .sheet(
      isPresented: Binding(
        get: { isPresentingLogSheet },
        set: { isPresented in
          if !isPresented {
            loggingModel?.dismissSheet()
          }
        }
      )
    ) {
      if let loggingModel {
        QuantityLogSheet(
          model: loggingModel,
          habits: habits,
          makeContext: operationContext
        )
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .presentationBackground(AlmanacPalette.paper)
        .preferredColorScheme(.light)
      }
    }
    .sensoryFeedback(trigger: loggingModel?.state.feedback?.id) { _, _ in
      sensoryFeedback(for: loggingModel?.state.feedback?.kind)
    }
    .onChange(of: loggingModel?.state.feedback?.id) { _, feedbackID in
      guard let loggingModel, let feedbackID else { return }
      Task { @MainActor in
        await Task.yield()
        loggingModel.consumeFeedback(feedbackID)
      }
    }
    .onChange(of: loggingModel?.state.actionFailure) { _, failure in
      guard let failure else { return }
      AccessibilityNotification.Announcement(failure.message).post()
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
      goals: goals,
      journalEntries: journalEntries,
      context: refreshContext
    )
  }

  @ViewBuilder
  private func presentationView(_ presentation: TodayPresentation) -> some View {
    switch presentation {
    case .firstLaunch:
      TodayFirstLaunchView(
        instant: instant,
        onPlantHabit: onPlantHabit,
        goalRows: model?.goalRows ?? [],
        retryGoal: retry
      )
    case .inactiveOnly:
      scrollSurface(identifier: "today.inactive") {
        TodayDashboardHeader(
          instant: instant,
          title: "Today",
          fractionText: nil,
          message: "No active habits."
        )

        if let goalRows = model?.goalRows, !goalRows.isEmpty {
          TodayGoalsSection(rows: goalRows, retry: retry)
        }
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
            retry: retry,
            activate: activateCurrent,
            activateAtRisk: activateAtRisk,
            loggingState: loggingModel?.state,
            performUndo: undo
          )
        }

        if !dashboard.tendedRows.isEmpty {
          TodayDashboardSection(
            title: "TENDED",
            identifier: "today.section.tended",
            rows: dashboard.tendedRows,
            retry: retry,
            activate: activateCurrent,
            activateAtRisk: activateAtRisk,
            loggingState: loggingModel?.state,
            performUndo: undo
          )
        }

        if !dashboard.goalRows.isEmpty {
          TodayGoalsSection(rows: dashboard.goalRows, retry: retry)
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
    resolvedLoggingModel().refresh(
      habits: habits,
      goals: goals,
      journalEntries: journalEntries,
      context: operationContext()
    )
  }

  private func activateCurrent(_ row: TodayHabitRow) {
    resolvedLoggingModel().activateCurrent(
      habit: row.habit,
      habits: habits,
      context: operationContext()
    )
  }

  private func activateAtRisk(_ row: TodayHabitRow) {
    resolvedLoggingModel().activateAtRisk(
      habit: row.habit,
      habits: habits,
      context: operationContext()
    )
  }

  private func undo(_ row: TodayHabitRow) {
    resolvedLoggingModel().undo(
      habits: habits,
      context: operationContext()
    )
  }

  private func operationContext() -> TodayRefreshContext {
    var context = refreshContext
    context = TodayRefreshContext(
      instant: fixedOperationInstant ?? .now,
      timeZone: context.timeZone,
      calendar: context.calendar,
      locale: context.locale
    )
    return context
  }

  private func sensoryFeedback(
    for kind: TodayLoggingFeedback.Kind?
  ) -> SensoryFeedback? {
    switch kind {
    case .logged:
      .impact(weight: .light)
    case .completion:
      .success
    case .undo:
      .selection
    case nil:
      nil
    }
  }

  private func resolvedLoggingModel() -> TodayLoggingModel {
    if let loggingModel {
      return loggingModel
    }
    let todayModel = model ?? TodayModel(context: modelContext)
    model = todayModel
    let createdModel = TodayLoggingModel(
      context: modelContext,
      todayModel: todayModel,
      reminderRefresh: reminderRefresh
    )
    loggingModel = createdModel
    return createdModel
  }

  private func retry(_ row: TodayHabitRow) {
    model?.retry(
      habitID: row.id,
      habits: habits,
      journalEntries: journalEntries,
      context: operationContext()
    )
  }

  private func retry(_ row: TodayGoalRow) {
    model?.retry(
      goalID: row.id,
      habits: habits,
      goals: goals,
      journalEntries: journalEntries,
      context: operationContext()
    )
  }
}

struct TodayFirstLaunchView: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.locale) private var locale
  @Environment(\.timeZone) private var timeZone

  let instant: Date
  let onPlantHabit: () -> Void
  let goalRows: [TodayGoalRow]
  let retryGoal: (TodayGoalRow) -> Void

  init(
    instant: Date,
    onPlantHabit: @escaping () -> Void,
    goalRows: [TodayGoalRow] = [],
    retryGoal: @escaping (TodayGoalRow) -> Void = { _ in }
  ) {
    self.instant = instant
    self.onPlantHabit = onPlantHabit
    self.goalRows = goalRows
    self.retryGoal = retryGoal
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(verbatim: dateEyebrow)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(AlmanacPalette.inkMuted)
        .fixedSize(horizontal: false, vertical: true)

      Text("Today")
        .almanacTextStyle(.screenTitle)
        .padding(.top, 6)

      ScrollView {
        VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
          introduction

          if !goalRows.isEmpty {
            TodayGoalsSection(rows: goalRows, retry: retryGoal)
          }
        }
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
      Text(instant, format: .dateTime.weekday(.wide).month(.wide).day())
        .font(.footnote.weight(.semibold))
        .foregroundStyle(AlmanacPalette.inkMuted)
        .textCase(.uppercase)
        .fixedSize(horizontal: false, vertical: true)
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
  let activate: (TodayHabitRow) -> Void
  let activateAtRisk: (TodayHabitRow) -> Void
  let loggingState: TodayLoggingState?
  let performUndo: (TodayHabitRow) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(title).almanacTextStyle(.label)
        .foregroundStyle(AlmanacPalette.inkMuted)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(.isHeader)

      VStack(spacing: AlmanacMetrics.spacingSmall) {
        ForEach(rows) { row in
          TodayHabitCard(
            row: row,
            retry: {
              retry(row)
            },
            activate: row.isAvailable
              ? {
                activate(row)
              }
              : nil,
            activateAtRisk: row.riskText != nil
              ? {
                activateAtRisk(row)
              }
              : nil,
            actionFailure: loggingState?.actionFailure(for: row.id),
            undo: loggingState?.undo(for: row.id),
            performUndo: {
              performUndo(row)
            }
          )
        }
      }
    }
  }
}

private struct TodayGoalsSection: View {
  let rows: [TodayGoalRow]
  let retry: (TodayGoalRow) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text("GOALS").almanacTextStyle(.label)
        .foregroundStyle(AlmanacPalette.inkMuted)
        .accessibilityIdentifier("today.section.goals")
        .accessibilityAddTraits(.isHeader)

      VStack(spacing: AlmanacMetrics.spacingSmall) {
        ForEach(rows) { row in
          TodayGoalCard(
            row: row,
            retry: {
              retry(row)
            }
          )
        }
      }
    }
  }
}

private struct TodayGoalCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let row: TodayGoalRow
  let retry: () -> Void

  @ViewBuilder
  var body: some View {
    if let facts = row.facts, let progress = row.progress {
      availableCard(facts: facts, progress: progress)
    } else {
      unavailableCard
    }
  }

  private func availableCard(
    facts: TodayGoalFacts,
    progress: GoalDetailProgressFact
  ) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      summary(accent: accent(for: facts.standing.standing))

      GoalProgressView(
        progress: progress,
        progressText: row.progressText,
        standing: facts.standing.standing,
        expectedNormalizedProgress: row.expectedNormalizedProgress,
        standingText: row.standingText,
        style: .roster
      )
      .accessibilityHidden(true)

      metadata(accent: accent(for: facts.standing.standing))
    }
    .padding(AlmanacMetrics.spacingMedium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .almanacRaisedSurface()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(row.accessibilityLabel)
    .accessibilityValue(row.accessibilityValue)
    .accessibilityIdentifier(identifier)
  }

  private var unavailableCard: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall / 2) {
        Text(row.name)
          .font(.body.weight(.semibold))
          .foregroundStyle(AlmanacPalette.ink)
          .fixedSize(horizontal: false, vertical: true)

        Text(row.progressText)
          .almanacTextStyle(.secondary)
          .foregroundStyle(AlmanacPalette.inkMuted)
          .fixedSize(horizontal: false, vertical: true)

        Text(row.deadlineText)
          .almanacTextStyle(.caption)
          .foregroundStyle(AlmanacPalette.inkMuted)
          .fixedSize(horizontal: false, vertical: true)

        Text(row.standingText)
          .almanacTextStyle(.caption)
          .foregroundStyle(AlmanacPalette.inkMuted)
          .fixedSize(horizontal: false, vertical: true)

        if let failure = row.failure {
          Text(failure.message)
            .almanacTextStyle(.secondary)
            .foregroundStyle(AlmanacPalette.goalOchreDeep)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .accessibilityHidden(true)

      if let failure = row.failure {
        Button(failure.retryTitle, action: retry)
          .buttonStyle(.plain)
          .font(.body.weight(.semibold))
          .foregroundStyle(AlmanacPalette.moss)
          .frame(
            minWidth: AlmanacMetrics.minimumTarget,
            minHeight: AlmanacMetrics.minimumTarget
          )
          .contentShape(Rectangle())
          .accessibilityHint("Retries this goal.")
          .accessibilityIdentifier(
            "today.goal.retry.\(row.goal.id.uuidString.lowercased())"
          )
      }
    }
    .padding(AlmanacMetrics.spacingMedium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .almanacSunkenSurface()
    .accessibilityElement(children: .contain)
    .accessibilityLabel(row.accessibilityLabel)
    .accessibilityValue(row.accessibilityValue)
    .accessibilityIdentifier(identifier)
  }

  @ViewBuilder
  private func summary(accent: Color) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall / 2) {
        name
        progressText(accent: accent)
      }
    } else {
      HStack(alignment: .firstTextBaseline, spacing: AlmanacMetrics.spacingMedium) {
        name
          .frame(maxWidth: .infinity, alignment: .leading)
        progressText(accent: accent)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }

  private var name: some View {
    Text(row.name)
      .font(.body.weight(.semibold))
      .foregroundStyle(AlmanacPalette.ink)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func progressText(accent: Color) -> some View {
    Text(row.progressText)
      .almanacTextStyle(.meaningfulNumeral(.subheadline))
      .foregroundStyle(accent)
      .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private func metadata(accent: Color) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall / 2) {
        deadline
        standing(accent: accent)
      }
    } else {
      HStack(alignment: .firstTextBaseline, spacing: AlmanacMetrics.spacingMedium) {
        deadline
          .frame(maxWidth: .infinity, alignment: .leading)
        standing(accent: accent)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }

  private var deadline: some View {
    Text(row.deadlineText)
      .almanacTextStyle(.caption)
      .multilineTextAlignment(.leading)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func standing(accent: Color) -> some View {
    Text(row.standingText)
      .font(.caption.weight(.semibold))
      .foregroundStyle(accent)
      .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func accent(for standing: GoalStanding) -> Color {
    switch standing {
    case .onPace:
      AlmanacPalette.moss
    case .behind:
      AlmanacPalette.goalOchreDeep
    case .pastDue:
      AlmanacPalette.withered
    }
  }

  private var identifier: String {
    "today.goal.\(row.goal.id.uuidString.lowercased())"
  }
}

private struct TodayHabitCard: View {

  let row: TodayHabitRow
  let retry: () -> Void
  let activate: (() -> Void)?
  let activateAtRisk: (() -> Void)?
  let actionFailure: TodayLoggingInlineFailure?
  let undo: TodayLogUndo?
  let performUndo: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      facts

      if let actionFailure {
        Text(actionFailure.message)
          .almanacTextStyle(.secondary)
          .foregroundStyle(AlmanacPalette.ochreDeep)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("today.action-error.\(row.name)")
      }

      if let undo {
        TodayLogUndoRow(
          undo: undo,
          habitName: row.name,
          identifier: "today.undo.\(row.name)",
          actionIdentifier: "today.undo.action.\(row.name)",
          action: performUndo
        )
      }
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
      .allowsHitTesting(false)
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
        if let activateAtRisk {
          Button(action: activateAtRisk) {
            riskLabel(riskText)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Log \(riskScopeLabel) for \(row.name)")
          .accessibilityValue(riskText)
          .accessibilityHint(
            row.habit.unit == "times" ? "Logs one instance" : "Opens log sheet"
          )
          .accessibilityIdentifier("today.risk.\(row.name)")
        } else {
          riskLabel(riskText)
        }
      }

      if !row.isMet {

        if let facts = row.facts {
          Group {
            TodayProgressTrack(fraction: facts.visualProgressFraction)
            Text(row.progressText).almanacTextStyle(.body)
              .foregroundStyle(AlmanacPalette.inkMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
          .accessibilityElement(children: .ignore)
          .accessibilityHidden(activate != nil)
        } else if let failure = row.failure {
          Text(row.progressText).almanacTextStyle(.body)
            .foregroundStyle(AlmanacPalette.inkMuted)
          Text(failure.message).almanacTextStyle(.secondary)
            .foregroundStyle(AlmanacPalette.ochreDeep)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .accessibilityElement(children: activate == nil ? .ignore : .contain)
    .accessibilityLabel(activate == nil ? row.accessibilityLabel : "")
    .accessibilityValue(activate == nil ? row.accessibilityValue : "")
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
    .accessibilityHidden(activate != nil)
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

  @ViewBuilder
  private var ring: some View {
    if let activate {
      Button(action: activate) {
        ringVisual
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(row.accessibilityLabel)
      .accessibilityValue(row.accessibilityValue)
      .accessibilityHint(row.habit.unit == "times" ? "Logs one instance" : "Opens log sheet")
      .accessibilityIdentifier("today.log.\(row.name)")
    } else {
      ringVisual
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }

  private var ringVisual: some View {
    TodayProgressRing(row: row)
      .frame(width: row.isMet ? 44 : 52, height: row.isMet ? 44 : 52)
      .fixedSize()
  }

  private func riskLabel(_ riskText: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: AlmanacMetrics.spacingSmall) {
      Circle()
        .fill(AlmanacPalette.ochreDeep)
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
      Text(riskText).almanacTextStyle(.secondary)
        .fontWeight(.semibold)
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(AlmanacPalette.ochreDeep)
    .frame(minHeight: AlmanacMetrics.minimumTarget)
    .contentShape(Rectangle())
  }

  private var riskScopeLabel: String {
    row.facts?.snapshot.cadence == .weekly ? "Last Week" : "Yesterday"
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
  private struct MotionState: Hashable {
    let fraction: Double?
    let isMet: Bool
  }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let row: TodayHabitRow

  var body: some View {
    let isMet = row.isMet
    if reduceMotion {
      ZStack {
        ring
          .id(motionState)
          .transition(.opacity)
      }
      .animation(.easeOut(duration: 0.2), value: motionState)
    } else {
      ZStack {
        ring
          .transition(.opacity)
      }
      .animation(.easeOut(duration: 0.25), value: motionState.fraction)
      .animation(.easeInOut(duration: 0.2), value: motionState.isMet)
      .keyframeAnimator(initialValue: 1.0, trigger: isMet) { content, scale in
        content.scaleEffect(isMet ? scale : 1)
      } keyframes: { _ in
        SpringKeyframe(1.06, duration: 0.225, spring: .smooth)
        SpringKeyframe(1, duration: 0.225, spring: .smooth)
      }
    }
  }

  private var motionState: MotionState {
    MotionState(
      fraction: row.facts?.visualProgressFraction,
      isMet: row.isMet
    )
  }

  @ViewBuilder
  private var ring: some View {
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
          .overlay {
            loggingGlyph
          }
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
          loggingGlyph
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

  private var loggingGlyph: some View {
    Image(systemName: "plus")
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(AlmanacPalette.mossDeep)
      .accessibilityHidden(true)
  }
}

private struct TodayViewRefreshStamp: Equatable {
  let instant: Date
  let timeZoneIdentifier: String
  let calendarIdentifier: String
  let localeIdentifier: String
  let habits: [HabitStamp]
  let goals: [GoalStamp]
  let journalEntries: [JournalStamp]

  init(
    habits: [Habit],
    goals: [Goal],
    journalEntries: [JournalEntry],
    context: TodayRefreshContext
  ) {
    instant = context.instant
    timeZoneIdentifier = context.timeZone.identifier
    calendarIdentifier = String(describing: context.calendar.identifier)
    localeIdentifier = context.locale.identifier
    self.habits =
      habits
      .map(HabitStamp.init)
      .sorted { $0.persistentID < $1.persistentID }
    self.goals =
      goals
      .map(GoalStamp.init)
      .sorted { $0.persistentID < $1.persistentID }
    var seenJournalIDs: Set<PersistentIdentifier> = []
    self.journalEntries =
      journalEntries
      .compactMap { entry in
        let persistentID = entry.persistentModelID
        guard seenJournalIDs.insert(persistentID).inserted else { return nil }
        return JournalStamp(entry)
      }
      .sorted { $0.persistentID < $1.persistentID }
  }

  struct JournalStamp: Equatable {
    let persistentID: PersistentIdentifier
    let publicID: UUID
    let dayKey: String

    init(_ entry: JournalEntry) {
      persistentID = entry.persistentModelID
      publicID = entry.id
      dayKey = entry.dayKey
    }
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

  struct GoalStamp: Equatable {
    let persistentID: PersistentIdentifier
    let publicID: UUID
    let name: String
    let kindRawValue: String
    let target: Int
    let unit: String
    let baseline: Int?
    let deadlineKey: String?
    let createdAt: Date
    let closureRawValue: String?
    let entriesRelationshipPresent: Bool
    let readingsRelationshipPresent: Bool
    let entries: [GoalEntryStamp]
    let readings: [GoalReadingStamp]

    init(_ goal: Goal) {
      persistentID = goal.persistentModelID
      publicID = goal.id
      name = goal.name
      kindRawValue = goal.kindRawValue
      target = goal.target
      unit = goal.unit
      baseline = goal.baseline
      deadlineKey = goal.deadlineKey
      createdAt = goal.createdAt
      closureRawValue = goal.closureRawValue
      let goalEntries = goal.entries
      let goalReadings = goal.readings
      entriesRelationshipPresent = goalEntries != nil
      readingsRelationshipPresent = goalReadings != nil
      entries = (goalEntries ?? [])
        .map(GoalEntryStamp.init)
        .sorted { $0.persistentID < $1.persistentID }
      readings = (goalReadings ?? [])
        .map(GoalReadingStamp.init)
        .sorted { $0.persistentID < $1.persistentID }
    }
  }

  struct GoalEntryStamp: Equatable {
    let persistentID: PersistentIdentifier
    let publicID: UUID
    let amount: Int
    let assignedDateKey: String
    let appendedAt: Date
    let appendSequence: Int
    let goalID: PersistentIdentifier?

    init(_ entry: GoalEntry) {
      persistentID = entry.persistentModelID
      publicID = entry.id
      amount = entry.amount
      assignedDateKey = entry.assignedDateKey
      appendedAt = entry.appendedAt
      appendSequence = entry.appendSequence
      goalID = entry.goal?.persistentModelID
    }
  }

  struct GoalReadingStamp: Equatable {
    let persistentID: PersistentIdentifier
    let publicID: UUID
    let value: Int
    let assignedDateKey: String
    let appendedAt: Date
    let appendSequence: Int
    let goalID: PersistentIdentifier?

    init(_ reading: GoalReading) {
      persistentID = reading.persistentModelID
      publicID = reading.id
      value = reading.value
      assignedDateKey = reading.assignedDateKey
      appendedAt = reading.appendedAt
      appendSequence = reading.appendSequence
      goalID = reading.goal?.persistentModelID
    }
  }
}
