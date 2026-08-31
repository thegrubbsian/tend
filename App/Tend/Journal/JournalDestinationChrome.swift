import Foundation
import Observation
import SwiftData
import SwiftUI
import TendCore

struct JournalDestinationChrome: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.locale) private var locale
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.timeZone) private var timeZone

  @Query private var entries: [JournalEntry]
  @Query private var habits: [Habit]

  @State private var overviewModel: JournalOverviewModel?
  @State private var editorModel: JournalEditorModel?
  @State private var editorRoute: JournalRoute?
  @State private var routeFailureMessage: String?
  @State private var editorNavigationGuardToken: ShellNavigationGuardToken?
  @State private var timelineDate: Date?
  @State private var editorEnvironment = JournalEditorEnvironment()
  #if DEBUG
    @State private var routeFixtureDuplicateID: UUID?
  #endif

  let routing: ShellRoutingModel
  private let fixedInstant: Date?

  init(
    routing: ShellRoutingModel,
    instant: Date? = nil
  ) {
    self.routing = routing
    #if DEBUG
      fixedInstant =
        instant
        ?? TendUITestStore.fixedInstant(arguments: ProcessInfo.processInfo.arguments)
    #else
      fixedInstant = instant
    #endif
  }

  @ViewBuilder
  var body: some View {
    if let fixedInstant {
      routedContent(at: fixedInstant)
    } else {
      ZStack {
        if let timelineDate {
          routedContent(at: timelineDate)
        } else {
          Color.clear
            .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
            .accessibilityHidden(true)
        }

        TimelineView(LocalDayTimelineSchedule(calendar: localCalendar)) { timeline in
          Color.clear
            .task(id: timeline.date) {
              guard timelineDate != timeline.date else { return }
              timelineDate = timeline.date
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
    }
  }

  private var localCalendar: Calendar {
    var localCalendar = calendar
    localCalendar.locale = locale
    localCalendar.timeZone = timeZone
    return localCalendar
  }

  private func routedContent(at instant: Date) -> some View {
    ZStack(alignment: .topLeading) {
      Group {
        switch routing.journalRoute {
        case .overview:
          if let overviewModel {
            JournalOverviewView(
              model: overviewModel,
              onCompose: showComposer,
              onOpenEntry: showEntry
            )
          } else {
            Color.clear
              .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
              .accessibilityHidden(true)
          }
        case .compose, .entry:
          if let routeFailureMessage {
            routeFailure(message: routeFailureMessage)
          } else if let editorModel {
            JournalEditorView(
              model: editorModel,
              habits: habits,
              routing: routing,
              gardenNow: editorEnvironment.now,
              gardenRefreshSignal: instant,
              managesLifecycle: false,
              onClose: showOverview,
              onSelectDate: showComposer
            )
          } else {
            Color.clear
              .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
              .accessibilityHidden(true)
          }
        }
      }
      Color.clear
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Journal")
        .accessibilityIdentifier("shell.destination.journal")
      #if DEBUG
        routeFailureFixtureControl
        repeatedDateRouteFixtureControl
      #endif
    }
    .task(id: refreshStamp(at: instant)) {
      synchronize(at: instant)
    }
    .onAppear {
      if let editorModel {
        installEditorNavigationGuard(for: editorModel)
      }
    }
    .onDisappear {
      releaseEditorNavigationGuard()
      editorModel?.stop()
    }
    .onChange(of: scenePhase) { previousPhase, phase in
      if phase == .active {
        synchronize(at: operationInstant(), force: true)
      } else if previousPhase == .active {
        editorModel?.flushForLifecycle()
      }
    }
  }

  private func synchronize(at instant: Date, force: Bool = false) {
    editorEnvironment.update(
      fixedInstant: fixedInstant,
      timeZone: timeZone,
      locale: locale
    )
    switch routing.journalRoute {
    case .overview:
      discardEditor()
      routeFailureMessage = nil
      let overviewModel = resolvedOverviewModel()
      if force {
        overviewModel.refresh(
          at: instant,
          calendar: localCalendar,
          timeZone: timeZone,
          locale: locale
        )
      } else {
        overviewModel.refreshIfEntryGraphChanged(
          entries,
          at: instant,
          calendar: localCalendar,
          timeZone: timeZone,
          locale: locale
        )
      }
    case .entry, .compose:
      if editorRoute == routing.journalRoute, editorModel != nil {
        validateCurrentEditorRoute(at: instant)
      } else {
        resolveEditor(at: instant)
      }
    }
  }

  private func resolvedOverviewModel() -> JournalOverviewModel {
    if let overviewModel { return overviewModel }
    let model = JournalOverviewModel(context: modelContext)
    overviewModel = model
    return model
  }

  private func resolveEditor(at instant: Date) {
    do {
      let query = JournalEntryQuery(context: modelContext)
      let entry: JournalEntry?
      let day: LocalDate
      switch routing.journalRoute {
      case .overview:
        return
      case .entry:
        guard let resolved = try routing.resolveJournalEntry(using: query) else {
          discardEditor()
          routeFailureMessage = nil
          synchronize(at: instant)
          return
        }
        entry = resolved
        guard let resolvedDay = LocalDate(rawValue: resolved.dayKey) else {
          throw JournalEntryQueryError.malformedDay(entryID: resolved.id, key: resolved.dayKey)
        }
        day = resolvedDay
      case .compose(let requestedDay):
        entry = try query.entry(on: requestedDay)
        day = requestedDay
        if let entry {
          routing.prepareJournalRoute(.entry(entry.id))
        }
      }

      let resolvedRoute = entry.map { JournalRoute.entry($0.id) } ?? .compose(day)
      let model = JournalEditorModel(
        day: day,
        entry: entry,
        operations: editorOperations(),
        now: editorEnvironment.now,
        timeZone: editorEnvironment.currentTimeZone,
        locale: editorEnvironment.currentLocale,
        onSaved: { savedEntry in
          routing.prepareJournalRoute(.entry(savedEntry.id))
          editorRoute = .entry(savedEntry.id)
        },
        onDeleted: showOverview
      )
      let previousModel = editorModel
      editorModel = model
      installEditorNavigationGuard(for: model)
      editorRoute = resolvedRoute
      routeFailureMessage = nil
      previousModel?.stop()
    } catch {
      routeFailureMessage = "This Journal page could not be loaded."
    }
  }

  private func validateCurrentEditorRoute(at instant: Date) {
    guard editorModel != nil else {
      resolveEditor(at: instant)
      return
    }
    do {
      let query = JournalEntryQuery(context: modelContext)
      switch routing.journalRoute {
      case .overview:
        synchronize(at: instant, force: true)
      case .entry:
        if try routing.resolveJournalEntry(using: query) == nil {
          discardEditor()
          routeFailureMessage = nil
          synchronize(at: instant, force: true)
        } else {
          routeFailureMessage = nil
        }
      case .compose(let day):
        if let entry = try query.entry(on: day) {
          routing.prepareJournalRoute(.entry(entry.id))
          discardEditor()
          resolveEditor(at: instant)
        } else {
          routeFailureMessage = nil
        }
      }
    } catch {
      routeFailureMessage = "This Journal page could not be loaded."
    }
  }

  private func showComposer(_ day: LocalDate) {
    guard editorModel?.day != day else { return }
    routing.prepareJournalRoute(.compose(day))
    resolveEditor(at: operationInstant())
  }

  private func showEntry(_ id: UUID) {
    routing.prepareJournalRoute(.entry(id))
    discardEditor()
    routeFailureMessage = nil
  }

  private func showOverview() {
    routing.prepareJournalRoute(.overview)
    discardEditor()
    routeFailureMessage = nil
    synchronize(at: operationInstant(), force: true)
  }

  private func installEditorNavigationGuard(for model: JournalEditorModel) {
    releaseEditorNavigationGuard()
    editorNavigationGuardToken = routing.installNavigationGuard { [model] in
      await model.flush()
    }
  }

  private func releaseEditorNavigationGuard() {
    guard let editorNavigationGuardToken else { return }
    routing.removeNavigationGuard(editorNavigationGuardToken)
    self.editorNavigationGuardToken = nil
  }

  private func discardEditor() {
    releaseEditorNavigationGuard()
    editorModel?.stop()
    editorModel = nil
    editorRoute = nil
  }

  private func routeFailure(message: String) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
      HStack(spacing: AlmanacMetrics.spacingSmall) {
        Image(systemName: "book.closed.fill")
          .foregroundStyle(AlmanacPalette.mossDeep)
          .accessibilityHidden(true)
        Text("Journal")
          .almanacTextStyle(.screenTitle)
          .accessibilityAddTraits(.isHeader)
      }

      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
        Text(message)
          .font(.body.weight(.semibold))
          .foregroundStyle(AlmanacPalette.ink)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("journal.route.failure")

        Button("Try again") {
          #if DEBUG
            repairRouteFailureFixtureIfNeeded()
          #endif
          synchronize(at: operationInstant(), force: true)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(AlmanacPalette.ink)
        .frame(minHeight: AlmanacMetrics.minimumTarget)
        .accessibilityIdentifier("journal.route.failure.retry")
      }
      .padding(AlmanacMetrics.spacingLarge)
      .frame(maxWidth: .infinity, alignment: .leading)
      .almanacSunkenSurface(radius: AlmanacMetrics.cardRadius)
    }
    .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
  }

  #if DEBUG
    @ViewBuilder
    private var routeFailureFixtureControl: some View {
      if ProcessInfo.processInfo.arguments.contains("-tend-journal-route-failure-control"),
        editorModel != nil, routeFixtureDuplicateID == nil
      {
        Button {
          corruptCurrentEditorRouteForTesting()
        } label: {
          Color.clear
            .frame(width: AlmanacMetrics.minimumTarget, height: AlmanacMetrics.minimumTarget)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Corrupt Journal route")
        .accessibilityIdentifier("journal.fixture.corrupt-route")
      }
    }

    @ViewBuilder
    private var repeatedDateRouteFixtureControl: some View {
      if ProcessInfo.processInfo.arguments.contains("-tend-journal-repeat-date-control"),
        let editorModel
      {
        Button {
          showComposer(editorModel.day)
        } label: {
          Color.clear
            .frame(width: AlmanacMetrics.minimumTarget, height: AlmanacMetrics.minimumTarget)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Repeat current Journal date route")
        .accessibilityIdentifier("journal.fixture.repeat-date")
      }
    }

    private func corruptCurrentEditorRouteForTesting() {
      guard let editorModel else { return }
      editorModel.updateBody("Pending route failure draft", isComposing: false)
      let instant = operationInstant()
      let duplicate = JournalEntry(
        day: editorModel.day,
        body: "Duplicate Journal route fixture",
        createdAt: instant,
        editedAt: instant
      )
      modelContext.insert(duplicate)
      do {
        try modelContext.save()
        routeFixtureDuplicateID = duplicate.id
      } catch {
        routeFailureMessage = "This Journal page could not be loaded."
      }
    }

    private func repairRouteFailureFixtureIfNeeded() {
      guard let duplicateID = routeFixtureDuplicateID,
        let duplicate = entries.first(where: { $0.id == duplicateID })
      else {
        return
      }
      modelContext.delete(duplicate)
      do {
        try modelContext.save()
        routeFixtureDuplicateID = nil
      } catch {
        routeFailureMessage = "This Journal page could not be loaded."
      }
    }
  #endif

  private func refreshStamp(at instant: Date) -> JournalDestinationRefreshStamp {
    JournalDestinationRefreshStamp(
      route: routing.journalRoute,
      instant: instant,
      calendarIdentifier: String(describing: calendar.identifier),
      timeZoneIdentifier: timeZone.identifier,
      localeIdentifier: locale.identifier,
      entries: entries.map(JournalDestinationEntryStamp.init).sorted {
        $0.id.uuidString < $1.id.uuidString
      }
    )
  }

  private func operationInstant() -> Date {
    fixedInstant ?? Date()
  }

  private func editorOperations() -> JournalEditorOperations {
    let live = JournalEditorOperations.live(context: modelContext)
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      if arguments.contains(JournalEditorUITestHarnessArguments.failFirstSave) {
        let failure = JournalDestinationSaveFailure(remaining: 1)
        return JournalEditorOperations(
          findEntry: live.findEntry,
          create: { day, body, instant, timeZone in
            if failure.consume() { throw JournalDestinationFixtureError.expectedFailure }
            return try live.create(day, body, instant, timeZone)
          },
          edit: { entry, body, instant in
            if failure.consume() { throw JournalDestinationFixtureError.expectedFailure }
            try live.edit(entry, body, instant)
          },
          delete: live.delete
        )
      }
    #endif
    return live
  }
}

private struct JournalDestinationRefreshStamp: Equatable {
  let route: JournalRoute
  let instant: Date
  let calendarIdentifier: String
  let timeZoneIdentifier: String
  let localeIdentifier: String
  let entries: [JournalDestinationEntryStamp]
}

private struct JournalDestinationEntryStamp: Equatable {
  let id: UUID
  let dayKey: String
  let body: String
  let createdAt: Date
  let editedAt: Date

  init(_ entry: JournalEntry) {
    id = entry.id
    dayKey = entry.dayKey
    body = entry.body
    createdAt = entry.createdAt
    editedAt = entry.editedAt
  }
}

@MainActor
@Observable
private final class JournalEditorEnvironment {
  private var fixedInstant: Date?
  private var timeZone = TimeZone.current
  private var locale = Locale.current

  func update(
    fixedInstant: Date?,
    timeZone: TimeZone,
    locale: Locale
  ) {
    self.fixedInstant = fixedInstant
    self.timeZone = timeZone
    self.locale = locale
  }

  func now() -> Date {
    fixedInstant ?? Date()
  }

  func currentTimeZone() -> TimeZone {
    timeZone
  }

  func currentLocale() -> Locale {
    locale
  }
}

#if DEBUG
  @MainActor
  private final class JournalDestinationSaveFailure {
    private var remaining: Int

    init(remaining: Int) {
      self.remaining = remaining
    }

    func consume() -> Bool {
      guard remaining > 0 else { return false }
      remaining -= 1
      return true
    }
  }

  private enum JournalDestinationFixtureError: Error {
    case expectedFailure
  }
#endif
