import Accessibility
import SwiftUI
import TendCore

private enum GoalProgressEntrySheetMetrics {
  // Presented sheets scale local geometry; two points preserve a 44-point screen hit target.
  static let minimumTarget = AlmanacMetrics.minimumTarget + 2
}

struct GoalProgressEntrySheet: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @FocusState private var isEntryFieldFocused: Bool
  @AccessibilityFocusState private var accessibilityFocus: AccessibilityFocus?

  let model: GoalDetailModel

  var body: some View {
    ScrollView {
      if let presentation = model.presentation, model.isPresentingEntrySheet {
        VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
          navigationHeader(presentation)

          Text(presentation.name)
            .almanacTextStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("goalProgressEntry.goalName")

          destinationSection(presentation)
          entrySection(presentation)

          if let failure = visibleOperationFailure {
            operationFailureCard(failure)
          }
        }
        .frame(maxWidth: AlmanacMetrics.readableContentWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, AlmanacMetrics.screenPadding)
        .padding(.top, AlmanacMetrics.spacingMedium)
        .padding(.bottom, AlmanacMetrics.spacingExtraLarge)
        .accessibilityElement(children: .contain)
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .background(AlmanacPalette.paper)
    .presentationDetents(
      dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
    )
    .presentationDragIndicator(.visible)
    .interactiveDismissDisabled(
      model.isOperationInFlight || visibleOperationFailure != nil
    )
    .accessibilityIdentifier("goalProgressEntry.sheet")
    .onAppear(perform: focusInitialElement)
    .onChange(of: visibleOperationFailure) { _, failure in
      guard let failure else { return }
      isEntryFieldFocused = false
      focusAndAnnounce(
        .operationFailure,
        message: failureAccessibilityMessage(failure)
      )
    }
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done", action: completeEntryEditing)
        .frame(
          minWidth: GoalProgressEntrySheetMetrics.minimumTarget,
          minHeight: GoalProgressEntrySheetMetrics.minimumTarget
        )
        .accessibilityIdentifier("goalProgressEntry.keyboardDone")
      }
    }
  }

  @ViewBuilder
  private func navigationHeader(_ presentation: GoalDetailPresentation) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(spacing: AlmanacMetrics.spacingSmall) {
        entryTitle(presentation)
        navigationActions(presentation)
      }
    } else {
      ZStack {
        entryTitle(presentation)
        navigationActions(presentation)
      }
    }
  }

  private func entryTitle(_ presentation: GoalDetailPresentation) -> some View {
    Text(copy(for: presentation).title)
      .font(.system(.title3, design: .serif, weight: .semibold))
      .foregroundStyle(AlmanacPalette.ink)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("goalProgressEntry.title")
  }

  private func navigationActions(_ presentation: GoalDetailPresentation) -> some View {
    HStack {
      Button(action: model.cancelEntrySheet) {
        Text("Cancel")
          .frame(
            minWidth: GoalProgressEntrySheetMetrics.minimumTarget,
            minHeight: GoalProgressEntrySheetMetrics.minimumTarget
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(canCancelEntry ? AlmanacPalette.clayDeep : AlmanacPalette.inkFaint)
      .disabled(!canCancelEntry)
      .accessibilityHint("Discards this \(entryNoun) without saving")
      .accessibilityIdentifier("goalProgressEntry.cancel")

      Spacer(minLength: AlmanacMetrics.spacingSmall)

      Button(action: saveEntry) {
        Text(model.isOperationInFlight ? "Saving…" : "Save")
          .fontWeight(.semibold)
          .frame(
            minWidth: GoalProgressEntrySheetMetrics.minimumTarget,
            minHeight: GoalProgressEntrySheetMetrics.minimumTarget
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(model.canSaveEntry ? AlmanacPalette.moss : AlmanacPalette.inkFaint)
      .disabled(!model.canSaveEntry)
      .accessibilityLabel(
        model.isOperationInFlight ? copy(for: presentation).savingLabel : copy(for: presentation).saveLabel
      )
      .accessibilityHint(copy(for: presentation).saveHint)
      .accessibilityIdentifier("goalProgressEntry.save")
    }
  }

  private func destinationSection(_ presentation: GoalDetailPresentation) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text("Date")
        .almanacTextStyle(.label)
        .accessibilityAddTraits(.isHeader)

      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(spacing: AlmanacMetrics.spacingSmall / 2) {
            destinationButtons(presentation)
          }
        } else {
          HStack(spacing: AlmanacMetrics.spacingSmall / 2) {
            destinationButtons(presentation)
          }
        }
      }
      .padding(AlmanacMetrics.spacingSmall / 2)
      .almanacSunkenSurface(
        radius: dynamicTypeSize.isAccessibilitySize
          ? AlmanacMetrics.insetRadius
          : AlmanacMetrics.tabPillRadius
      )
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Progress date")
      .accessibilityIdentifier("goalProgressEntry.destination")
    }
  }

  @ViewBuilder
  private func destinationButtons(_ presentation: GoalDetailPresentation) -> some View {
    ForEach(Array(presentation.appendDestinations.enumerated()), id: \.offset) { _, append in
      let isSelected = append.destination == model.selectedAppendDestination
      Button {
        model.selectAppendDestination(append.destination)
      } label: {
        Text(append.title)
          .font(.body.weight(.semibold))
          .foregroundStyle(isSelected ? AlmanacPalette.paper : AlmanacPalette.inkMuted)
          .frame(maxWidth: .infinity, minHeight: GoalProgressEntrySheetMetrics.minimumTarget)
          .padding(.horizontal, AlmanacMetrics.spacingSmall)
          .background(isSelected ? AlmanacPalette.moss : Color.clear, in: Capsule())
          .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .disabled(!model.canMutate)
      .accessibilityLabel(append.title)
      .accessibilityValue(isSelected ? "Selected" : "Not selected")
      .accessibilityAddTraits(isSelected ? .isSelected : [])
      .accessibilityIdentifier(
        "goalProgressEntry.destination.\(identifierComponent(for: append.destination))"
      )
    }
  }

  private func entrySection(_ presentation: GoalDetailPresentation) -> some View {
    let copy = copy(for: presentation)
    return VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(copy.fieldTitle)
        .almanacTextStyle(.label)
        .accessibilityAddTraits(.isHeader)

      TextField(copy.placeholder, text: entryBinding)
        .keyboardType(
          presentation.kind == .accumulate ? .numberPad : .numbersAndPunctuation
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .focused($isEntryFieldFocused)
        .onSubmit(completeEntryEditing)
        .disabled(!model.canMutate)
        .font(.body.monospacedDigit())
        .foregroundStyle(AlmanacPalette.ink)
        .padding(.horizontal, AlmanacMetrics.spacingMedium)
        .frame(
          maxWidth: .infinity,
          minHeight: GoalProgressEntrySheetMetrics.minimumTarget,
          alignment: .leading
        )
        .almanacSunkenSurface()
        .accessibilityLabel(copy.fieldTitle)
        .accessibilityHint(copy.fieldHint)
        .accessibilityIdentifier("goalProgressEntry.value")

      Text(copy.explanation)
        .almanacTextStyle(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("goalProgressEntry.explanation")

      if let validationMessage = model.entryValidationMessage {
        Text(validationMessage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(AlmanacPalette.ochreDeep)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel("Entry error. \(validationMessage)")
          .accessibilityFocused($accessibilityFocus, equals: .validation)
          .accessibilityIdentifier("goalProgressEntry.validation")
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func operationFailureCard(_ failure: GoalDetailOperationFailure) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(failure.message)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AlmanacPalette.ochreDeep)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(failureAccessibilityMessage(failure))
        .accessibilityFocused($accessibilityFocus, equals: .operationFailure)

      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
            failureActions(failure)
          }
        } else {
          HStack(spacing: AlmanacMetrics.spacingMedium) {
            failureActions(failure)
          }
        }
      }
    }
    .padding(AlmanacMetrics.spacingMedium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .almanacRaisedSurface()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("goalProgressEntry.failure")
  }

  @ViewBuilder
  private func failureActions(_ failure: GoalDetailOperationFailure) -> some View {
    Button(failure.retryTitle, action: model.retryOperation)
      .buttonStyle(.plain)
      .font(.body.weight(.semibold))
      .foregroundStyle(model.isOperationInFlight ? AlmanacPalette.inkFaint : AlmanacPalette.moss)
      .frame(
        minWidth: GoalProgressEntrySheetMetrics.minimumTarget,
        minHeight: GoalProgressEntrySheetMetrics.minimumTarget
      )
      .contentShape(Rectangle())
      .disabled(model.isOperationInFlight)
      .accessibilityHint(failureRetryHint(failure))
      .accessibilityIdentifier("goalProgressEntry.failure.retry")

    if let cancelTitle = failure.cancelTitle {
      Button(cancelTitle, action: model.cancelOperationFailure)
        .buttonStyle(.plain)
        .font(.body.weight(.semibold))
        .foregroundStyle(
          model.isOperationInFlight ? AlmanacPalette.inkFaint : AlmanacPalette.clayDeep
        )
        .frame(
          minWidth: GoalProgressEntrySheetMetrics.minimumTarget,
          minHeight: GoalProgressEntrySheetMetrics.minimumTarget
        )
        .contentShape(Rectangle())
        .disabled(model.isOperationInFlight)
        .accessibilityHint("Cancels this failed \(entryNoun)")
        .accessibilityIdentifier("goalProgressEntry.failure.cancel")
    }
  }

  private func completeEntryEditing() {
    isEntryFieldFocused = false
    guard let validationMessage = model.entryValidationMessage else { return }
    focusAndAnnounce(
      .validation,
      message: "Entry error. \(validationMessage)"
    )
  }

  private func saveEntry() {
    guard model.canSaveEntry else { return }
    isEntryFieldFocused = false
    model.saveEntry()
  }

  private func focusInitialElement() {
    Task { @MainActor in
      await Task.yield()
      if let failure = visibleOperationFailure {
        accessibilityFocus = .operationFailure
        announce(failureAccessibilityMessage(failure))
      } else {
        isEntryFieldFocused = true
      }
    }
  }

  private func focusAndAnnounce(
    _ focus: AccessibilityFocus,
    message: String
  ) {
    Task { @MainActor in
      await Task.yield()
      accessibilityFocus = focus
      announce(message)
    }
  }

  private var entryBinding: Binding<String> {
    Binding(
      get: { model.entryText },
      set: { model.entryText = $0 }
    )
  }

  private var canCancelEntry: Bool {
    !model.isOperationInFlight && visibleOperationFailure == nil
  }

  private var entryNoun: String {
    switch model.presentation?.kind {
    case .measure: "reading"
    case .accumulate, nil: "progress amount"
    }
  }

  private func failureAccessibilityMessage(
    _ failure: GoalDetailOperationFailure
  ) -> String {
    switch failure.placement {
    case .entrySheet:
      return "Save failed. \(failure.message)"
    case .reload:
      return "Refresh failed. \(failure.message)"
    case .history, .lifecycle, .goalDeletion:
      return "Action failed. \(failure.message)"
    }
  }

  private func failureRetryHint(
    _ failure: GoalDetailOperationFailure
  ) -> String {
    switch failure.placement {
    case .entrySheet:
      return "Retries saving this \(entryNoun)"
    case .reload:
      return "Retries refreshing the saved goal"
    case .history, .lifecycle, .goalDeletion:
      return "Retries the failed action"
    }
  }

  private var visibleOperationFailure: GoalDetailOperationFailure? {
    guard let failure = model.operationFailure else { return nil }
    switch failure.placement {
    case .entrySheet, .reload:
      return failure
    case .history, .lifecycle, .goalDeletion:
      return nil
    }
  }

  private func copy(for presentation: GoalDetailPresentation) -> EntryCopy {
    let unit = unit(in: presentation.progress)
    switch presentation.kind {
    case .accumulate:
      return EntryCopy(
        title: "Add progress",
        fieldTitle: "Amount",
        placeholder: "Positive whole number",
        explanation: "Add a positive whole number of \(unit).",
        fieldHint: "Required positive whole number of \(unit)",
        saveLabel: "Save progress",
        savingLabel: "Saving progress",
        saveHint: "Adds this amount without changing earlier entries"
      )
    case .measure:
      return EntryCopy(
        title: "Add reading",
        fieldTitle: "Reading",
        placeholder: "Signed whole number",
        explanation: "Record the current \(unit) reading. Negative values are allowed.",
        fieldHint: "Required signed whole number of \(unit). Negative values are allowed",
        saveLabel: "Save reading",
        savingLabel: "Saving reading",
        saveHint: "Records this reading without changing earlier readings"
      )
    }
  }

  private func unit(in progress: GoalDetailProgressFact) -> String {
    switch progress {
    case .accumulate(_, _, let unit, _),
      .measure(_, _, _, _, _, _, let unit, _):
      return unit
    }
  }

  private func identifierComponent(for destination: GoalProgressDestination) -> String {
    switch destination {
    case .today: "today"
    case .yesterday: "yesterday"
    }
  }

  private func announce(_ message: String) {
    AccessibilityNotification.Announcement(message).post()
  }
}

private struct EntryCopy {
  let title: String
  let fieldTitle: String
  let placeholder: String
  let explanation: String
  let fieldHint: String
  let saveLabel: String
  let savingLabel: String
  let saveHint: String
}

private enum AccessibilityFocus: Hashable {
  case validation
  case operationFailure
}
