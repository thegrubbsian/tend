#if DEBUG
  import SwiftData
  import SwiftUI
  import TendCore

  enum JournalEditorUITestHarnessArguments {
    static let enabled = "-tend-journal-editor"
    static let failSave = "-tend-journal-editor-fail-save"
    static let failFirstSave = "-tend-journal-editor-fail-first-save"

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
      let entry = entries.first { $0.dayKey == day.rawValue }
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
