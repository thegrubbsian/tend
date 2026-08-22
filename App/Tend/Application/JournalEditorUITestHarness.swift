#if DEBUG
  import SwiftData
  import SwiftUI
  import TendCore

  enum JournalEditorUITestHarnessArguments {
    static let enabled = "-tend-journal-editor"
    static let failSave = "-tend-journal-editor-fail-save"
    static let failFirstSave = "-tend-journal-editor-fail-first-save"
    static let garden = "-tend-journal-garden"

    static func isEnabled(_ arguments: [String]) -> Bool {
      arguments.contains(enabled)
    }
  }

  struct JournalEditorUITestHarness: View {
    @State private var isClosed = false
    @State private var isDeleted = false

    let routing: ShellRoutingModel
    let instant: Date
    let failsSaves: Bool
    let failsFirstSave: Bool

    var body: some View {
      Group {
        if isDeleted {
          result("Entry deleted", identifier: "journalEditor.deleted")
        } else if isClosed {
          result("Editor closed", identifier: "journalEditor.closed")
        } else {
          JournalEditorUITestHarnessContent(
            routing: routing,
            instant: instant,
            failsSaves: failsSaves,
            failsFirstSave: failsFirstSave,
            onClose: { isClosed = true },
            onDeleted: { isDeleted = true }
          )
        }
      }
    }

    private func result(_ text: String, identifier: String) -> some View {
      Text(text)
        .almanacTextStyle(.screenTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
        .accessibilityIdentifier(identifier)
    }
  }

  private struct JournalEditorUITestHarnessContent: View {
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var context
    @Environment(\.timeZone) private var timeZone
    @Query private var entries: [JournalEntry]
    @State private var model: JournalEditorModel?

    let routing: ShellRoutingModel
    let instant: Date
    let failsSaves: Bool
    let failsFirstSave: Bool
    let onClose: @MainActor () -> Void
    let onDeleted: @MainActor () -> Void

    @ViewBuilder
    var body: some View {
      if let model {
        JournalEditorView(
          model: model,
          routing: routing,
          gardenNow: { instant },
          onClose: onClose
        )
      } else {
        Color.clear
          .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
          .task { buildModel() }
          .accessibilityHidden(true)
      }
    }

    private func buildModel() {
      guard model == nil, let day = localDay else { return }
      let liveOperations = JournalEditorOperations.live(context: context)
      let operations: JournalEditorOperations
      if failsSaves || failsFirstSave {
        let failure = HarnessSaveFailure(
          remaining: failsSaves ? .max : 1
        )
        operations = JournalEditorOperations(
          findEntry: liveOperations.findEntry,
          create: { day, body, instant, timeZone in
            if failure.consume() { throw HarnessFailure.expected }
            return try liveOperations.create(day, body, instant, timeZone)
          },
          edit: { entry, body, instant in
            if failure.consume() { throw HarnessFailure.expected }
            try liveOperations.edit(entry, body, instant)
          },
          delete: liveOperations.delete
        )
      } else {
        operations = liveOperations
      }
      let entry =
        if ProcessInfo.processInfo.arguments.contains(JournalEditorUITestHarnessArguments.garden) {
          try? seedGarden(on: day)
        } else {
          entries.first { $0.dayKey == day.rawValue }
        }
      let sleep: JournalEditorModel.Sleep
      if failsFirstSave {
        sleep = { _ in try await Task.sleep(for: .seconds(60)) }
      } else {
        sleep = { duration in try await Task.sleep(for: duration) }
      }
      model = JournalEditorModel(
        day: day,
        entry: entry,
        operations: operations,
        now: { instant },
        timeZone: { timeZone },
        locale: { locale },
        sleep: sleep,
        onDeleted: onDeleted
      )
    }

    private func seedGarden(on day: LocalDate) throws -> JournalEntry {
      if let entry = entries.first(where: { $0.dayKey == day.rawValue }) {
        return entry
      }
      let management = HabitManagementOperations(context: context)
      let logging = LogEntryOperations(context: context)

      let read = try management.create(
        fields: HabitEditableFields(name: "Read", target: 2, unit: "pages"),
        cadence: .daily,
        at: instant,
        timeZone: timeZone
      )
      read.id = fixtureID(1)
      _ = try logging.append(
        amount: 2,
        to: read,
        at: instant,
        timeZone: timeZone
      )

      let walk = try management.create(
        fields: HabitEditableFields(name: "Walk", target: 2, unit: "miles"),
        cadence: .daily,
        at: instant,
        timeZone: timeZone
      )
      walk.id = fixtureID(2)
      _ = try logging.append(
        amount: 1,
        to: walk,
        at: instant,
        timeZone: timeZone
      )

      let broken = Habit(
        id: fixtureID(3),
        name: "Broken",
        cadence: .daily,
        target: 1,
        isActive: true,
        createdAt: instant
      )
      let brokenActivity = HabitActivityPeriod(startedAt: instant, habit: broken)
      context.insert(broken)
      context.insert(brokenActivity)
      broken.activityPeriods = [brokenActivity]
      try context.save()

      return try JournalEntryOperations(context: context).create(
        day: day,
        body: "Field notes from the garden.",
        at: instant,
        timeZone: timeZone
      )
    }

    private func fixtureID(_ value: Int) -> UUID {
      UUID(
        uuidString: String(
          format: "00000000-0000-0000-0000-%012d",
          locale: Locale(identifier: "en_US_POSIX"),
          value
        )
      )!
    }

    private var localDay: LocalDate? {
      var calendar = Calendar(identifier: .gregorian)
      calendar.locale = Locale(identifier: "en_US_POSIX")
      calendar.timeZone = timeZone
      let components = calendar.dateComponents([.era, .year, .month, .day], from: instant)
      guard
        components.era == 1,
        let year = components.year,
        let month = components.month,
        let day = components.day
      else { return nil }
      return LocalDate(year: year, month: month, day: day)
    }

    private enum HarnessFailure: Error {
      case expected
    }
  }

  @MainActor
  private final class HarnessSaveFailure {
    private var remaining: Int

    init(remaining: Int) {
      self.remaining = remaining
    }

    func consume() -> Bool {
      if remaining == .max { return true }
      guard remaining > 0 else { return false }
      remaining -= 1
      return true
    }
  }
#endif
