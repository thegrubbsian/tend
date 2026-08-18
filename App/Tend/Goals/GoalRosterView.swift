import Foundation
import SwiftData
import SwiftUI
import TendCore

struct GoalRosterView: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.locale) private var locale
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.timeZone) private var timeZone

  private let context: ModelContext
  #if DEBUG
    private let fixedInstant: Date?
  #endif

  @State private var model: GoalRosterModel
  @State private var presentedForm: GoalRosterForm?
  @State private var selectedGoal: GoalRosterSelection?
  @State private var hasStarted = false
  @State private var hasLeftActiveScene = false

  init(context: ModelContext) {
    self.context = context
    _model = State(initialValue: GoalRosterModel(context: context))
    #if DEBUG
      fixedInstant = nil
    #endif
  }

  #if DEBUG
    init(context: ModelContext, fixedInstant: Date?) {
      self.context = context
      self.fixedInstant = fixedInstant
      _model = State(initialValue: GoalRosterModel(context: context))
    }
  #endif

  var body: some View {
    TimelineView(
      GoalRosterTimelineSchedule(
        calendar: localDayCalendar,
        domainTransition: model.nextRefreshInstant
      )
    ) { timeline in
      rosterList
        .onAppear {
          startOnce(at: timeline.date)
        }
        .onChange(of: timeline.date) { previousDate, date in
          guard hasStarted, previousDate != date else { return }
          refresh(at: date)
        }
    }
    .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
    .accessibilityIdentifier("goals.screen")
    .onChange(of: scenePhase) { _, phase in
      guard hasStarted else { return }
      if phase == .active {
        guard hasLeftActiveScene else { return }
        hasLeftActiveScene = false
        refreshCurrentContext()
      } else {
        hasLeftActiveScene = true
      }
    }
    .onChange(of: timeZone.identifier) { _, _ in
      guard hasStarted else { return }
      refreshCurrentContext()
    }
    .sheet(
      item: $presentedForm,
      onDismiss: {
        refreshCurrentContext()
      },
      content: { _ in
        GoalFormView(
          mode: .new,
          onSaved: refreshCurrentContext
        )
        .modelContext(context)
      }
    )
    .fullScreenCover(
      item: $selectedGoal,
      onDismiss: {
        refreshCurrentContext()
      },
      content: { selection in
        GoalDetailView(
          goal: selection.goal,
          context: context,
          onBack: closeDetail
        )
        .modelContext(context)
      }
    )
  }

  private var rosterList: some View {
    List {
      titleRow
        .modifier(GoalRosterListRowModifier(verticalInset: AlmanacMetrics.spacingMedium))

      if let loadFailure = model.loadFailure {
        GoalRosterLoadFailureCard(
          failure: loadFailure,
          retry: refreshCurrentContext
        )
        .modifier(GoalRosterListRowModifier(verticalInset: AlmanacMetrics.spacingSmall / 2))
      }

      if hasSavedRows {
        rosterRows(model.openRows)

        if !model.pastDueRows.isEmpty {
          Text("PAST DUE")
            .almanacTextStyle(.label)
            .accessibilityAddTraits(.isHeader)
            .modifier(
              GoalRosterSectionHeaderModifier(
                hasPrecedingSection: !model.openRows.isEmpty
              )
            )
            .accessibilityIdentifier("goals.pastDue")

          rosterRows(model.pastDueRows)
        }

        if !model.closedRows.isEmpty {
          closedDisclosure
            .modifier(
              GoalRosterListRowModifier(
                verticalInset: AlmanacMetrics.spacingSmall / 2
              )
            )

          if model.isClosedExpanded {
            rosterRows(model.closedRows)
          }
        }
      } else if model.loadFailure == nil {
        emptyState
          .modifier(
            GoalRosterListRowModifier(
              verticalInset: AlmanacMetrics.spacingLarge
            )
          )
      }
    }
    .listStyle(.plain)
    .listRowSpacing(0)
    .scrollContentBackground(.hidden)
    .contentMargins(.horizontal, 0, for: .scrollContent)
    .contentMargins(.top, 0, for: .scrollContent)
    .id("goals.list")
    .accessibilityIdentifier("goals.list")
  }

  private var titleRow: some View {
    HStack(alignment: .center, spacing: AlmanacMetrics.spacingMedium) {
      Text("Goals")
        .almanacTextStyle(.screenTitle)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      Spacer(minLength: 0)

      Button(action: presentNewGoal) {
        Image(systemName: "plus")
          .font(.body.weight(.bold))
          .foregroundStyle(AlmanacPalette.paper)
          .frame(
            width: AlmanacMetrics.spacingExtraLarge,
            height: AlmanacMetrics.spacingExtraLarge
          )
          .background(AlmanacPalette.moss, in: Circle())
          .accessibilityHidden(true)
      }
      .buttonStyle(.plain)
      .frame(
        minWidth: AlmanacMetrics.minimumTarget,
        minHeight: AlmanacMetrics.minimumTarget
      )
      .contentShape(Rectangle())
      .accessibilityLabel("New goal")
      .accessibilityHint("Opens a form to create a goal")
      .accessibilityIdentifier("goals.add")
    }
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
        Text("No goals yet")
          .font(.headline)
          .fixedSize(horizontal: false, vertical: true)

        Text("Create a goal to track progress toward something that matters.")
          .almanacTextStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button(action: presentNewGoal) {
        Text("New goal")
          .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
          .contentShape(Capsule())
      }
      .buttonStyle(AlmanacPrimaryButtonStyle())
      .accessibilityHint("Opens a form to create a goal")
      .accessibilityIdentifier("goals.empty.add")
    }
    .padding(AlmanacMetrics.spacingLarge)
    .frame(maxWidth: .infinity, alignment: .leading)
    .almanacSunkenSurface()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("goals.empty")
  }

  @ViewBuilder
  private func rosterRows(_ rows: [GoalRosterRow]) -> some View {
    ForEach(rows) { row in
      GoalRosterRowButton(
        row: row,
        isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
        select: {
          selectedGoal = GoalRosterSelection(goal: row.goal)
        }
      )
      .modifier(
        GoalRosterListRowModifier(
          verticalInset: AlmanacMetrics.spacingSmall / 2
        )
      )
    }
  }

  private var closedDisclosure: some View {
    Button(action: model.toggleClosedDisclosure) {
      HStack(spacing: AlmanacMetrics.spacingMedium) {
        Text("CLOSED · \(model.closedRows.count)")
          .almanacTextStyle(.emphasizedLabel)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 0)

        Image(systemName: model.isClosedExpanded ? "chevron.up" : "chevron.down")
          .font(.caption.weight(.semibold))
          .foregroundStyle(AlmanacPalette.ink)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, AlmanacMetrics.spacingMedium)
      .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
      .contentShape(
        RoundedRectangle(
          cornerRadius: AlmanacMetrics.cardRadius,
          style: .continuous
        )
      )
    }
    .buttonStyle(.plain)
    .almanacSunkenSurface(radius: AlmanacMetrics.cardRadius)
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel("Closed goals")
    .accessibilityValue(
      "\(model.closedRows.count), \(model.isClosedExpanded ? "expanded" : "collapsed")"
    )
    .accessibilityHint(
      model.isClosedExpanded
        ? "Collapses closed goals"
        : "Expands closed goals"
    )
    .accessibilityIdentifier("goals.closed.disclosure")
    .id("goals.closed.disclosure")
  }

  private var hasSavedRows: Bool {
    !model.openRows.isEmpty
      || !model.pastDueRows.isEmpty
      || !model.closedRows.isEmpty
  }

  private var localDayCalendar: Calendar {
    var localDayCalendar = calendar
    localDayCalendar.timeZone = timeZone
    return localDayCalendar
  }

  private func startOnce(at instant: Date) {
    guard !hasStarted else { return }
    hasStarted = true
    hasLeftActiveScene = scenePhase != .active
    refresh(at: instant)
  }

  private func refresh(at instant: Date) {
    model.refresh(
      at: resolvedInstant(instant),
      calendar: localDayCalendar,
      timeZone: timeZone,
      locale: locale
    )
  }

  private func resolvedInstant(_ instant: Date) -> Date {
    #if DEBUG
      fixedInstant ?? instant
    #else
      instant
    #endif
  }

  private func refreshCurrentContext() {
    refresh(at: .now)
  }

  private func presentNewGoal() {
    presentedForm = .new
  }

  private func closeDetail() {
    selectedGoal = nil
    refreshCurrentContext()
  }
}

private enum GoalRosterForm: Identifiable {
  case new

  var id: String { "new" }
}

private struct GoalRosterSelection: Identifiable {
  let goal: Goal

  var id: PersistentIdentifier { goal.persistentModelID }
}

private struct GoalRosterListRowModifier: ViewModifier {
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

private struct GoalRosterSectionHeaderModifier: ViewModifier {
  let hasPrecedingSection: Bool

  func body(content: Content) -> some View {
    content
      .modifier(GoalRosterListRowModifier())
      .padding(
        .top,
        hasPrecedingSection
          ? AlmanacMetrics.spacingLarge
          : AlmanacMetrics.spacingSmall
      )
      .padding(.bottom, AlmanacMetrics.spacingSmall / 2)
  }
}

private struct GoalRosterRowButton: View {
  let row: GoalRosterRow
  let isAccessibilitySize: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
        summary

        GoalProgressView(
          progress: row.progress,
          progressText: row.progressText,
          standing: row.standing,
          expectedNormalizedProgress: row.expectedNormalizedProgress,
          standingText: row.standing == nil ? nil : row.stateText,
          closure: row.closure,
          closureText: row.closure == nil ? nil : row.stateText,
          style: .roster
        )

        metadata
      }
      .padding(AlmanacMetrics.spacingMedium)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(
        RoundedRectangle(
          cornerRadius: AlmanacMetrics.cardRadius,
          style: .continuous
        )
      )
    }
    .buttonStyle(.plain)
    .almanacRaisedSurface()
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(row.accessibilityLabel)
    .accessibilityValue(row.accessibilityValue)
    .accessibilityHint("Opens goal details")
    .accessibilityIdentifier("goals.row.\(row.goal.id.uuidString)")
  }

  @ViewBuilder
  private var summary: some View {
    if isAccessibilitySize {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall / 2) {
        name
        progressText
      }
    } else {
      HStack(alignment: .firstTextBaseline, spacing: AlmanacMetrics.spacingMedium) {
        name
          .frame(maxWidth: .infinity, alignment: .leading)
        progressText
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }

  private var name: some View {
    Text(row.name)
      .font(.body.weight(.semibold))
      .foregroundStyle(row.closure == nil ? AlmanacPalette.ink : AlmanacPalette.inkMuted)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var progressText: some View {
    Text(row.progressText)
      .almanacTextStyle(.meaningfulNumeral(.subheadline))
      .foregroundStyle(accent)
      .multilineTextAlignment(isAccessibilitySize ? .leading : .trailing)
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private var metadata: some View {
    if isAccessibilitySize {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall / 2) {
        deadline
        state
      }
    } else {
      HStack(alignment: .firstTextBaseline, spacing: AlmanacMetrics.spacingMedium) {
        deadline
          .frame(maxWidth: .infinity, alignment: .leading)
        state
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

  private var state: some View {
    Text(row.stateText)
      .font(.caption.weight(.semibold))
      .foregroundStyle(accent)
      .multilineTextAlignment(isAccessibilitySize ? .leading : .trailing)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var accent: Color {
    if row.closure != nil {
      return AlmanacPalette.inkMuted
    }

    switch row.standing {
    case .behind:
      return AlmanacPalette.goalOchreDeep
    case .pastDue:
      return AlmanacPalette.withered
    case .onPace, nil:
      return AlmanacPalette.moss
    }
  }
}

private struct GoalRosterLoadFailureCard: View {
  let failure: GoalRosterLoadFailure
  let retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(failure.message)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AlmanacPalette.goalOchreDeep)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Goals refresh failed. \(failure.message)")

      Button(failure.retryTitle, action: retry)
        .buttonStyle(.plain)
        .font(.body.weight(.semibold))
        .foregroundStyle(AlmanacPalette.moss)
        .frame(minWidth: AlmanacMetrics.minimumTarget, minHeight: AlmanacMetrics.minimumTarget)
        .contentShape(Rectangle())
        .accessibilityHint("Retries loading saved goals")
        .accessibilityIdentifier("goals.loadFailure.retry")
    }
    .padding(AlmanacMetrics.spacingMedium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .almanacSunkenSurface()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("goals.loadFailure")
  }
}

private nonisolated struct GoalRosterTimelineSchedule: TimelineSchedule {
  let calendar: Calendar
  let domainTransition: Date?

  func entries(from startDate: Date, mode: Mode) -> Entries {
    Entries(
      nextDate: startDate,
      calendar: calendar,
      domainTransition: domainTransition
    )
  }

  nonisolated struct Entries: Sequence, IteratorProtocol {
    private var nextDate: Date?
    private let calendar: Calendar
    private var domainTransition: Date?

    fileprivate init(
      nextDate: Date,
      calendar: Calendar,
      domainTransition: Date?
    ) {
      self.nextDate = nextDate
      self.calendar = calendar
      self.domainTransition = domainTransition
    }

    mutating func next() -> Date? {
      guard let date = nextDate else { return nil }
      advance(after: date)
      return date
    }

    private mutating func advance(after date: Date) {
      if let domainTransition, domainTransition <= date {
        self.domainTransition = nil
      }

      let nextMidnight = calendar.date(
        byAdding: .day,
        value: 1,
        to: calendar.startOfDay(for: date)
      )

      guard let domainTransition else {
        nextDate = nextMidnight
        return
      }

      guard let nextMidnight else {
        nextDate = domainTransition
        self.domainTransition = nil
        return
      }

      if domainTransition < nextMidnight {
        nextDate = domainTransition
        self.domainTransition = nil
      } else {
        nextDate = nextMidnight
        if domainTransition == nextMidnight {
          self.domainTransition = nil
        }
      }
    }
  }
}
