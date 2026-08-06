import Accessibility
import SwiftUI
import TendCore

private enum QuantityLogSheetMetrics {
  // A presented sheet scales local geometry; two points preserve a 44-point screen hit target.
  static let minimumTarget = AlmanacMetrics.minimumTarget + 2
}

struct QuantityLogSheet: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.dismiss) private var dismiss
  @FocusState private var isAmountFieldFocused: Bool
  @AccessibilityFocusState private var isProgressFocused: Bool

  let model: TodayLoggingModel
  let habits: [Habit]
  let showsCloseButton: Bool
  let makeContext: () -> TodayRefreshContext

  var body: some View {
    ScrollView {
      if let sheet = model.state.sheet {
        VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
          sheetHeader(sheet)

          scopeControl(sheet)
          progressSection(sheet)
          quickAddSection(sheet)
          amountSection(sheet)

          if let sheetError = sheet.sheetError {
            inlineError(sheetError, identifier: "log-sheet.error")
          }

          entrySection(sheet)

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
    .accessibilityIdentifier("log-sheet")
    .background(AlmanacPalette.paper)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let sheet = model.state.sheet,
        let undo = model.state.undo(for: sheet.habitID)
      {
        TodayLogUndoBar(undo: undo, habitName: sheet.habitName) {
          model.undo(habits: habits, context: makeContext())
        }
      }
    }
    .onChange(of: model.state.sheet) { oldSheet, newSheet in
      if oldSheet?.amountEditorMode == nil, newSheet?.amountEditorMode != nil {
        Task { @MainActor in
          await Task.yield()
          isAmountFieldFocused = true
        }
      } else if newSheet?.amountEditorMode == nil {
        isAmountFieldFocused = false
      }
      if newSheet?.sheetError != oldSheet?.sheetError {
        announce(newSheet?.sheetError)
      }
      if newSheet?.amountError != oldSheet?.amountError {
        announce(newSheet?.amountError)
      }
    }
    .onChange(of: model.state.announcementToken) { _, _ in
      guard let sheet = model.state.sheet else { return }
      AccessibilityNotification.Announcement(progressText(for: sheet)).post()
    }
  }

  @ViewBuilder
  private func sheetHeader(_ sheet: LogSheetPresentation) -> some View {
    if showsCloseButton {
      HStack(alignment: .top, spacing: AlmanacMetrics.spacingMedium) {
        sheetTitle(sheet)
        Spacer(minLength: AlmanacMetrics.spacingMedium)
        Button("Close") {
          dismiss()
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AlmanacPalette.ink)
        .frame(
          minWidth: QuantityLogSheetMetrics.minimumTarget,
          minHeight: QuantityLogSheetMetrics.minimumTarget
        )
        .contentShape(Rectangle())
        .accessibilityIdentifier("log-sheet.close")
      }
    } else {
      sheetTitle(sheet)
    }
  }

  private func sheetTitle(_ sheet: LogSheetPresentation) -> some View {
    Text(sheet.habitName)
      .almanacTextStyle(.screenTitle)
      .foregroundStyle(AlmanacPalette.ink)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("log-sheet.title")
      .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder
  private func scopeControl(_ sheet: LogSheetPresentation) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: AlmanacMetrics.spacingSmall) {
          scopeButtons(sheet)
        }
      } else {
        HStack(spacing: AlmanacMetrics.spacingSmall) {
          scopeButtons(sheet)
        }
      }
    }
    .padding(4)
    .almanacSunkenSurface(radius: AlmanacMetrics.cardRadius)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Logging period")
  }

  @ViewBuilder
  private func scopeButtons(_ sheet: LogSheetPresentation) -> some View {
    ForEach(sheet.scopes) { scope in
      scopeButton(scope, selectedPeriodKey: sheet.selectedPeriodKey)
    }
  }

  private func scopeButton(
    _ scope: LogSheetScope,
    selectedPeriodKey: String
  ) -> some View {
    let isSelected = scope.periodKey == selectedPeriodKey
    return Button {
      model.selectPeriod(
        scope.periodKey,
        habits: habits,
        context: makeContext()
      )
      isProgressFocused = true
    } label: {
      HStack(spacing: AlmanacMetrics.spacingSmall) {
        if scope.showsUnfinishedMarker {
          Circle()
            .fill(AlmanacPalette.ochreDeep)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
        }
        Text(scope.label)
          .font(.subheadline.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
      }
      .foregroundStyle(isSelected ? AlmanacPalette.paper : AlmanacPalette.ink)
      .frame(maxWidth: .infinity, minHeight: QuantityLogSheetMetrics.minimumTarget)
      .padding(.horizontal, AlmanacMetrics.spacingSmall)
      .background(isSelected ? AlmanacPalette.moss : Color.clear, in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(scope.label)
    .accessibilityValue(scope.showsUnfinishedMarker ? "Unfinished" : "")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier("log-sheet.scope.\(scope.label)")
  }

  private func progressSection(_ sheet: LogSheetPresentation) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      LogSheetProgressTrack(fraction: sheet.progressFraction)
        .accessibilityHidden(true)

      Text(progressText(for: sheet))
        .almanacTextStyle(.body)
        .foregroundStyle(AlmanacPalette.inkMuted)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("log-sheet.progress")
        .accessibilityFocused($isProgressFocused)

      Text(streakText(for: sheet))
        .almanacTextStyle(.secondary)
        .foregroundStyle(AlmanacPalette.inkMuted)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("log-sheet.streak")
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private func quickAddSection(_ sheet: LogSheetPresentation) -> some View {
    let amounts = sheet.quickAddAmounts
    if !amounts.presets.isEmpty || amounts.finish != nil {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
        Text("QUICK ADD")
          .almanacTextStyle(.label)
          .foregroundStyle(AlmanacPalette.ink)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)

        Group {
          if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
              quickAddButtons(sheet, stacked: true)
            }
          } else {
            HStack(spacing: AlmanacMetrics.spacingSmall) {
              quickAddButtons(sheet, stacked: false)
            }
          }
        }
        .accessibilityElement(children: .contain)
      }
    }
  }

  @ViewBuilder
  private func quickAddButtons(
    _ sheet: LogSheetPresentation,
    stacked: Bool
  ) -> some View {
    ForEach(sheet.quickAddAmounts.presets, id: \.self) { amount in
      quickAddButton(amount: amount, sheet: sheet, isFinish: false, stacked: stacked)
    }
    if let finish = sheet.quickAddAmounts.finish {
      quickAddButton(amount: finish, sheet: sheet, isFinish: true, stacked: stacked)
    }
  }

  private func quickAddButton(
    amount: Int,
    sheet: LogSheetPresentation,
    isFinish: Bool,
    stacked: Bool
  ) -> some View {
    Button {
      model.appendQuickAdd(
        amount: amount,
        habits: habits,
        context: makeContext()
      )
    } label: {
      ZStack {
        Capsule()
          .fill(isFinish ? AlmanacPalette.moss : Color.clear)
          .allowsHitTesting(false)
        if !isFinish {
          Capsule()
            .stroke(AlmanacPalette.moss, lineWidth: 1)
            .allowsHitTesting(false)
        }
        Text(
          isFinish
            ? "Finish · \(amount.formatted()) \(sheet.unit)"
            : "+\(amount.formatted())"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isFinish ? AlmanacPalette.paper : AlmanacPalette.mossDeep)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, AlmanacMetrics.spacingMedium)
      }
      .frame(
        minWidth: QuantityLogSheetMetrics.minimumTarget,
        maxWidth: stacked ? .infinity : nil,
        minHeight: QuantityLogSheetMetrics.minimumTarget
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .frame(
      minWidth: QuantityLogSheetMetrics.minimumTarget,
      maxWidth: stacked ? .infinity : nil,
      minHeight: QuantityLogSheetMetrics.minimumTarget
    )
    .contentShape(Rectangle())
    .accessibilityLabel(
      isFinish
        ? "Finish with \(amount.formatted()) \(sheet.unit)"
        : "Add \(amount.formatted()) \(sheet.unit)"
    )
    .accessibilityValue("\(amount.formatted()) \(sheet.unit)")
    .accessibilityIdentifier(
      isFinish ? "log-sheet.quick-add.finish" : "log-sheet.quick-add.\(amount)"
    )
  }

  @ViewBuilder
  private func amountSection(_ sheet: LogSheetPresentation) -> some View {
    if let mode = sheet.amountEditorMode {
      amountEditor(sheet, mode: mode)
    } else {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(spacing: 0) {
            customAmountButton
            Divider().overlay(AlmanacPalette.hairline)
            setTotalButton(cadence: sheet.cadence)
          }
        } else {
          HStack(spacing: 0) {
            customAmountButton
            Divider()
              .overlay(AlmanacPalette.hairline)
              .frame(height: QuantityLogSheetMetrics.minimumTarget)
            setTotalButton(cadence: sheet.cadence)
          }
        }
      }
      .almanacSunkenSurface(radius: AlmanacMetrics.cardRadius)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("log-sheet.amount-actions")
    }
  }

  private var customAmountButton: some View {
    Button("Custom amount") {
      model.beginCustomAmountEditing()
    }
    .buttonStyle(.plain)
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(AlmanacPalette.ink)
    .frame(maxWidth: .infinity, minHeight: QuantityLogSheetMetrics.minimumTarget)
    .padding(.horizontal, AlmanacMetrics.spacingSmall)
    .contentShape(Rectangle())
    .accessibilityIdentifier("log-sheet.amount.custom")
  }

  private func setTotalButton(cadence: HabitCadence) -> some View {
    let label = cadence == .daily ? "Set day total" : "Set week total"
    return Button(label) {
      model.beginSetTotalEditing()
    }
    .buttonStyle(.plain)
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(AlmanacPalette.ink)
    .frame(maxWidth: .infinity, minHeight: QuantityLogSheetMetrics.minimumTarget)
    .padding(.horizontal, AlmanacMetrics.spacingSmall)
    .contentShape(Rectangle())
    .accessibilityIdentifier("log-sheet.amount.set-total")
  }

  private func amountEditor(
    _ sheet: LogSheetPresentation,
    mode: LogAmountEditorMode
  ) -> some View {
    let title = editorTitle(mode: mode, cadence: sheet.cadence)
    let submitLabel = mode == .customAmount ? "Add" : "Set total"

    return VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(title)
        .almanacTextStyle(.label)
        .foregroundStyle(AlmanacPalette.ink)
        .accessibilityAddTraits(.isHeader)

      TextField("Whole number", text: amountInputBinding)
        .keyboardType(.numberPad)
        .submitLabel(.done)
        .focused($isAmountFieldFocused)
        .onSubmit(submitAmount)
        .font(.body.monospacedDigit())
        .foregroundStyle(AlmanacPalette.ink)
        .padding(.horizontal, AlmanacMetrics.spacingMedium)
        .frame(minHeight: QuantityLogSheetMetrics.minimumTarget)
        .background(AlmanacPalette.paperRaised, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(AlmanacPalette.hairline, lineWidth: 1)
            .allowsHitTesting(false)
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier("log-sheet.amount.field")
        .toolbar {
          ToolbarItemGroup(placement: .keyboard) {
            Button("Cancel", action: cancelAmountEditor)
              .accessibilityIdentifier("log-sheet.amount.keyboard-cancel")
              .simultaneousGesture(
                TapGesture().onEnded {
                  cancelAmountEditor()
                }
              )
            Spacer()
            Button(submitLabel, action: submitAmount)
              .accessibilityIdentifier("log-sheet.amount.keyboard-submit")
          }
        }

      if let amountError = sheet.amountError {
        inlineError(amountError, identifier: "log-sheet.amount.error")
      }

      HStack(spacing: AlmanacMetrics.spacingSmall) {
        Button(submitLabel, action: submitAmount)
          .buttonStyle(
            AlmanacPrimaryButtonStyle(minimumTarget: QuantityLogSheetMetrics.minimumTarget)
          )
          .accessibilityIdentifier("log-sheet.amount.submit")

        Button("Cancel", action: cancelAmountEditor)
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AlmanacPalette.ink)
        .frame(
          minWidth: QuantityLogSheetMetrics.minimumTarget,
          minHeight: QuantityLogSheetMetrics.minimumTarget
        )
        .padding(.horizontal, AlmanacMetrics.spacingSmall)
        .contentShape(Rectangle())
        .accessibilityIdentifier("log-sheet.amount.cancel")
      }
    }
    .padding(AlmanacMetrics.spacingMedium)
    .almanacSunkenSurface(radius: AlmanacMetrics.cardRadius)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("log-sheet.amount-editor")
  }

  private var amountInputBinding: Binding<String> {
    Binding(
      get: { model.state.sheet?.amountInput ?? "" },
      set: { value in model.updateAmountInput(value) }
    )
  }

  private func submitAmount() {
    model.submitAmount(habits: habits, context: makeContext())
  }

  private func cancelAmountEditor() {
    isAmountFieldFocused = false
    model.cancelAmountEditing()
  }

  @ViewBuilder
  private func entrySection(_ sheet: LogSheetPresentation) -> some View {
    if let scope = sheet.scopes.first(where: { $0.periodKey == sheet.selectedPeriodKey }) {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
        Text(scope.entryListLabel)
          .almanacTextStyle(.label)
          .foregroundStyle(AlmanacPalette.ink)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("log-sheet.entries.title")
          .accessibilityAddTraits(.isHeader)

        if sheet.entries.isEmpty {
          Text("Nothing logged in this period.")
            .almanacTextStyle(.secondary)
            .foregroundStyle(AlmanacPalette.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("log-sheet.entries.empty")
        } else {
          VStack(spacing: 0) {
            ForEach(sheet.entries) { entry in
              if entry.id != sheet.entries.first?.id {
                Divider().overlay(AlmanacPalette.hairline)
              }
              entryRow(entry)
            }
          }
          .background(AlmanacPalette.paperRaised)
          .clipShape(RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius))
          .overlay {
            RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius)
              .stroke(AlmanacPalette.hairline, lineWidth: 1)
              .allowsHitTesting(false)
          }
          .accessibilityElement(children: .contain)
        }
      }
    }
  }

  private func entryRow(_ entry: LogSheetEntryPresentation) -> some View {
    HStack(alignment: .center, spacing: AlmanacMetrics.spacingMedium) {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall / 2) {
        Text(entry.timestampText)
          .almanacTextStyle(.secondary)
          .foregroundStyle(AlmanacPalette.inkMuted)
        Text(entry.amountText)
          .almanacTextStyle(.body)
          .foregroundStyle(AlmanacPalette.ink)
      }
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(entry.accessibilityLabel)

      Spacer(minLength: AlmanacMetrics.spacingSmall)

      Button {
        model.deleteEntry(
          entry.id,
          habits: habits,
          context: makeContext()
        )
      } label: {
        Image(systemName: "minus.circle")
          .font(.title3.weight(.semibold))
          .foregroundStyle(AlmanacPalette.clayDeep)
          .frame(
            width: QuantityLogSheetMetrics.minimumTarget,
            height: QuantityLogSheetMetrics.minimumTarget
          )
          .contentShape(Rectangle())
          .accessibilityHidden(true)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Delete \(entry.accessibilityLabel)")
      .accessibilityIdentifier("log-sheet.delete.\(entry.uuid.uuidString)")
    }
    .padding(.leading, AlmanacMetrics.spacingMedium)
    .padding(.trailing, AlmanacMetrics.spacingSmall)
    .padding(.vertical, AlmanacMetrics.spacingSmall)
    .frame(minHeight: QuantityLogSheetMetrics.minimumTarget)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("log-sheet.entry.\(entry.uuid.uuidString)")
  }

  private func inlineError(_ message: String, identifier: String) -> some View {
    Text(message)
      .almanacTextStyle(.secondary)
      .foregroundStyle(AlmanacPalette.ochreDeep)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier(identifier)
  }

  private func progressText(for sheet: LogSheetPresentation) -> String {
    "\(sheet.progress.formatted()) of \(sheet.target.formatted()) \(sheet.unit)"
  }

  private func streakText(for sheet: LogSheetPresentation) -> String {
    let period = sheet.cadence == .daily ? "day" : "week"
    return "\(sheet.currentStreak) \(period) streak"
  }

  private func editorTitle(mode: LogAmountEditorMode, cadence: HabitCadence) -> String {
    switch mode {
    case .customAmount:
      "Custom amount"
    case .setTotal:
      cadence == .daily ? "Set day total" : "Set week total"
    }
  }

  private func announce(_ message: String?) {
    guard let message else { return }
    AccessibilityNotification.Announcement(message).post()
  }
}

struct TodayLogUndoBar: View {
  let undo: TodayLogUndo
  let habitName: String
  let action: () -> Void

  var body: some View {
    TodayLogUndoRow(
      undo: undo,
      habitName: habitName,
      identifier: "log-sheet.undo",
      actionIdentifier: "log-sheet.undo.action",
      action: action
    )
    .padding(.leading, AlmanacMetrics.spacingMedium)
    .padding(.trailing, AlmanacMetrics.spacingSmall)
    .padding(.vertical, AlmanacMetrics.spacingSmall)
    .almanacRaisedSurface(radius: AlmanacMetrics.cardRadius)
    .padding(.horizontal, AlmanacMetrics.screenPadding)
    .padding(.bottom, AlmanacMetrics.spacingSmall)
  }
}

struct TodayLogUndoRow: View {
  let undo: TodayLogUndo
  let habitName: String
  let identifier: String
  let actionIdentifier: String
  let action: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      HStack(spacing: AlmanacMetrics.spacingMedium) {
        Text("Logged \(undo.amount.formatted()) \(undo.unit)")
          .almanacTextStyle(.body)
          .fontWeight(.semibold)
          .foregroundStyle(AlmanacPalette.ink)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: AlmanacMetrics.spacingSmall)

        Button("Undo", action: action)
          .buttonStyle(.plain)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(AlmanacPalette.clayDeep)
          .frame(
            minWidth: QuantityLogSheetMetrics.minimumTarget,
            minHeight: QuantityLogSheetMetrics.minimumTarget
          )
          .padding(.horizontal, AlmanacMetrics.spacingSmall)
          .contentShape(Rectangle())
          .accessibilityLabel(
            "Undo \(undo.amount.formatted()) \(undo.unit) for \(habitName)"
          )
          .accessibilityIdentifier(actionIdentifier)
      }

      if let error = undo.error {
        Text(error)
          .almanacTextStyle(.secondary)
          .foregroundStyle(AlmanacPalette.ochreDeep)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("today.undo.error")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      "\(habitName). Logged \(undo.amount.formatted()) \(undo.unit). Undo available."
    )
    .accessibilityIdentifier(identifier)
    .onChange(of: undo.error) { _, error in
      guard let error else { return }
      AccessibilityNotification.Announcement(error).post()
    }
  }
}

private struct LogSheetProgressTrack: View {
  let fraction: Double

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(AlmanacPalette.paperSunken)
        Capsule()
          .fill(AlmanacPalette.moss)
          .frame(width: geometry.size.width * min(max(fraction, 0), 1))
      }
    }
    .frame(height: 8)
  }
}
