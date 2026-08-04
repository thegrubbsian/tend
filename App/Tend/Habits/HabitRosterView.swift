import SwiftData
import SwiftUI
import TendCore

struct HabitRosterView: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.locale) private var locale
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.timeZone) private var timeZone

  private let context: ModelContext

  @State private var model: HabitRosterModel
  @State private var presentedForm: HabitRosterForm?
  @State private var selectedHabit: HabitRosterSelection?

  init(context: ModelContext) {
    self.context = context
    _model = State(initialValue: HabitRosterModel(context: context))
  }

  var body: some View {
    TimelineView(LocalDayTimelineSchedule(calendar: localDayCalendar)) { timeline in
      List {
        titleRow

        if let rosterErrorMessage = model.rosterErrorMessage {
          HabitRosterLoadErrorCard(
            message: rosterErrorMessage,
            retry: model.retryRefresh
          )
          .modifier(HabitRosterListRowModifier())
        }

        if model.activeRows.isEmpty, model.inactiveRows.isEmpty,
          model.rosterErrorMessage == nil
        {
          emptyState
            .modifier(HabitRosterListRowModifier(verticalInset: AlmanacMetrics.spacingLarge))
        } else {
          rosterSection(title: "Active", rows: model.activeRows)
          rosterSection(title: "Inactive", rows: model.inactiveRows)
        }
      }
      .listStyle(.plain)
      .listRowSpacing(0)
      .scrollContentBackground(.hidden)
      .contentMargins(.horizontal, 0, for: .scrollContent)
      .contentMargins(.top, 0, for: .scrollContent)
      .onAppear {
        refresh(at: timeline.date)
      }
      .onChange(of: timeline.date) { _, date in
        refresh(at: date)
      }
    }
    .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        refresh(at: .now)
      }
    }
    .onChange(of: timeZone.identifier) { _, _ in
      refresh(at: .now)
    }
    .sheet(
      item: $presentedForm,
      onDismiss: {
        refresh(at: .now)
      }
    ) { form in
      HabitFormView(mode: form.mode)
    }
    .sheet(item: deletionConfirmationBinding) { confirmation in
      HabitRosterDeletionSheet(
        confirmation: confirmation,
        model: model,
        timeZone: timeZone,
        calendar: localDayCalendar,
        locale: locale
      )
      .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
      .presentationDragIndicator(.visible)
    }
    .fullScreenCover(
      item: $selectedHabit,
      onDismiss: {
        refresh(at: .now)
      }
    ) { selection in
      HabitDetailView(habit: selection.habit, context: context) {
        selectedHabit = nil
      }
    }
  }

  private var localDayCalendar: Calendar {
    var localDayCalendar = calendar
    localDayCalendar.timeZone = timeZone
    return localDayCalendar
  }

  private var titleRow: some View {
    HStack(alignment: .center, spacing: AlmanacMetrics.spacingMedium) {
      Text("All Habits")
        .almanacTextStyle(.screenTitle)
        .accessibilityAddTraits(.isHeader)

      Spacer(minLength: 0)

      Button {
        presentedForm = .new
      } label: {
        Image(systemName: "plus")
          .font(.body.weight(.bold))
          .foregroundStyle(AlmanacPalette.paper)
          .frame(width: 40, height: 40)
          .background(AlmanacPalette.moss, in: Circle())
      }
      .buttonStyle(.plain)
      .frame(
        minWidth: AlmanacMetrics.minimumTarget,
        minHeight: AlmanacMetrics.minimumTarget
      )
      .contentShape(Rectangle())
      .accessibilityLabel("New habit")
      .accessibilityHint("Opens a new habit form.")
      .accessibilityIdentifier("habits.add")
    }
    .modifier(HabitRosterListRowModifier(verticalInset: AlmanacMetrics.spacingMedium))
  }

  private var emptyState: some View {
    VStack(spacing: AlmanacMetrics.spacingMedium) {
      AlmanacIcon.today
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(AlmanacPalette.moss)
        .accessibilityHidden(true)

      VStack(spacing: AlmanacMetrics.spacingSmall) {
        Text("Plant your first habit")
          .font(.headline)

        Text("Use Add to begin tending a daily or weekly practice.")
          .almanacTextStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(AlmanacMetrics.spacingLarge)
    .almanacSunkenSurface()
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("habits.empty")
  }

  @ViewBuilder
  private func rosterSection(title: String, rows: [HabitRosterRow]) -> some View {
    if !rows.isEmpty {
      Text(title)
        .almanacTextStyle(.label)
        .accessibilityAddTraits(.isHeader)
        .modifier(HabitRosterSectionHeaderModifier(hasPrecedingSection: title == "Inactive"))

      ForEach(rows) { row in
        HabitRosterRowCard(row: row, retryStreak: model.retryRefresh)
          .modifier(
            HabitRosterActionsModifier(
              row: row,
              isMutationInFlight: model.isMutationInFlight(for: row.habit),
              perform: { perform($0, on: row) }
            )
          )
          .onTapGesture {
            select(row)
          }
          .accessibilityAddTraits(.isButton)
          .accessibilityAction {
            select(row)
          }
          .modifier(HabitRosterListRowModifier(verticalInset: AlmanacMetrics.spacingSmall / 2))

        if let failure = operationFailure(for: row) {
          HabitRosterOperationErrorCard(
            failure: failure,
            retry: retryOperation,
            dismiss: model.dismissOperationError
          )
          .modifier(HabitRosterListRowModifier(verticalInset: AlmanacMetrics.spacingSmall / 2))
        }
      }
    }
  }

  private var deletionConfirmationBinding: Binding<HabitRosterDeletionConfirmation?> {
    Binding(
      get: { model.deletionConfirmation },
      set: { confirmation in
        if confirmation == nil {
          model.cancelDeletion()
        }
      }
    )
  }

  private func refresh(at instant: Date) {
    model.refresh(
      at: instant,
      timeZone: timeZone,
      calendar: localDayCalendar,
      locale: locale
    )

    if let selectedHabit,
      !model.activeRows.contains(where: { $0.id == selectedHabit.id }),
      !model.inactiveRows.contains(where: { $0.id == selectedHabit.id })
    {
      self.selectedHabit = nil
    }
  }

  private func retryOperation() {
    model.retryOperation(
      at: .now,
      timeZone: timeZone,
      calendar: localDayCalendar,
      locale: locale
    )
  }

  private func select(_ row: HabitRosterRow) {
    guard !model.isMutationInFlight(for: row.habit) else { return }
    selectedHabit = HabitRosterSelection(id: row.id, habit: row.habit)
  }

  private func perform(_ action: HabitRosterAction, on row: HabitRosterRow) {
    switch action {
    case .edit:
      presentedForm = .edit(row.habit)
    case .archive:
      model.archive(
        row.habit,
        at: .now,
        timeZone: timeZone,
        calendar: localDayCalendar,
        locale: locale
      )
    case .reactivate:
      model.reactivate(
        row.habit,
        at: .now,
        timeZone: timeZone,
        calendar: localDayCalendar,
        locale: locale
      )
    case .delete:
      model.requestDeletion(of: row.habit)
    }
  }

  private func operationFailure(for row: HabitRosterRow) -> HabitRosterOperationFailure? {
    guard let failure = model.operationError,
      failure.habitID == row.id,
      model.deletionConfirmation == nil
    else {
      return nil
    }
    return failure
  }
}

private struct HabitRosterSelection: Identifiable {
  let id: PersistentIdentifier
  let habit: Habit
}

private enum HabitRosterForm: Identifiable {
  case new
  case edit(Habit)

  var id: String {
    switch self {
    case .new:
      "new"
    case .edit(let habit):
      "edit-\(habit.id.uuidString)"
    }
  }

  var mode: HabitFormMode {
    switch self {
    case .new:
      .new
    case .edit(let habit):
      .edit(habit)
    }
  }
}

private struct HabitRosterListRowModifier: ViewModifier {
  var verticalInset: CGFloat = 0

  func body(content: Content) -> some View {
    content
      .listRowInsets(
        EdgeInsets(
          top: verticalInset,
          leading: 0,
          bottom: verticalInset,
          trailing: 0
        )
      )
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
  }
}

private struct HabitRosterSectionHeaderModifier: ViewModifier {
  let hasPrecedingSection: Bool

  func body(content: Content) -> some View {
    content
      .modifier(HabitRosterListRowModifier())
      .padding(
        .top, hasPrecedingSection ? AlmanacMetrics.spacingLarge : AlmanacMetrics.spacingSmall
      )
      .padding(.bottom, AlmanacMetrics.spacingSmall / 2)
  }
}

private struct HabitRosterRowCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let row: HabitRosterRow
  let retryStreak: () -> Void

  @ViewBuilder
  var body: some View {
    if row.isStreakRetryAvailable {
      accessibleRow
        .accessibilityAction(named: "Retry streak", retryStreak)
    } else {
      accessibleRow
    }
  }

  private var accessibleRow: some View {
    Group {
      if row.streakTone == .inactive {
        rowContent
          .almanacSunkenSurface(radius: AlmanacMetrics.cardRadius)
      } else {
        rowContent
          .almanacRaisedSurface()
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(row.accessibilityLabel)
    .accessibilityValue(row.accessibilityValue)
    .accessibilityIdentifier("habits.row.\(row.habit.id.uuidString)")
  }

  @ViewBuilder
  private var rowContent: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
        identity
        streak(alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, AlmanacMetrics.spacingMedium)
      .padding(.vertical, 12)
    } else {
      HStack(alignment: .center, spacing: AlmanacMetrics.spacingMedium) {
        identity
          .layoutPriority(1)

        Spacer(minLength: 0)

        streak(alignment: .trailing)
      }
      .padding(.horizontal, AlmanacMetrics.spacingMedium)
      .padding(.vertical, 12)
    }
  }

  private var identity: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall / 2) {
      Text(row.name)
        .font(.body.weight(.semibold))
        .foregroundStyle(row.streakTone == .inactive ? AlmanacPalette.inkMuted : AlmanacPalette.ink)
        .fixedSize(horizontal: false, vertical: true)

      Text(row.metadataText)
        .almanacTextStyle(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func streak(alignment: HorizontalAlignment) -> some View {
    VStack(alignment: alignment, spacing: AlmanacMetrics.spacingSmall / 2) {
      Text(row.streakText)
        .almanacTextStyle(.meaningfulNumeral(.body))
        .foregroundStyle(streakColor)
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        .fixedSize(horizontal: false, vertical: true)

      if row.isStreakRetryAvailable {
        Button("Try again", action: retryStreak)
          .font(.caption.weight(.semibold))
          .foregroundStyle(AlmanacPalette.clayDeep)
          .frame(minHeight: AlmanacMetrics.minimumTarget)
          .buttonStyle(.plain)
          .accessibilityHidden(true)
      }
    }
  }

  private var streakColor: Color {
    switch row.streakTone {
    case .normal:
      AlmanacPalette.moss
    case .atRisk:
      AlmanacPalette.ochreDeep
    case .inactive:
      AlmanacPalette.withered
    case .unavailable:
      AlmanacPalette.clayDeep
    }
  }
}

private struct HabitRosterActionsModifier: ViewModifier {
  let row: HabitRosterRow
  let isMutationInFlight: Bool
  let perform: (HabitRosterAction) -> Void

  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        ForEach(row.availableActions, id: \.self) { action in
          actionButton(action)
            .tint(tint(for: action))
        }
      }
      .contextMenu {
        ForEach(row.availableActions, id: \.self) { action in
          actionButton(action)
        }
      }
      .accessibilityAction(named: "Edit") {
        perform(.edit)
      }
      .accessibilityAction(named: row.habit.isActive ? "Archive" : "Reactivate") {
        perform(row.habit.isActive ? .archive : .reactivate)
      }
      .accessibilityAction(named: "Delete") {
        perform(.delete)
      }
  }

  private func actionButton(_ action: HabitRosterAction) -> some View {
    Button(role: action.isDestructive ? .destructive : nil) {
      perform(action)
    } label: {
      Label(action.title, systemImage: action.systemImage)
    }
    .disabled(isMutationInFlight)
    .accessibilityHint(action.accessibilityHint)
  }

  private func tint(for action: HabitRosterAction) -> Color {
    switch action {
    case .edit, .reactivate:
      AlmanacPalette.moss
    case .archive:
      AlmanacPalette.withered
    case .delete:
      AlmanacPalette.clayDeep
    }
  }
}

private struct HabitRosterLoadErrorCard: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(message)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AlmanacPalette.clayDeep)
        .fixedSize(horizontal: false, vertical: true)

      Button("Try again", action: retry)
        .font(.body.weight(.semibold))
        .foregroundStyle(AlmanacPalette.moss)
        .frame(minHeight: AlmanacMetrics.minimumTarget)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(AlmanacMetrics.spacingMedium)
    .almanacSunkenSurface()
    .accessibilityElement(children: .contain)
  }
}

private struct HabitRosterOperationErrorCard: View {
  let failure: HabitRosterOperationFailure
  let retry: () -> Void
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(failure.message)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AlmanacPalette.clayDeep)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: AlmanacMetrics.spacingMedium) {
        Button(failure.retryTitle, action: retry)
          .font(.body.weight(.semibold))
          .foregroundStyle(AlmanacPalette.moss)
          .frame(minHeight: AlmanacMetrics.minimumTarget)

        Button("Dismiss", action: dismiss)
          .font(.body)
          .foregroundStyle(AlmanacPalette.inkMuted)
          .frame(minHeight: AlmanacMetrics.minimumTarget)
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(AlmanacMetrics.spacingMedium)
    .almanacSunkenSurface()
  }
}

private struct HabitRosterDeletionSheet: View {
  @Environment(\.dismiss) private var dismiss

  let confirmation: HabitRosterDeletionConfirmation
  let model: HabitRosterModel
  let timeZone: TimeZone
  let calendar: Calendar
  let locale: Locale

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
        HStack(alignment: .top, spacing: AlmanacMetrics.spacingMedium) {
          Text(confirmation.title)
            .font(.system(.title2, design: .serif, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 1)

          Spacer(minLength: 0)

          Button {
            model.cancelDeletion()
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.body.weight(.semibold))
              .frame(
                minWidth: AlmanacMetrics.minimumTarget + AlmanacMetrics.spacingSmall,
                minHeight: AlmanacMetrics.minimumTarget + AlmanacMetrics.spacingSmall
              )
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Cancel deletion")
        }

        Text(confirmation.consequenceText)
          .almanacTextStyle(.body)
          .padding(.vertical, 1)
          .fixedSize(horizontal: false, vertical: true)

        if let failure = model.operationError,
          failure.habitID == confirmation.id
        {
          HabitRosterOperationErrorCard(
            failure: failure,
            retry: retryOperation,
            dismiss: model.dismissOperationError
          )
        }
      }
      .padding(AlmanacMetrics.spacingLarge)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollIndicators(.hidden)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      actionButtons
        .padding(.horizontal, AlmanacMetrics.spacingLarge)
        .padding(.vertical, AlmanacMetrics.spacingMedium)
        .background(AlmanacPalette.paper)
    }
    .background(AlmanacPalette.paper.ignoresSafeArea())
  }

  private var actionButtons: some View {
    VStack(spacing: AlmanacMetrics.spacingSmall) {
      if confirmation.offersArchiveAlternative {
        Button {
          model.archiveInsteadOfDeleting(
            at: .now,
            timeZone: timeZone,
            calendar: calendar,
            locale: locale
          )
        } label: {
          Text("Archive instead")
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(AlmanacPrimaryButtonStyle())
        .frame(minHeight: AlmanacMetrics.minimumTarget + AlmanacMetrics.spacingSmall)
        .disabled(model.isMutationInFlight(for: confirmation.habit))
        .accessibilityHint(HabitRosterAction.archive.accessibilityHint)
      }

      Button(role: .destructive) {
        model.confirmDeletion(
          at: .now,
          timeZone: timeZone,
          calendar: calendar,
          locale: locale
        )
      } label: {
        Text("Delete permanently")
          .font(.body.weight(.semibold))
          .foregroundStyle(AlmanacPalette.paper)
          .padding(.vertical, 1)
          .frame(
            maxWidth: .infinity,
            minHeight: AlmanacMetrics.minimumTarget + AlmanacMetrics.spacingSmall
          )
          .background(AlmanacPalette.clayDeep, in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(model.isMutationInFlight(for: confirmation.habit))
      .accessibilityHint(HabitRosterAction.delete.accessibilityHint)
    }
  }

  private func retryOperation() {
    model.retryOperation(
      at: .now,
      timeZone: timeZone,
      calendar: calendar,
      locale: locale
    )
  }
}
