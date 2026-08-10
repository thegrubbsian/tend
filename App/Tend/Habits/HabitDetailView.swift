import Foundation
import SwiftData
import SwiftUI
import TendCore

struct HabitDetailView: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.locale) private var locale
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.timeZone) private var timeZone

  @State private var model: HabitDetailModel
  @State private var hasStarted = false
  @State private var hasLeftActiveScene = false

  private let onBack: () -> Void
  private let reminderRefresh: ReminderRefreshSignal
  private let requestReminderAuthorization: ReminderAuthorizationRequest
  private let synchronizesEnvironment: Bool
  private let operationInstant: Date?

  init(
    habit: Habit,
    context: ModelContext,
    reminders: any ReminderRuntimeClient,
    operationInstant: Date? = nil,
    onBack: @escaping () -> Void
  ) {
    let reminderRefresh: ReminderRefreshSignal = {
      reminders.refresh()
    }
    _model = State(
      initialValue: HabitDetailModel(
        habit: habit,
        context: context,
        now: { operationInstant ?? .now },
        reminderRefresh: reminderRefresh
      )
    )
    self.operationInstant = operationInstant
    self.reminderRefresh = reminderRefresh
    requestReminderAuthorization = {
      await reminders.requestAuthorizationIfNeeded()
    }
    self.onBack = onBack
    synchronizesEnvironment = true
  }

  init(
    model: HabitDetailModel,
    reminderRefresh: @escaping ReminderRefreshSignal = {},
    requestReminderAuthorization: @escaping ReminderAuthorizationRequest = {},
    onBack: @escaping () -> Void
  ) {
    _model = State(initialValue: model)
    self.reminderRefresh = reminderRefresh
    self.requestReminderAuthorization = requestReminderAuthorization
    self.onBack = onBack
    operationInstant = nil
    synchronizesEnvironment = false
  }

  var body: some View {
    VStack(spacing: 0) {
      navigationHeader

      ScrollView {
        ZStack(alignment: .topLeading) {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: model.dismissHistoryCallout)

          content
        }
      }
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize)
    }
    .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
    .sheet(isPresented: editPresentation) {
      if let habit = model.habitForEditing {
        HabitFormView(
          mode: .edit(habit),
          reminderRefresh: reminderRefresh,
          requestReminderAuthorization: requestReminderAuthorization,
          operationInstant: operationInstant,
          onSaved: model.editSaved
        )
      }
    }
    .onAppear {
      guard !hasStarted else { return }
      hasLeftActiveScene = false
      if synchronizesEnvironment {
        model.synchronizeEnvironment(
          calendar: calendar,
          locale: locale,
          timeZone: timeZone
        )
      }
      hasStarted = true
      model.start()
    }
    .onChange(of: scenePhase) { _, phase in
      guard hasStarted else { return }
      if phase == .active {
        guard hasLeftActiveScene else { return }
        hasLeftActiveScene = false
        model.sceneBecameActive()
      } else {
        hasLeftActiveScene = true
      }
    }
    .onChange(of: environmentDependencies) { _, dependencies in
      guard hasStarted, synchronizesEnvironment else { return }
      model.synchronizeEnvironment(
        calendar: dependencies.calendar,
        locale: dependencies.locale,
        timeZone: dependencies.timeZone
      )
    }
    .onDisappear {
      guard hasStarted else { return }
      hasStarted = false
      hasLeftActiveScene = false
      model.stop()
    }
  }

  private var navigationHeader: some View {
    HStack(spacing: AlmanacMetrics.spacingMedium) {
      Button(action: onBack) {
        HStack(spacing: AlmanacMetrics.spacingSmall / 2) {
          Image(systemName: "chevron.left")
            .font(.body.weight(.semibold))
          Text("Back")
        }
        .frame(minHeight: AlmanacMetrics.minimumTarget)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(AlmanacPalette.ink)
      .accessibilityLabel("Back")
      .accessibilityHint("Returns to habits")
      .accessibilityIdentifier("habitDetail.back")

      Spacer(minLength: 0)

      Button("Edit", action: model.presentEdit)
        .font(.body.weight(.semibold))
        .foregroundStyle(canEdit ? AlmanacPalette.clayDeep : AlmanacPalette.inkFaint)
        .frame(minWidth: AlmanacMetrics.minimumTarget, minHeight: AlmanacMetrics.minimumTarget)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(!canEdit)
        .accessibilityHint("Edits this habit")
        .accessibilityIdentifier("habitDetail.edit")
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
      Text(model.habitName)
        .almanacTextStyle(.screenTitle)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("habitDetail.title")

      if let presentation = model.presentation {
        verifiedContent(presentation)
      } else if let failure = model.loadFailure {
        HabitDetailFailureCard(
          failure: failure,
          retry: model.retryLoad
        )
      } else {
        ProgressView("Loading habit")
          .tint(AlmanacPalette.moss)
          .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
          .accessibilityIdentifier("habitDetail.loading")
      }
    }
    .padding(.top, AlmanacMetrics.spacingMedium)
    .padding(.bottom, AlmanacMetrics.spacingExtraLarge)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func verifiedContent(_ presentation: HabitDetailPresentation) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
      Text(presentation.metadataText)
        .almanacTextStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("habitDetail.metadata")

      streakFacts(presentation)

      if let currentStreakRiskText = presentation.currentStreakRiskText {
        riskCallout(currentStreakRiskText)
      }

      historySection(presentation)
      entriesSection(presentation)
      lifecycleSection(presentation)
    }
  }

  @ViewBuilder
  private func streakFacts(_ presentation: HabitDetailPresentation) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
        streakFact(
          label: "Current",
          value: presentation.currentStreak,
          unit: presentation.currentStreakUnit,
          fullText: presentation.currentStreakText,
          color: currentStreakColor(presentation)
        )
        streakFact(
          label: "Best",
          value: presentation.bestStreak,
          unit: presentation.bestStreakUnit,
          fullText: presentation.bestStreakText,
          color: AlmanacPalette.ink
        )
      }
    } else {
      HStack(alignment: .top, spacing: AlmanacMetrics.spacingMedium) {
        streakFact(
          label: "Current",
          value: presentation.currentStreak,
          unit: presentation.currentStreakUnit,
          fullText: presentation.currentStreakText,
          color: currentStreakColor(presentation)
        )
        .frame(maxWidth: .infinity, alignment: .leading)

        streakFact(
          label: "Best",
          value: presentation.bestStreak,
          unit: presentation.bestStreakUnit,
          fullText: presentation.bestStreakText,
          color: AlmanacPalette.ink
        )
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func streakFact(
    label: String,
    value: Int,
    unit: String,
    fullText: String,
    color: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(label)
        .almanacTextStyle(.label)

      HStack(alignment: .firstTextBaseline, spacing: AlmanacMetrics.spacingSmall) {
        Text(value, format: .number)
          .almanacTextStyle(.meaningfulNumeral(.largeTitle))
          .foregroundStyle(color)

        Text(unit)
          .almanacTextStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(label) streak, \(fullText)")
    .accessibilityIdentifier("habitDetail.streak.\(label.lowercased())")
  }

  private func currentStreakColor(_ presentation: HabitDetailPresentation) -> Color {
    if presentation.isAtRisk {
      return AlmanacPalette.ochre
    }
    return presentation.isActive ? AlmanacPalette.moss : AlmanacPalette.withered
  }

  private func riskCallout(_ message: String) -> some View {
    return HStack(spacing: AlmanacMetrics.spacingSmall) {
      Circle()
        .fill(AlmanacPalette.ochre)
        .frame(
          width: AlmanacMetrics.spacingSmall,
          height: AlmanacMetrics.spacingSmall
        )
        .accessibilityHidden(true)

      Text(message)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AlmanacPalette.ochreDeep)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, AlmanacMetrics.spacingMedium)
    .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget, alignment: .leading)
    .almanacRaisedSurface()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(message)
    .accessibilityIdentifier("habitDetail.risk")
  }

  private func historySection(_ presentation: HabitDetailPresentation) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
      monthControls(presentation)

      if presentation.cadence == .daily {
        dailyGarden(presentation)
      } else {
        weeklyGarden(presentation)
      }

      if let fact = model.selectedHistory {
        HabitDetailHistoryCallout(fact: fact)
      }

      HabitDetailLegend()
    }
    .accessibilityElement(children: .contain)
  }

  private func monthControls(_ presentation: HabitDetailPresentation) -> some View {
    HStack(spacing: AlmanacMetrics.spacingSmall) {
      monthButton(
        systemImage: "chevron.left",
        accessibilityLabel: "Previous month",
        isEnabled: model.canSelectPreviousMonth,
        action: model.selectPreviousMonth
      )

      Text(presentation.monthTitle)
        .almanacTextStyle(.label)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("habitDetail.month")

      monthButton(
        systemImage: "chevron.right",
        accessibilityLabel: "Next month",
        isEnabled: model.canSelectNextMonth,
        action: model.selectNextMonth
      )
    }
  }

  private func monthButton(
    systemImage: String,
    accessibilityLabel: String,
    isEnabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.body.weight(.semibold))
        .frame(
          width: AlmanacMetrics.minimumTarget,
          height: AlmanacMetrics.minimumTarget
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isEnabled ? AlmanacPalette.inkFaint : AlmanacPalette.hairline)
    .disabled(!isEnabled)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(presentationMonthAccessibilityValue)
    .accessibilityIdentifier(
      systemImage == "chevron.left" ? "habitDetail.month.previous" : "habitDetail.month.next"
    )
  }

  private var presentationMonthAccessibilityValue: String {
    model.presentation?.monthTitle ?? "Unavailable"
  }

  private func dailyGarden(_ presentation: HabitDetailPresentation) -> some View {
    let items = dailyGardenItems(presentation)
    let rowStarts = Array(stride(from: 0, to: items.count, by: 7))
    let weekdayLabels = HabitFormWeekday.localizedLabels(calendar: calendar, locale: locale)

    return VStack(spacing: AlmanacMetrics.spacingSmall) {
      HStack(spacing: 0) {
        ForEach(weekdayLabels.indices, id: \.self) { index in
          Text(weekdayLabels[index].short)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AlmanacPalette.inkMuted)
            .frame(
              width: AlmanacMetrics.minimumTarget,
              height: AlmanacMetrics.minimumTarget
            )
            .accessibilityLabel(weekdayLabels[index].accessibility)

          if index != weekdayLabels.indices.last {
            Spacer(minLength: 0)
          }
        }
      }

      ForEach(rowStarts, id: \.self) { rowStart in
        HStack(spacing: 0) {
          ForEach(0..<7, id: \.self) { column in
            let item = items[rowStart + column]
            if let fact = item.fact {
              historyButton(fact, fillsWidth: false)
            } else {
              HabitDetailPeriodSurface(state: .future)
                .frame(
                  width: AlmanacMetrics.minimumTarget,
                  height: AlmanacMetrics.minimumTarget
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            if column != 6 {
              Spacer(minLength: 0)
            }
          }
        }
      }
    }
  }

  private func weeklyGarden(_ presentation: HabitDetailPresentation) -> some View {
    VStack(spacing: AlmanacMetrics.spacingSmall) {
      ForEach(presentation.history) { fact in
        historyButton(fact, fillsWidth: true)
      }
    }
  }

  private func historyButton(
    _ fact: HabitDetailHistoryFact,
    fillsWidth: Bool
  ) -> some View {
    let isSelected = model.selectedHistory?.key == fact.key
    return Button {
      model.selectHistory(fact.key)
    } label: {
      HabitDetailPeriodSurface(state: fact.state)
        .overlay {
          if isSelected {
            RoundedRectangle(
              cornerRadius: AlmanacMetrics.gardenCellRadius,
              style: .continuous
            )
            .strokeBorder(AlmanacPalette.ink, lineWidth: AlmanacMetrics.gardenOutlineWidth)
          }
        }
        .frame(
          maxWidth: fillsWidth ? .infinity : AlmanacMetrics.minimumTarget,
          minHeight: AlmanacMetrics.minimumTarget,
          maxHeight: AlmanacMetrics.minimumTarget
        )
        .frame(width: fillsWidth ? nil : AlmanacMetrics.minimumTarget)
        .contentShape(
          RoundedRectangle(
            cornerRadius: AlmanacMetrics.gardenCellRadius,
            style: .continuous
          )
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(fact.accessibilityLabel)
    .accessibilityHint("Shows details for this period")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier("habitDetail.history.\(fact.key)")
  }

  private func dailyGardenItems(
    _ presentation: HabitDetailPresentation
  ) -> [HabitDetailDailyGardenItem] {
    var items: [HabitDetailDailyGardenItem] = []
    items.reserveCapacity(
      presentation.dailyLeadingFillerCount
        + presentation.history.count
        + presentation.dailyTrailingFillerCount
    )

    for index in 0..<presentation.dailyLeadingFillerCount {
      items.append(HabitDetailDailyGardenItem(id: "leading-\(index)", fact: nil))
    }
    items.append(
      contentsOf: presentation.history.map {
        HabitDetailDailyGardenItem(id: $0.key, fact: $0)
      })
    for index in 0..<presentation.dailyTrailingFillerCount {
      items.append(HabitDetailDailyGardenItem(id: "trailing-\(index)", fact: nil))
    }
    return items
  }

  private func entriesSection(_ presentation: HabitDetailPresentation) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
      Text("Recent entries")
        .almanacTextStyle(.label)
        .accessibilityAddTraits(.isHeader)

      if presentation.entries.isEmpty {
        Text("No editable entries in the open or grace period.")
          .almanacTextStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("habitDetail.entries.empty")
      } else {
        VStack(spacing: 0) {
          ForEach(Array(presentation.entries.enumerated()), id: \.element.id) { index, entry in
            HabitDetailEntryRow(
              entry: entry,
              isDisabled: model.isOperationInFlight,
              delete: { model.deleteEntry(id: entry.id) }
            )

            if index != presentation.entries.indices.last {
              Rectangle()
                .fill(AlmanacPalette.hairline)
                .frame(height: 1)
                .accessibilityHidden(true)
            }
          }
        }
      }

      if let failure = operationFailure(placement: .entries) {
        HabitDetailOperationFailureCard(
          failure: failure,
          isDisabled: model.isOperationInFlight,
          retry: model.retryOperation,
          accessibilityIdentifier: "habitDetail.entries.failure"
        )
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func lifecycleSection(_ presentation: HabitDetailPresentation) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Button(presentation.isActive ? "Archive habit" : "Reactivate habit") {
        if presentation.isActive {
          model.archive()
        } else {
          model.reactivate()
        }
      }
      .font(.body.weight(.semibold))
      .foregroundStyle(
        presentation.isActive ? AlmanacPalette.inkMuted : AlmanacPalette.moss
      )
      .frame(minHeight: AlmanacMetrics.minimumTarget)
      .contentShape(Rectangle())
      .buttonStyle(.plain)
      .disabled(model.isOperationInFlight)
      .accessibilityHint(
        presentation.isActive
          ? "Pauses tracking without deleting history"
          : "Resumes tracking for the current period"
      )
      .accessibilityIdentifier(
        presentation.isActive ? "habitDetail.archive" : "habitDetail.reactivate"
      )

      if let failure = operationFailure(placement: .lifecycle) {
        HabitDetailOperationFailureCard(
          failure: failure,
          isDisabled: model.isOperationInFlight,
          retry: model.retryOperation,
          accessibilityIdentifier: "habitDetail.lifecycle.failure"
        )
      }
    }
  }

  private func operationFailure(
    placement: HabitDetailOperationFailure.Placement
  ) -> HabitDetailOperationFailure? {
    guard model.operationFailure?.placement == placement else { return nil }
    return model.operationFailure
  }

  private var canEdit: Bool {
    model.habitForEditing != nil
  }

  private var editPresentation: Binding<Bool> {
    Binding(
      get: { model.isPresentingEdit },
      set: { isPresented in
        if isPresented {
          model.presentEdit()
        } else {
          model.editCancelled()
        }
      }
    )
  }
  private var environmentDependencies: HabitDetailEnvironmentDependencies {
    HabitDetailEnvironmentDependencies(
      calendar: calendar,
      locale: locale,
      timeZone: timeZone
    )
  }

}

private struct HabitDetailEnvironmentDependencies: Equatable {
  let calendar: Calendar
  let locale: Locale
  let timeZone: TimeZone
}

private struct HabitDetailDailyGardenItem: Identifiable {
  let id: String
  let fact: HabitDetailHistoryFact?
}

private struct HabitDetailPeriodSurface: View {
  let state: HabitHistoryState

  var body: some View {
    Group {
      switch state {
      case .met:
        RoundedRectangle(
          cornerRadius: AlmanacMetrics.gardenCellRadius,
          style: .continuous
        )
        .fill(AlmanacPalette.moss)
      case .missed:
        RoundedRectangle(
          cornerRadius: AlmanacMetrics.gardenCellRadius,
          style: .continuous
        )
        .fill(AlmanacPalette.withered)
      case .open:
        raisedOutline(AlmanacPalette.clay)
      case .grace:
        raisedOutline(AlmanacPalette.ochre)
      case .inactive, .beforeCreation, .future:
        Color.clear
          .almanacSunkenSurface(radius: AlmanacMetrics.gardenCellRadius)
      }
    }
    .opacity(isDormant ? 0.45 : 1)
  }

  private var isDormant: Bool {
    switch state {
    case .inactive, .beforeCreation, .future:
      true
    case .met, .missed, .open, .grace:
      false
    }
  }
  private func raisedOutline(_ color: Color) -> some View {
    Color.clear
      .almanacRaisedSurface(radius: AlmanacMetrics.gardenCellRadius)
      .overlay {
        RoundedRectangle(
          cornerRadius: AlmanacMetrics.gardenCellRadius,
          style: .continuous
        )
        .strokeBorder(color, lineWidth: AlmanacMetrics.gardenOutlineWidth)
      }
  }
}

private struct HabitDetailHistoryCallout: View {
  let fact: HabitDetailHistoryFact

  var body: some View {
    Text(fact.calloutText)
      .almanacTextStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(AlmanacMetrics.spacingMedium)
      .frame(maxWidth: .infinity, alignment: .leading)
      .almanacRaisedSurface()
      .accessibilityLabel(fact.accessibilityLabel)
      .accessibilityIdentifier("habitDetail.history.callout")
  }
}

private struct HabitDetailLegend: View {
  var body: some View {
    HStack(spacing: AlmanacMetrics.spacingLarge) {
      legendItem("Met") {
        RoundedRectangle(
          cornerRadius: AlmanacMetrics.gardenCellRadius,
          style: .continuous
        )
        .fill(AlmanacPalette.moss)
      }
      legendItem("Missed") {
        RoundedRectangle(
          cornerRadius: AlmanacMetrics.gardenCellRadius,
          style: .continuous
        )
        .fill(AlmanacPalette.withered)
      }
      legendItem("Open") {
        Color.clear
          .almanacRaisedSurface(radius: AlmanacMetrics.gardenCellRadius)
          .overlay {
            RoundedRectangle(
              cornerRadius: AlmanacMetrics.gardenCellRadius,
              style: .continuous
            )
            .strokeBorder(AlmanacPalette.clay, lineWidth: AlmanacMetrics.gardenOutlineWidth)
          }
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Legend. Met, Missed, Open")
    .accessibilityIdentifier("habitDetail.legend")
  }

  private func legendItem<Swatch: View>(
    _ title: String,
    @ViewBuilder swatch: () -> Swatch
  ) -> some View {
    HStack(spacing: AlmanacMetrics.spacingSmall) {
      swatch()
        .frame(
          width: AlmanacMetrics.spacingMedium,
          height: AlmanacMetrics.spacingMedium
        )
        .accessibilityHidden(true)
      Text(title)
        .almanacTextStyle(.caption)
    }
  }
}

private struct HabitDetailEntryRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let entry: HabitDetailEntryFact
  let isDisabled: Bool
  let delete: () -> Void

  @ViewBuilder
  var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
        details
        deleteButton
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(.vertical, AlmanacMetrics.spacingSmall)
    } else {
      HStack(alignment: .center, spacing: AlmanacMetrics.spacingMedium) {
        details
        Spacer(minLength: 0)
        deleteButton
      }
      .padding(.vertical, AlmanacMetrics.spacingSmall)
    }
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall / 2) {
      Text(entry.scopeText)
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)

      Text("\(entry.timeText) · \(entry.amountText)")
        .almanacTextStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var deleteButton: some View {
    Button(action: delete) {
      Image(systemName: "minus.circle")
        .font(.title3.weight(.semibold))
        .frame(
          width: AlmanacMetrics.minimumTarget,
          height: AlmanacMetrics.minimumTarget
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isDisabled ? AlmanacPalette.inkFaint : AlmanacPalette.clayDeep)
    .disabled(isDisabled)
    .accessibilityLabel(entry.accessibilityLabel)
    .accessibilityHint("Deletes this contribution")
    .accessibilityIdentifier("habitDetail.entry.delete.\(entry.id.uuidString)")
  }
}

private struct HabitDetailFailureCard: View {
  let failure: HabitDetailLoadFailure
  let retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(failure.message)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AlmanacPalette.clayDeep)
        .fixedSize(horizontal: false, vertical: true)

      Button(failure.retryTitle, action: retry)
        .font(.body.weight(.semibold))
        .foregroundStyle(AlmanacPalette.moss)
        .frame(minHeight: AlmanacMetrics.minimumTarget)
        .buttonStyle(.plain)
        .accessibilityHint("Retries loading this habit")
        .accessibilityIdentifier("habitDetail.failure.retry")
    }
    .padding(AlmanacMetrics.spacingMedium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .almanacSunkenSurface()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("habitDetail.failure")
  }
}

private struct HabitDetailOperationFailureCard: View {
  let failure: HabitDetailOperationFailure
  let isDisabled: Bool
  let retry: () -> Void
  let accessibilityIdentifier: String

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(failure.message)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AlmanacPalette.clayDeep)
        .fixedSize(horizontal: false, vertical: true)

      Button(failure.retryTitle, action: retry)
        .font(.body.weight(.semibold))
        .foregroundStyle(isDisabled ? AlmanacPalette.inkFaint : AlmanacPalette.moss)
        .frame(minHeight: AlmanacMetrics.minimumTarget)
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityHint("Retries the failed action")
    }
    .padding(AlmanacMetrics.spacingMedium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .almanacRaisedSurface()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}

#if DEBUG
  @MainActor
  private struct HabitDetailPreviewHost: View {
    enum Kind {
      case daily
      case weekly
      case initialFailure
    }

    private let container: ModelContainer
    @State private var model: HabitDetailModel

    init(_ kind: Kind) {
      let graph = try! HabitDetailPreviewGraph.make(kind)
      container = graph.container
      _model = State(initialValue: graph.model)
    }

    var body: some View {
      HabitDetailView(model: model, onBack: {})
        .modelContainer(container)
    }
  }

  @MainActor
  private struct HabitDetailPreviewGraph {
    let container: ModelContainer
    let model: HabitDetailModel

    static func make(
      _ kind: HabitDetailPreviewHost.Kind
    ) throws -> HabitDetailPreviewGraph {
      let container = try TendModelContainer.inMemory()
      let context = container.mainContext
      let timeZone = try previewTimeZone()
      let cadence: HabitCadence = kind == .weekly ? .weekly : .daily
      let now = try previewDate("2026-08-03T12:00:00Z")
      let createdAt = try previewDate(
        cadence == .daily ? "2026-06-15T09:00:00Z" : "2026-05-11T09:00:00Z"
      )
      let habit = Habit(
        name: cadence == .daily
          ? "Walk the river path before the neighborhood wakes"
          : "Publish one thoughtful field note for the whole team",
        cadence: cadence,
        target: cadence == .daily ? 8_000 : 2,
        unit: cadence == .daily
          ? "steps along the river path"
          : "carefully edited field notes",
        pinnedWeekdays: cadence == .weekly
          ? PinnedWeekdays(
            rawValue: PinnedWeekdays.monday.rawValue | PinnedWeekdays.wednesday.rawValue
          ) ?? .none
          : .none,
        reminderTime: ReminderTime(rawValue: cadence == .daily ? 17 * 60 : 9 * 60 + 30),
        createdAt: createdAt,
        bestStreak: cadence == .daily ? 29 : 11
      )
      context.insert(habit)

      let activity = HabitActivityPeriod(startedAt: createdAt, habit: habit)
      context.insert(activity)

      let schedule = CalendarBucketSchedule(timeZone: timeZone)
      var periods: [CalendarBucketPeriod] = []
      var period = try schedule.period(containing: createdAt, cadence: cadence)
      let currentPeriod = try schedule.period(containing: now, cadence: cadence)
      while period.start <= currentPeriod.start {
        periods.append(period)
        if period.key == currentPeriod.key { break }
        period = try schedule.next(after: period)
      }

      var buckets: [HabitBucket] = []
      buckets.reserveCapacity(periods.count)
      for (index, period) in periods.enumerated() {
        let distanceFromCurrent = periods.count - index - 1
        let isProvisional = distanceFromCurrent <= 1
        let isInactive = distanceFromCurrent == (cadence == .daily ? 20 : 8)
        let verdict: BucketVerdict? =
          isProvisional || isInactive
          ? nil
          : (distanceFromCurrent == (cadence == .daily ? 22 : 10) ? .missed : .met)
        let bucket = HabitBucket(
          periodKey: period.key,
          startAt: period.start,
          endAt: period.end,
          cadence: cadence,
          isExempt: isInactive,
          finalizedAt: verdict == nil ? nil : period.graceEnd,
          verdict: verdict,
          targetSnapshot: verdict == nil ? nil : habit.target,
          unitSnapshot: verdict == nil ? nil : habit.unit,
          habit: habit
        )
        context.insert(bucket)
        buckets.append(bucket)
      }

      if let graceBucket = buckets.dropLast().last {
        context.insert(
          LogEntry(
            timestamp: graceBucket.endAt.addingTimeInterval(-2 * 60 * 60),
            amount: cadence == .daily ? 2_500 : 1,
            habit: habit,
            bucket: graceBucket
          )
        )
      }
      if let openBucket = buckets.last {
        context.insert(
          LogEntry(
            timestamp: now.addingTimeInterval(-45 * 60),
            amount: habit.target,
            habit: habit,
            bucket: openBucket
          )
        )
        context.insert(
          LogEntry(
            timestamp: now.addingTimeInterval(-3 * 60 * 60),
            amount: cadence == .daily ? 1_200 : 1,
            habit: habit,
            bucket: openBucket
          )
        )
      }
      try context.save()

      let operations: HabitDetailOperations
      if kind == .initialFailure {
        let computation = HabitDetailComputation(context: context)
        let gate = HabitDetailPreviewFailureGate()
        operations = .live(context: context) { habit, month, instant, timeZone in
          if gate.shouldFail {
            gate.shouldFail = false
            throw HabitDetailPreviewError.initialLoad
          }
          return try computation.snapshot(
            for: habit,
            selectedMonth: month,
            at: instant,
            timeZone: timeZone
          )
        }
      } else {
        operations = .live(context: context)
      }

      let model = HabitDetailModel(
        habit: habit,
        operations: operations,
        now: { now },
        timeZone: { timeZone },
        calendar: { previewCalendar(timeZone: timeZone) },
        locale: { Locale(identifier: "en_US") },
        boundaryScheduling: HabitDetailBoundaryScheduling { _, _ in
          HabitDetailBoundaryCancellation {}
        }
      )
      return HabitDetailPreviewGraph(container: container, model: model)
    }

    private static func previewDate(_ value: String) throws -> Date {
      guard let date = ISO8601DateFormatter().date(from: value) else {
        throw HabitDetailPreviewError.invalidDate
      }
      return date
    }

    private static func previewTimeZone() throws -> TimeZone {
      guard let timeZone = TimeZone(identifier: "UTC") else {
        throw HabitDetailPreviewError.invalidTimeZone
      }
      return timeZone
    }

    private static func previewCalendar(timeZone: TimeZone) -> Calendar {
      var calendar = Calendar(identifier: .gregorian)
      calendar.locale = Locale(identifier: "en_US")
      calendar.timeZone = timeZone
      calendar.firstWeekday = 2
      calendar.minimumDaysInFirstWeek = 4
      return calendar
    }
  }

  @MainActor
  private final class HabitDetailPreviewFailureGate {
    var shouldFail = true
  }

  private enum HabitDetailPreviewError: Error {
    case initialLoad
    case invalidDate
    case invalidTimeZone
  }

  #Preview("Daily") {
    HabitDetailPreviewHost(.daily)
  }

  #Preview("Weekly") {
    HabitDetailPreviewHost(.weekly)
  }

  #Preview("Initial failure") {
    HabitDetailPreviewHost(.initialFailure)
  }
#endif
