import SwiftData
import SwiftUI
import TendCore
import UIKit

struct JournalEditorView: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.locale) private var locale
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.timeZone) private var timeZone
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Query private var habits: [Habit]

  @State private var model: JournalEditorModel
  @State private var gardenModel: JournalDayGardenModel?
  @State private var editorIsFocused = false
  @State private var navigationGuardToken: ShellNavigationGuardToken?

  private let routing: ShellRoutingModel?
  private let onClose: @MainActor () -> Void
  private let onSelectDate: @MainActor (LocalDate) -> Void
  private let gardenNow: @MainActor () -> Date

  init(
    model: JournalEditorModel,
    routing: ShellRoutingModel? = nil,
    gardenNow: @escaping @MainActor () -> Date = Date.init,
    onClose: @escaping @MainActor () -> Void = {},
    onSelectDate: @escaping @MainActor (LocalDate) -> Void = { _ in }
  ) {
    _model = State(initialValue: model)
    self.routing = routing
    self.gardenNow = gardenNow
    self.onClose = onClose
    self.onSelectDate = onSelectDate
  }

  var body: some View {
    VStack(spacing: 0) {
      navigationHeader

      Rectangle()
        .fill(AlmanacPalette.hairline)
        .frame(height: 1)
        .padding(.top, AlmanacMetrics.spacingSmall)

      if !model.scopeOptions.isEmpty {
        scopePicker
          .padding(
            .top, isCompactHeight ? AlmanacMetrics.spacingSmall : AlmanacMetrics.spacingMedium)
      }

      persistenceStatus
        .padding(.top, isCompactHeight ? AlmanacMetrics.spacingSmall : AlmanacMetrics.spacingMedium)

      editorPage
    }
    .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("journalEditor.screen")
    .alert(
      "Delete this entry?",
      isPresented: deletionConfirmation,
      actions: {
        Button("Cancel", role: .cancel, action: model.cancelDeletion)
        Button("Delete entry", role: .destructive, action: model.confirmDeletion)
      },
      message: {
        Text("This removes the prose for this day.")
      }
    )
    .task(id: gardenRefreshStamp) {
      refreshGarden()
    }
    .onAppear {
      editorIsFocused = true
      installNavigationGuard()
    }
    .onDisappear {
      removeNavigationGuard()
      model.stop()
    }
    .onChange(of: model.status) { _, status in
      guard status.failure != nil, scenePhase == .active else { return }
      editorIsFocused = true
    }
    .onChange(of: scenePhase) { previousPhase, phase in
      if phase == .active {
        refreshGarden(force: true)
        if model.status.failure != nil {
          editorIsFocused = true
        }
      } else if previousPhase == .active {
        model.flushForLifecycle()
      }
    }
  }

  @ViewBuilder
  private var navigationHeader: some View {
    if isCompactHeight {
      inlineNavigationHeader {
        compactDateTitle
      }
    } else if dynamicTypeSize.isAccessibilitySize {
      VStack(spacing: AlmanacMetrics.spacingSmall) {
        dateTitle
        navigationActions
      }
    } else {
      inlineNavigationHeader {
        dateTitle
      }
    }
  }

  private var dateTitle: some View {
    Text(formattedDay)
      .almanacTextStyle(.screenTitle)
      .lineLimit(2)
      .minimumScaleFactor(0.75)
      .multilineTextAlignment(.center)
      .accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("journalEditor.date")
  }

  private var compactDateTitle: some View {
    Text(formattedCompactDay)
      .font(.headline)
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .multilineTextAlignment(.center)
      .accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("journalEditor.date")
  }

  private func inlineNavigationHeader<Title: View>(
    @ViewBuilder title: () -> Title
  ) -> some View {
    HStack(spacing: AlmanacMetrics.spacingSmall) {
      Group {
        if isCompactHeight {
          compactBackButton
        } else {
          backButton
        }
      }
      .frame(
        width: isCompactHeight ? AlmanacMetrics.minimumTarget : 80,
        alignment: .leading
      )

      title()
        .frame(maxWidth: .infinity)

      deletionSlot
        .frame(
          width: isCompactHeight ? AlmanacMetrics.minimumTarget : 80,
          alignment: .trailing
        )
    }
    .frame(maxWidth: .infinity)
  }

  private var navigationActions: some View {
    HStack(spacing: AlmanacMetrics.spacingMedium) {
      backButton
      Spacer(minLength: AlmanacMetrics.spacingMedium)
      if model.canDelete {
        deleteButton
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var backButton: some View {
    Button(action: requestClose) {
      Label("Back", systemImage: "chevron.left")
        .frame(
          minWidth: AlmanacMetrics.minimumTarget,
          minHeight: AlmanacMetrics.minimumTarget
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(AlmanacPalette.mossDeep)
    .accessibilityHint("Saves pending prose before returning")
    .accessibilityIdentifier("journalEditor.back")
  }

  private var compactBackButton: some View {
    Button(action: requestClose) {
      Image(systemName: "chevron.left")
        .frame(
          minWidth: AlmanacMetrics.minimumTarget,
          minHeight: AlmanacMetrics.minimumTarget
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(AlmanacPalette.mossDeep)
    .accessibilityLabel("Back")
    .accessibilityHint("Saves pending prose before returning")
    .accessibilityIdentifier("journalEditor.back")
  }

  @ViewBuilder
  private var deletionSlot: some View {
    if model.canDelete {
      deleteButton
    } else {
      Color.clear
        .frame(
          width: AlmanacMetrics.minimumTarget,
          height: AlmanacMetrics.minimumTarget
        )
        .accessibilityHidden(true)
    }
  }

  private var deleteButton: some View {
    Button(action: model.requestDeletion) {
      Image(systemName: "trash")
    }
    .buttonStyle(.plain)
    .foregroundStyle(AlmanacPalette.clayDeep)
    .frame(
      minWidth: AlmanacMetrics.minimumTarget,
      minHeight: AlmanacMetrics.minimumTarget
    )
    .contentShape(Rectangle())
    .accessibilityLabel("Delete entry")
    .accessibilityHint("Requires confirmation")
    .accessibilityIdentifier("journalEditor.delete")
  }

  private var scopePicker: some View {
    HStack(spacing: AlmanacMetrics.spacingSmall / 2) {
      ForEach(model.scopeOptions) { option in
        Button {
          requestDate(option.day)
        } label: {
          Text(option.label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(
              option.isSelected ? AlmanacPalette.paperRaised : AlmanacPalette.ink
            )
            .frame(
              maxWidth: .infinity,
              minHeight: AlmanacMetrics.minimumTarget
            )
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, isCompactHeight ? 0 : AlmanacMetrics.spacingSmall)
            .background(
              option.isSelected ? AlmanacPalette.moss : .clear,
              in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(option.isSelected ? .isSelected : [])
        .accessibilityIdentifier("journalEditor.scope.\(option.label)")
      }
    }
    .padding(AlmanacMetrics.spacingSmall / 2)
    .almanacSunkenSurface(radius: AlmanacMetrics.tabPillRadius)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Entry date")
    .accessibilityIdentifier("journalEditor.scope")
  }

  @ViewBuilder
  private var persistenceStatus: some View {
    switch model.status {
    case .idle:
      Color.clear
        .frame(height: AlmanacMetrics.spacingMedium)
        .accessibilityHidden(true)
    case .pending:
      HStack(spacing: AlmanacMetrics.spacingSmall) {
        ProgressView()
          .controlSize(.small)
        Text("Saving…")
          .almanacTextStyle(.caption)
      }
      .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.spacingMedium)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Saving")
      .accessibilityIdentifier("journalEditor.status")
    case .saved:
      HStack(spacing: AlmanacMetrics.spacingSmall) {
        Image(systemName: "checkmark")
        Text("Saved")
      }
      .almanacTextStyle(.caption)
      .foregroundStyle(AlmanacPalette.mossDeep)
      .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.spacingMedium)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Saved")
      .accessibilityIdentifier("journalEditor.status")
    case .failed(let failure):
      HStack(alignment: .firstTextBaseline, spacing: AlmanacMetrics.spacingMedium) {
        Text(failure.message)
          .almanacTextStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: AlmanacMetrics.spacingSmall)

        Button(failure.retryTitle) {
          model.retry()
          editorIsFocused = true
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(AlmanacPalette.clayDeep)
        .frame(minHeight: AlmanacMetrics.minimumTarget)
        .accessibilityIdentifier("journalEditor.failure.retry")
      }
      .padding(.horizontal, AlmanacMetrics.spacingMedium)
      .padding(.vertical, AlmanacMetrics.spacingSmall)
      .frame(maxWidth: .infinity, alignment: .leading)
      .almanacSunkenSurface()
      .accessibilityElement(children: .contain)
      .accessibilityLabel(failure.message)
      .accessibilityIdentifier("journalEditor.failure")
    }
  }

  private var editorPage: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: AlmanacMetrics.spacingLarge) {
          prosePage
            .frame(minHeight: proseMinimumHeight(in: geometry.size.height))

          if model.entryID != nil, let gardenModel, !gardenModel.rows.isEmpty {
            JournalDayGardenView(
              rows: gardenModel.rows,
              onRetry: { refreshGarden(force: true) }
            )
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AlmanacMetrics.spacingSmall)
        .padding(
          .bottom,
          isCompactHeight ? AlmanacMetrics.spacingSmall : AlmanacMetrics.spacingMedium
        )
      }
      .scrollDismissesKeyboard(.immediately)
      .accessibilityIdentifier("journalEditor.scroll")
    }
  }

  private var prosePage: some View {
    JournalProseTextView(
      text: model.body,
      isFocused: $editorIsFocused,
      onChange: model.updateBody
    )
    .frame(maxWidth: .infinity)
    .almanacRaisedSurface(radius: AlmanacMetrics.cardRadius)
    .accessibilityLabel("Journal entry for \(formattedDay)")
    .accessibilityIdentifier("journalEditor.prose")
  }
  private var gardenRefreshStamp: JournalDayGardenModel.InputFingerprint? {
    guard model.entryID != nil else { return nil }
    return JournalDayGardenModel.InputFingerprint(
      day: model.day,
      habits: habits,
      context: gardenRefreshContext
    )
  }

  private var gardenRefreshContext: JournalDayGardenRefreshContext {
    JournalDayGardenRefreshContext(
      instant: gardenNow(),
      timeZone: timeZone,
      locale: locale
    )
  }

  private func proseMinimumHeight(in availableHeight: CGFloat) -> CGFloat {
    if model.entryID != nil {
      return isCompactHeight ? 100 : 180
    }
    let minimum = isCompactHeight ? AlmanacMetrics.minimumTarget : 180
    return max(minimum, availableHeight - AlmanacMetrics.spacingMedium)
  }

  private func refreshGarden(force: Bool = false) {
    guard model.entryID != nil else {
      gardenModel?.clear()
      return
    }
    let gardenModel = resolvedGardenModel()
    _ = gardenModel.refresh(
      day: model.day,
      habits: habits,
      context: gardenRefreshContext,
      force: force
    )
  }

  private func resolvedGardenModel() -> JournalDayGardenModel {
    if let gardenModel { return gardenModel }
    let gardenModel = JournalDayGardenModel(context: modelContext)
    self.gardenModel = gardenModel
    return gardenModel
  }

  private var deletionConfirmation: Binding<Bool> {
    Binding(
      get: { model.isDeletionConfirmationPresented },
      set: { isPresented in
        if !isPresented { model.cancelDeletion() }
      }
    )
  }

  private var isCompactHeight: Bool {
    verticalSizeClass == .compact
  }

  private var formattedDay: String {
    formatDay(template: "EEEE MMMM d yyyy")
  }

  private var formattedCompactDay: String {
    formatDay(template: "MMM d yyyy")
  }

  private func formatDay(template: String) -> String {
    guard let date = try? model.day.start(in: timeZone) else {
      return model.day.rawValue
    }
    var calendar = calendar
    calendar.locale = locale
    calendar.timeZone = timeZone
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = calendar
    formatter.timeZone = timeZone
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
  }

  private func requestClose() {
    Task {
      if await model.flush() {
        editorIsFocused = false
        onClose()
      } else {
        editorIsFocused = true
      }
    }
  }

  private func requestDate(_ day: LocalDate) {
    guard day != model.day else { return }
    Task {
      if await model.flush() {
        editorIsFocused = false
        onSelectDate(day)
      } else {
        editorIsFocused = true
      }
    }
  }

  private func installNavigationGuard() {
    guard navigationGuardToken == nil, let routing else { return }
    navigationGuardToken = routing.installNavigationGuard { [model] in
      await model.flush()
    }
  }

  private func removeNavigationGuard() {
    guard let navigationGuardToken, let routing else { return }
    routing.removeNavigationGuard(navigationGuardToken)
    self.navigationGuardToken = nil
  }
}

private struct JournalProseTextView: UIViewRepresentable {
  let text: String
  @Binding var isFocused: Bool
  let onChange: @MainActor (_ text: String, _ isComposing: Bool) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.delegate = context.coordinator
    textView.backgroundColor = .clear
    textView.font = .preferredFont(forTextStyle: .body)
    textView.adjustsFontForContentSizeCategory = true
    textView.textColor = UIColor(AlmanacPalette.ink)
    textView.tintColor = UIColor(AlmanacPalette.moss)
    textView.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
    textView.textContainer.lineFragmentPadding = 0
    textView.keyboardDismissMode = .interactive
    textView.autocapitalizationType = .sentences
    textView.autocorrectionType = .default
    textView.smartDashesType = .default
    textView.smartQuotesType = .default
    textView.spellCheckingType = .default
    textView.accessibilityIdentifier = "journalEditor.prose"
    textView.accessibilityLabel = "Journal entry"
    textView.text = text
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.parent = self
    if textView.markedTextRange == nil, textView.text != text {
      textView.text = text
    }
    if isFocused, !textView.isFirstResponder {
      textView.becomeFirstResponder()
    } else if !isFocused, textView.isFirstResponder {
      textView.resignFirstResponder()
    }
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: JournalProseTextView
    private var lastCompositionState = false

    init(parent: JournalProseTextView) {
      self.parent = parent
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
      parent.isFocused = true
    }

    func textViewDidEndEditing(_ textView: UITextView) {
      parent.isFocused = false
    }

    func textViewDidChange(_ textView: UITextView) {
      publish(textView)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      let isComposing = textView.markedTextRange != nil
      guard isComposing != lastCompositionState else { return }
      publish(textView)
    }

    private func publish(_ textView: UITextView) {
      let isComposing = textView.markedTextRange != nil
      lastCompositionState = isComposing
      parent.onChange(textView.text, isComposing)
    }
  }
}
