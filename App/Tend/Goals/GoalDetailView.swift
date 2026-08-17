import Accessibility
import Foundation
import SwiftData
import SwiftUI
import TendCore

struct GoalDetailView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.scenePhase) private var scenePhase

  @State private var model: GoalDetailModel
  @State private var hasStarted = false
  @State private var hasLeftActiveScene = false

  private let onBack: () -> Void

  init(
    goal: Goal,
    context: ModelContext,
    onBack: @escaping () -> Void
  ) {
    _model = State(initialValue: GoalDetailModel(goal: goal, context: context))
    self.onBack = onBack
  }

  init(
    model: GoalDetailModel,
    onBack: @escaping () -> Void
  ) {
    _model = State(initialValue: model)
    self.onBack = onBack
  }

  var body: some View {
    VStack(spacing: 0) {
      navigationHeader

      ScrollView {
        content
      }
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize)
    }
    .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
    .accessibilityIdentifier("goalDetail.screen")
    .sheet(isPresented: entrySheetPresentation) {
      GoalProgressEntrySheet(model: model)
    }
    .sheet(isPresented: editPresentation) {
      if let goal = model.goalForEditing {
        GoalFormView(
          mode: .edit(goal),
          onSaved: model.editSaved
        )
      }
    }
    .alert(
      confirmationTitle,
      isPresented: confirmationPresentation,
      actions: confirmationActions,
      message: confirmationMessage
    )
    .onAppear(perform: startOnce)
    .onChange(of: scenePhase) { _, phase in
      guard hasStarted else { return }
      if phase == .active {
        guard hasLeftActiveScene else { return }
        hasLeftActiveScene = false
        guard
          !model.isPresentingEntrySheet,
          !model.isPresentingEdit,
          model.confirmation == nil
        else { return }
        model.refresh()
      } else {
        hasLeftActiveScene = true
      }
    }
    .onChange(of: model.isDeleted) { _, isDeleted in
      guard isDeleted else { return }
      onBack()
    }
    .onChange(of: model.loadFailure) { _, failure in
      guard let failure else { return }
      let prefix = model.presentation == nil ? "Goal load failed." : "Goal refresh failed."
      announce("\(prefix) \(failure.message)")
    }
    .onChange(of: model.operationFailure) { _, failure in
      guard let failure else { return }
      announceOperationFailure(failure)
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
      .accessibilityHint("Returns to goals")
      .accessibilityIdentifier("goalDetail.back")

      Spacer(minLength: 0)

      Button("Edit", action: model.presentEdit)
        .font(.body.weight(.semibold))
        .foregroundStyle(canEdit ? AlmanacPalette.clayDeep : AlmanacPalette.inkFaint)
        .frame(minWidth: AlmanacMetrics.minimumTarget, minHeight: AlmanacMetrics.minimumTarget)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(!canEdit)
        .accessibilityHint("Edits this goal, including closed goals")
        .accessibilityIdentifier("goalDetail.edit")
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
      Text(model.presentation?.name ?? "Goal")
        .almanacTextStyle(.screenTitle)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("goalDetail.title")

      if let presentation = model.presentation {
        verifiedContent(presentation)
      } else if let failure = model.loadFailure {
        loadFailureCard(failure, isRefreshFailure: false)
      } else {
        ProgressView("Loading goal")
          .tint(AlmanacPalette.moss)
          .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
          .accessibilityIdentifier("goalDetail.loading")
      }
    }
    .padding(.top, AlmanacMetrics.spacingMedium)
    .padding(.bottom, AlmanacMetrics.spacingExtraLarge)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func verifiedContent(_ presentation: GoalDetailPresentation) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
      if let loadFailure = model.loadFailure {
        loadFailureCard(loadFailure, isRefreshFailure: true)
      }

      if let reloadFailure = operationFailure(placement: .reload) {
        operationFailureCard(
          reloadFailure,
          identifierComponent: "reload",
          retryHint: "Retries refreshing the saved goal"
        )
      }

      GoalProgressView(
        progress: presentation.progress,
        progressText: presentation.progressText,
        standing: presentation.standing,
        expectedNormalizedProgress: presentation.expectedNormalizedProgress,
        standingText: presentation.standingText,
        closure: presentation.closure,
        closureText: presentation.closureText
      )
      .accessibilityIdentifier("goalDetail.progress")

      metadataSection(presentation)

      if presentation.actions.contains(.addProgress) {
        addProgressButton(presentation)
      }

      historySection(presentation)
      lifecycleSection(presentation)
      deleteGoalSection(presentation)
    }
  }

  private func metadataSection(_ presentation: GoalDetailPresentation) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
      Text("Details")
        .almanacTextStyle(.label)
        .accessibilityAddTraits(.isHeader)

      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
            metadataFact(label: "Kind", value: kindTitle(presentation.kind))
            metadataFact(label: "Deadline", value: presentation.deadlineText)
          }
        } else {
          HStack(alignment: .top, spacing: AlmanacMetrics.spacingLarge) {
            metadataFact(label: "Kind", value: kindTitle(presentation.kind))
              .frame(maxWidth: .infinity, alignment: .leading)
            metadataFact(label: "Deadline", value: presentation.deadlineText)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
    .padding(AlmanacMetrics.spacingMedium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .almanacSunkenSurface()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("goalDetail.metadata")
  }

  private func metadataFact(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall / 2) {
      Text(label)
        .almanacTextStyle(.label)
      Text(value)
        .almanacTextStyle(.body)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(value)
    .accessibilityIdentifier("goalDetail.metadata.\(label.lowercased())")
  }

  private func addProgressButton(_ presentation: GoalDetailPresentation) -> some View {
    Button(action: model.presentEntrySheet) {
      Text("Add Progress")
        .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
        .contentShape(Capsule())
    }
    .buttonStyle(AlmanacPrimaryButtonStyle())
    .disabled(!canPerform(.addProgress, in: presentation))
    .accessibilityHint(addProgressHint(for: presentation.kind))
    .accessibilityIdentifier("goalDetail.addProgress")
  }

  private func historySection(_ presentation: GoalDetailPresentation) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
      Text("History")
        .almanacTextStyle(.label)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("goalDetail.history.title")

      if presentation.history.isEmpty {
        Text(historyEmptyMessage(presentation))
          .almanacTextStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(AlmanacMetrics.spacingMedium)
          .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget, alignment: .leading)
          .almanacSunkenSurface()
          .accessibilityIdentifier("goalDetail.history.empty")
      } else {
        VStack(spacing: 0) {
          ForEach(Array(presentation.history.enumerated()), id: \.element.id) { index, fact in
            GoalDetailHistoryRow(
              fact: fact,
              kind: presentation.kind,
              isDisabled: !model.canMutate,
              delete: { model.requestHistoryDeletion(fact.id) }
            )

            if index != presentation.history.indices.last {
              Divider()
                .overlay(AlmanacPalette.hairline)
                .accessibilityHidden(true)
            }
          }
        }
        .almanacRaisedSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("goalDetail.history")
      }

      if let historyFailure = operationFailure(placement: .history) {
        operationFailureCard(
          historyFailure,
          identifierComponent: "history",
          retryHint: "Retries deleting this history item"
        )
      }
    }
  }

  @ViewBuilder
  private func lifecycleSection(_ presentation: GoalDetailPresentation) -> some View {
    let showsLifecycleActions =
      presentation.actions.contains(.harvest)
      || presentation.actions.contains(.letGo)
      || presentation.actions.contains(.reopen)

    if showsLifecycleActions {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
        Text("Goal status")
          .almanacTextStyle(.label)
          .accessibilityAddTraits(.isHeader)

        if presentation.actions.contains(.reopen) {
          Button {
            model.requestConfirmation(.reopen)
          } label: {
            Text("Reopen")
              .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
              .contentShape(Capsule())
          }
          .buttonStyle(AlmanacPrimaryButtonStyle())
          .disabled(!canPerform(.reopen, in: presentation))
          .accessibilityHint("Confirms reopening this goal for progress entry")
          .accessibilityIdentifier("goalDetail.reopen")
        } else {
          Group {
            if dynamicTypeSize.isAccessibilitySize {
              VStack(spacing: AlmanacMetrics.spacingSmall) {
                openLifecycleButtons(presentation)
              }
            } else {
              HStack(spacing: AlmanacMetrics.spacingSmall) {
                openLifecycleButtons(presentation)
              }
            }
          }
        }

        if let lifecycleFailure = operationFailure(placement: .lifecycle) {
          operationFailureCard(
            lifecycleFailure,
            identifierComponent: "lifecycle",
            retryHint: "Retries changing this goal's status"
          )
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("goalDetail.lifecycle")
    }
  }

  @ViewBuilder
  private func openLifecycleButtons(_ presentation: GoalDetailPresentation) -> some View {
    if presentation.actions.contains(.harvest) {
      lifecycleButton(
        title: "Harvest",
        color: AlmanacPalette.mossDeep,
        isEnabled: canPerform(.harvest, in: presentation),
        hint: "Confirms closing this goal as harvested",
        identifier: "goalDetail.harvest"
      ) {
        model.requestConfirmation(.harvest)
      }
    }

    if presentation.actions.contains(.letGo) {
      lifecycleButton(
        title: "Let go",
        color: AlmanacPalette.clayDeep,
        isEnabled: canPerform(.letGo, in: presentation),
        hint: "Confirms closing this goal as let go",
        identifier: "goalDetail.letGo"
      ) {
        model.requestConfirmation(.letGo)
      }
    }
  }

  private func lifecycleButton(
    title: String,
    color: Color,
    isEnabled: Bool,
    hint: String,
    identifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
        .font(.body.weight(.semibold))
        .foregroundStyle(isEnabled ? color : AlmanacPalette.inkFaint)
        .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
        .padding(.horizontal, AlmanacMetrics.spacingMedium)
        .contentShape(Capsule())
        .almanacRaisedSurface(radius: AlmanacMetrics.tabPillRadius)
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityHint(hint)
    .accessibilityIdentifier(identifier)
  }

  @ViewBuilder
  private func deleteGoalSection(_ presentation: GoalDetailPresentation) -> some View {
    if presentation.actions.contains(.deleteGoal) {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
        Button {
          model.requestConfirmation(.deleteGoal)
        } label: {
          Text("Delete Goal")
            .font(.body.weight(.semibold))
            .foregroundStyle(
              canPerform(.deleteGoal, in: presentation)
                ? AlmanacPalette.clayDeep
                : AlmanacPalette.inkFaint
            )
            .frame(minHeight: AlmanacMetrics.minimumTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canPerform(.deleteGoal, in: presentation))
        .accessibilityLabel("Permanently delete \(presentation.name)")
        .accessibilityHint("Confirms deleting the goal and all of its history")
        .accessibilityIdentifier("goalDetail.deleteGoal")

        if let deletionFailure = operationFailure(placement: .goalDeletion) {
          operationFailureCard(
            deletionFailure,
            identifierComponent: "goalDeletion",
            retryHint: "Retries permanently deleting this goal"
          )
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("goalDetail.deletion")
    }
  }

  private func loadFailureCard(
    _ failure: GoalDetailLoadFailure,
    isRefreshFailure: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(failure.message)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AlmanacPalette.ochreDeep)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(
          isRefreshFailure
            ? "Refresh failed. \(failure.message)"
            : "Load failed. \(failure.message)"
        )

      Button(failure.retryTitle, action: model.retryLoad)
        .buttonStyle(.plain)
        .font(.body.weight(.semibold))
        .foregroundStyle(model.isOperationInFlight ? AlmanacPalette.inkFaint : AlmanacPalette.moss)
        .frame(minWidth: AlmanacMetrics.minimumTarget, minHeight: AlmanacMetrics.minimumTarget)
        .contentShape(Rectangle())
        .disabled(model.isOperationInFlight)
        .accessibilityHint(
          isRefreshFailure ? "Retries refreshing this goal" : "Retries loading this goal"
        )
        .accessibilityIdentifier("goalDetail.loadFailure.retry")
    }
    .padding(AlmanacMetrics.spacingMedium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .almanacSunkenSurface()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(
      isRefreshFailure ? "goalDetail.refreshFailure" : "goalDetail.loadFailure"
    )
  }

  private func operationFailureCard(
    _ failure: GoalDetailOperationFailure,
    identifierComponent: String,
    retryHint: String
  ) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(failure.message)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AlmanacPalette.ochreDeep)
        .fixedSize(horizontal: false, vertical: true)

      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
            operationFailureActions(
              failure,
              identifierComponent: identifierComponent,
              retryHint: retryHint
            )
          }
        } else {
          HStack(spacing: AlmanacMetrics.spacingMedium) {
            operationFailureActions(
              failure,
              identifierComponent: identifierComponent,
              retryHint: retryHint
            )
          }
        }
      }
    }
    .padding(AlmanacMetrics.spacingMedium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .almanacRaisedSurface()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("goalDetail.failure.\(identifierComponent)")
  }

  @ViewBuilder
  private func operationFailureActions(
    _ failure: GoalDetailOperationFailure,
    identifierComponent: String,
    retryHint: String
  ) -> some View {
    Button(failure.retryTitle, action: model.retryOperation)
      .buttonStyle(.plain)
      .font(.body.weight(.semibold))
      .foregroundStyle(model.isOperationInFlight ? AlmanacPalette.inkFaint : AlmanacPalette.moss)
      .frame(minWidth: AlmanacMetrics.minimumTarget, minHeight: AlmanacMetrics.minimumTarget)
      .contentShape(Rectangle())
      .disabled(model.isOperationInFlight)
      .accessibilityHint(retryHint)
      .accessibilityIdentifier("goalDetail.failure.\(identifierComponent).retry")

    if let cancelTitle = failure.cancelTitle {
      Button(cancelTitle, action: model.cancelOperationFailure)
        .buttonStyle(.plain)
        .font(.body.weight(.semibold))
        .foregroundStyle(
          model.isOperationInFlight ? AlmanacPalette.inkFaint : AlmanacPalette.clayDeep
        )
        .frame(minWidth: AlmanacMetrics.minimumTarget, minHeight: AlmanacMetrics.minimumTarget)
        .contentShape(Rectangle())
        .disabled(model.isOperationInFlight)
        .accessibilityHint("Cancels the failed action and keeps the goal unchanged")
        .accessibilityIdentifier("goalDetail.failure.\(identifierComponent).cancel")
    }
  }

  private func operationFailure(
    placement: GoalDetailOperationFailure.Placement
  ) -> GoalDetailOperationFailure? {
    guard model.operationFailure?.placement == placement else { return nil }
    return model.operationFailure
  }

  private func startOnce() {
    guard !hasStarted else { return }
    hasStarted = true
    hasLeftActiveScene = false
    model.start()
  }

  private func canPerform(
    _ action: GoalDetailAction,
    in presentation: GoalDetailPresentation
  ) -> Bool {
    model.canMutate && presentation.actions.contains(action)
  }

  private var canEdit: Bool {
    guard let presentation = model.presentation else { return false }
    return canPerform(.edit, in: presentation)
  }

  private var entrySheetPresentation: Binding<Bool> {
    Binding(
      get: { model.isPresentingEntrySheet },
      set: { isPresented in
        if isPresented {
          model.presentEntrySheet()
        } else {
          model.cancelEntrySheet()
        }
      }
    )
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

  private var confirmationPresentation: Binding<Bool> {
    Binding(
      get: {
        model.confirmation != nil && model.canMutate
      },
      set: { isPresented in
        if !isPresented {
          model.cancelConfirmation()
        }
      }
    )
  }

  @ViewBuilder
  private func confirmationActions() -> some View {
    Button("Cancel", role: .cancel, action: model.cancelConfirmation)
      .accessibilityIdentifier("goalDetail.confirmation.cancel")

    Button(
      confirmationActionTitle,
      role: confirmationRole,
      action: model.confirmPendingAction
    )
    .accessibilityIdentifier("goalDetail.confirmation.confirm")
  }

  @ViewBuilder
  private func confirmationMessage() -> some View {
    Text(confirmationMessageText)
  }

  private var confirmationTitle: String {
    guard let confirmation = model.confirmation else { return "Confirm action" }
    let name = model.presentation?.name ?? "this goal"
    switch confirmation {
    case .harvest:
      return "Harvest “\(name)”?"
    case .letGo:
      return "Let go of “\(name)”?"
    case .reopen:
      return "Reopen “\(name)”?"
    case .deleteGoal:
      return "Delete “\(name)” permanently?"
    case .deleteHistory(let id):
      return "Delete this \(historyNoun(for: id))?"
    }
  }

  private var confirmationActionTitle: String {
    guard let confirmation = model.confirmation else { return "Continue" }
    return switch confirmation {
    case .harvest: "Harvest"
    case .letGo: "Let go"
    case .reopen: "Reopen"
    case .deleteGoal: "Delete Goal"
    case .deleteHistory(let id): "Delete \(historyNoun(for: id).capitalized)"
    }
  }

  private var confirmationRole: ButtonRole? {
    switch model.confirmation {
    case .letGo, .deleteGoal, .deleteHistory:
      return .destructive
    case .harvest, .reopen, nil:
      return nil
    }
  }

  private var confirmationMessageText: String {
    guard let confirmation = model.confirmation else { return "" }
    let presentation = model.presentation
    let name = presentation?.name ?? "this goal"
    switch confirmation {
    case .harvest:
      return
        "This closes “\(name)” as harvested and keeps its progress history. You can reopen it later."
    case .letGo:
      return
        "This closes “\(name)” as let go and keeps its progress history. You can reopen it later."
    case .reopen:
      return "This reopens “\(name)” and makes progress entry available again."
    case .deleteGoal:
      let noun = presentation?.kind == .measure ? "reading" : "entry"
      return
        "This permanently deletes “\(name)” and removes all of its \(noun) history. This cannot be undone."
    case .deleteHistory(let id):
      return historyDeletionMessage(id)
    }
  }

  private func historyDeletionMessage(_ id: GoalDetailHistoryID) -> String {
    guard let fact = model.presentation?.history.first(where: { $0.id == id }) else {
      return
        "This permanently removes the history item and may change the goal's progress. This cannot be undone."
    }

    switch id {
    case .entry:
      return
        "This permanently removes the \(fact.valueText) entry for \(fact.dateText) and recalculates the goal's progress. This cannot be undone."
    case .reading:
      return
        "This permanently removes the \(fact.valueText) reading for \(fact.dateText). Progress will be recalculated from the remaining readings. This cannot be undone."
    }
  }

  private func historyNoun(for id: GoalDetailHistoryID) -> String {
    switch id {
    case .entry: "entry"
    case .reading: "reading"
    }
  }

  private func kindTitle(_ kind: GoalKind) -> String {
    switch kind {
    case .accumulate: "Accumulate"
    case .measure: "Measure"
    }
  }

  private func addProgressHint(for kind: GoalKind) -> String {
    switch kind {
    case .accumulate: "Opens a sheet to add an amount"
    case .measure: "Opens a sheet to record a reading"
    }
  }

  private func historyEmptyMessage(_ presentation: GoalDetailPresentation) -> String {
    if presentation.actions.contains(.addProgress) {
      return "No progress recorded yet. Use Add Progress to record the first update."
    }
    return "No progress was recorded before this goal closed."
  }

  private func announceOperationFailure(
    _ failure: GoalDetailOperationFailure
  ) {
    if model.isPresentingEntrySheet {
      switch failure.placement {
      case .entrySheet, .reload:
        return
      case .history, .lifecycle, .goalDeletion:
        break
      }
    }

    let prefix: String
    switch failure.placement {
    case .entrySheet:
      prefix = "Save failed."
    case .history:
      prefix = "History deletion failed."
    case .lifecycle:
      prefix = "Goal status change failed."
    case .goalDeletion:
      prefix = "Goal deletion failed."
    case .reload:
      prefix = "Goal refresh failed."
    }
    announce("\(prefix) \(failure.message)")
  }

  private func announce(_ message: String) {
    AccessibilityNotification.Announcement(message).post()
  }
}

private struct GoalDetailHistoryRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let fact: GoalDetailHistoryFact
  let kind: GoalKind
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
      .padding(.horizontal, AlmanacMetrics.spacingMedium)
      .padding(.vertical, AlmanacMetrics.spacingSmall)
    } else {
      HStack(alignment: .center, spacing: AlmanacMetrics.spacingMedium) {
        details
        Spacer(minLength: AlmanacMetrics.spacingSmall)
        deleteButton
      }
      .padding(.leading, AlmanacMetrics.spacingMedium)
      .padding(.trailing, AlmanacMetrics.spacingSmall)
      .padding(.vertical, AlmanacMetrics.spacingSmall)
    }
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall / 2) {
      Text(fact.dateText)
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)

      Text(fact.valueText)
        .almanacTextStyle(.body)
        .fixedSize(horizontal: false, vertical: true)

      if kind == .measure {
        Text(fact.isEffective ? "Current reading" : "Earlier reading")
          .almanacTextStyle(.caption)
          .foregroundStyle(
            fact.isEffective ? AlmanacPalette.mossDeep : AlmanacPalette.inkMuted
          )
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(detailsAccessibilityLabel)
    .accessibilityIdentifier("goalDetail.history.row.\(identifierComponent)")
  }

  @ViewBuilder
  private var deleteButton: some View {
    if fact.isDeleteEligible {
      Button(action: delete) {
        Image(systemName: "minus.circle")
          .font(.title3.weight(.semibold))
          .frame(
            width: AlmanacMetrics.minimumTarget,
            height: AlmanacMetrics.minimumTarget
          )
          .contentShape(Rectangle())
          .accessibilityHidden(true)
      }
      .buttonStyle(.plain)
      .foregroundStyle(isDisabled ? AlmanacPalette.inkFaint : AlmanacPalette.clayDeep)
      .disabled(isDisabled)
      .accessibilityLabel(
        "Delete \(historyNoun), \(fact.valueText), \(fact.dateText)"
      )
      .accessibilityHint(
        "Confirms removing this \(historyNoun) and updating goal progress"
      )
      .accessibilityIdentifier("goalDetail.history.delete.\(identifierComponent)")
    }
  }

  private var historyNoun: String {
    switch fact.id {
    case .entry: "entry"
    case .reading: "reading"
    }
  }

  private var detailsAccessibilityLabel: String {
    guard kind == .measure else {
      return "\(fact.dateText), \(fact.valueText)"
    }
    let readingState = fact.isEffective ? "current reading" : "earlier reading"
    return "\(fact.dateText), \(fact.valueText), \(readingState)"
  }

  private var identifierComponent: String {
    switch fact.id {
    case .entry(let identity):
      "entry.\(identity.rawValue.uuidString)"
    case .reading(let identity):
      "reading.\(identity.rawValue.uuidString)"
    }
  }
}
