#if DEBUG
  import SwiftData
  import SwiftUI
  import TendCore

  enum JournalEditorUITestHarnessArguments {
    static let enabled = "-tend-journal-editor"
    static let failSave = "-tend-journal-editor-fail-save"

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
      let operations =
        failsSaves
        ? JournalEditorOperations(
          findEntry: liveOperations.findEntry,
          create: { _, _, _, _ in throw HarnessFailure.expected },
          edit: { _, _, _ in throw HarnessFailure.expected },
          delete: liveOperations.delete
        )
        : liveOperations
      let entry = entries.first { $0.dayKey == day.rawValue }
      model = JournalEditorModel(
        day: day,
        entry: entry,
        operations: operations,
        now: { instant },
        timeZone: { timeZone },
        locale: { locale },
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
#endif
