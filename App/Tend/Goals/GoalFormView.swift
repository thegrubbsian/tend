import Accessibility
import Foundation
import SwiftData
import SwiftUI
import TendCore

private enum GoalFormMetrics {
  static let fieldHorizontalPadding: CGFloat = 14
  static let fieldVerticalPadding: CGFloat = 12
  static let selectorInset = AlmanacMetrics.spacingSmall / 2
}

struct GoalFormView: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.modelContext) private var modelContext
  @Environment(\.timeZone) private var timeZone

  @State private var model: GoalFormModel
  @FocusState private var focusedField: GoalFormField?

  private let now: () -> Date
  private let onSaved: () -> Void

  init(
    mode: GoalFormMode,
    now: @escaping () -> Date = Date.init,
    onSaved: @escaping () -> Void = {}
  ) {
    _model = State(initialValue: GoalFormModel(mode: mode))
    self.now = now
    self.onSaved = onSaved
  }

  var body: some View {
    VStack(spacing: 0) {
      navigationHeader

      Rectangle()
        .fill(AlmanacPalette.hairline)
        .frame(height: 1)
        .padding(.top, AlmanacMetrics.spacingSmall)

      ScrollView {
        VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
          nameSection
          kindSection

          if let configurationError = model.configurationErrorMessage {
            configurationErrorSection(configurationError)
          }

          targetAndUnitSection

          if model.kind == .measure {
            baselineSection
          }

          deadlineSection

          if let persistenceError = model.persistenceError {
            persistenceErrorSection(persistenceError)
          }
        }
        .padding(.top, AlmanacMetrics.spacingLarge)
        .padding(.bottom, AlmanacMetrics.spacingExtraLarge)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("goalForm.sheet")
    .onChange(of: focusedField) { previousField, nextField in
      if let previousField, previousField != nextField {
        model.markInteracted(with: previousField)
      }
    }
    .onChange(of: model.error(for: .name)) { _, error in
      announce(error, for: .name)
    }
    .onChange(of: model.error(for: .target)) { _, error in
      announce(error, for: .target)
    }
    .onChange(of: model.error(for: .unit)) { _, error in
      announce(error, for: .unit)
    }
    .onChange(of: model.error(for: .baseline)) { _, error in
      announce(error, for: .baseline)
    }
    .onAppear(perform: announceInitialErrors)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") {
          if let focusedField {
            model.markInteracted(with: focusedField)
          }
          focusedField = nil
        }
        .accessibilityIdentifier("goalForm.keyboardDone")
      }
    }
  }

  @ViewBuilder
  private var navigationHeader: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(spacing: AlmanacMetrics.spacingSmall) {
        navigationTitle
        navigationActions
      }
    } else {
      ZStack {
        navigationTitle
        navigationActions
      }
    }
  }

  private var navigationTitle: some View {
    Text(title)
      .font(.system(.title3, design: .serif, weight: .semibold))
      .foregroundStyle(AlmanacPalette.ink)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("goalForm.title")
  }

  private var navigationActions: some View {
    HStack {
      Button(action: dismiss.callAsFunction) {
        Text("Cancel")
          .frame(
            minWidth: AlmanacMetrics.minimumTarget,
            minHeight: AlmanacMetrics.minimumTarget
          )
          .contentShape(Rectangle())
      }
      .foregroundStyle(AlmanacPalette.clayDeep)
      .accessibilityHint("Discards changes without saving")
      .accessibilityIdentifier("goalForm.cancel")

      Spacer()

      Button(action: save) {
        Text(model.isSaving ? "Saving…" : "Save")
          .fontWeight(.semibold)
          .frame(
            minWidth: AlmanacMetrics.minimumTarget,
            minHeight: AlmanacMetrics.minimumTarget
          )
          .contentShape(Rectangle())
      }
      .foregroundStyle(isSaveDisabled ? AlmanacPalette.inkMuted : AlmanacPalette.moss)
      .disabled(isSaveDisabled)
      .accessibilityLabel(model.isSaving ? "Saving goal" : "Save goal")
      .accessibilityHint(saveAccessibilityHint)
      .accessibilityIdentifier("goalForm.save")
    }
  }

  private var nameSection: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      fieldLabel("Name")

      TextField("Read every day", text: nameBinding, axis: .vertical)
        .lineLimit(1...3)
        .textInputAutocapitalization(.sentences)
        .submitLabel(.next)
        .focused($focusedField, equals: .name)
        .onSubmit { focusedField = .target }
        .padding(.horizontal, GoalFormMetrics.fieldHorizontalPadding)
        .padding(.vertical, GoalFormMetrics.fieldVerticalPadding)
        .frame(minHeight: AlmanacMetrics.minimumTarget)
        .almanacSunkenSurface()
        .accessibilityLabel("Goal name")
        .accessibilityHint("Required")
        .accessibilityIdentifier("goalForm.name")

      fieldError(for: .name)
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var kindSection: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      fieldLabel("Kind")

      if model.isKindLocked {
        HStack(spacing: AlmanacMetrics.spacingSmall) {
          Text(model.kind.displayName)
            .almanacTextStyle(.body)
          Spacer()
          Image(systemName: "lock.fill")
            .font(.footnote.weight(.semibold))
            .accessibilityHidden(true)
        }
        .foregroundStyle(AlmanacPalette.inkMuted)
        .padding(.horizontal, GoalFormMetrics.fieldHorizontalPadding)
        .padding(.vertical, GoalFormMetrics.fieldVerticalPadding)
        .frame(minHeight: AlmanacMetrics.minimumTarget)
        .almanacSunkenSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kind, \(model.kind.displayName), locked")
        .accessibilityIdentifier("goalForm.kind.locked")

        Text("Changing kind requires a new goal.")
          .almanacTextStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("goalForm.kind.explanation")
      } else {
        kindChoices
      }
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var kindChoices: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: GoalFormMetrics.selectorInset) {
          kindChoice(.accumulate)
          kindChoice(.measure)
        }
      } else {
        HStack(spacing: GoalFormMetrics.selectorInset) {
          kindChoice(.accumulate)
          kindChoice(.measure)
        }
      }
    }
    .padding(GoalFormMetrics.selectorInset)
    .almanacSunkenSurface(
      radius: dynamicTypeSize.isAccessibilitySize
        ? AlmanacMetrics.insetRadius
        : AlmanacMetrics.tabPillRadius
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Goal kind")
    .accessibilityIdentifier("goalForm.kind")
  }

  @ViewBuilder
  private var targetAndUnitSection: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
        targetSection
        unitSection
      }
    } else {
      HStack(alignment: .top, spacing: AlmanacMetrics.spacingMedium) {
        targetSection
          .frame(maxWidth: .infinity)
        unitSection
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var targetSection: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      fieldLabel("Target")

      TextField("1", text: targetBinding)
        .keyboardType(.numberPad)
        .focused($focusedField, equals: .target)
        .padding(.horizontal, GoalFormMetrics.fieldHorizontalPadding)
        .padding(.vertical, GoalFormMetrics.fieldVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget, alignment: .leading)
        .almanacSunkenSurface()
        .accessibilityLabel("Target")
        .accessibilityHint("Required positive whole number")
        .accessibilityIdentifier("goalForm.target")

      fieldError(for: .target)
    }
    .accessibilityElement(children: .contain)
  }

  private var unitSection: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      fieldLabel("Unit")

      TextField("times", text: unitBinding, axis: .vertical)
        .lineLimit(1...3)
        .textInputAutocapitalization(.never)
        .focused($focusedField, equals: .unit)
        .submitLabel(model.kind == .measure ? .next : .done)
        .onSubmit {
          focusedField = model.kind == .measure ? .baseline : nil
        }
        .padding(.horizontal, GoalFormMetrics.fieldHorizontalPadding)
        .padding(.vertical, GoalFormMetrics.fieldVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget, alignment: .leading)
        .almanacSunkenSurface()
        .accessibilityLabel("Unit")
        .accessibilityHint("Required, for example times, pages, or dollars")
        .accessibilityIdentifier("goalForm.unit")

      fieldError(for: .unit)
    }
    .accessibilityElement(children: .contain)
  }

  private var baselineSection: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      fieldLabel("Baseline")

      TextField("0", text: baselineBinding)
        .keyboardType(.numbersAndPunctuation)
        .focused($focusedField, equals: .baseline)
        .submitLabel(.done)
        .onSubmit { focusedField = nil }
        .padding(.horizontal, GoalFormMetrics.fieldHorizontalPadding)
        .padding(.vertical, GoalFormMetrics.fieldVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget, alignment: .leading)
        .almanacSunkenSurface()
        .accessibilityLabel("Baseline")
        .accessibilityHint("Required signed whole number. Negative values are allowed")
        .accessibilityIdentifier("goalForm.baseline")

      Text("The starting reading for this measure goal.")
        .almanacTextStyle(.caption)
        .fixedSize(horizontal: false, vertical: true)

      fieldError(for: .baseline)
    }
    .accessibilityElement(children: .contain)
  }

  private var deadlineSection: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      fieldLabel("Deadline")

      if model.deadline == nil {
        Button(action: addDeadline) {
          HStack(spacing: AlmanacMetrics.spacingSmall) {
            Text("None")
              .foregroundStyle(AlmanacPalette.ink)
            Spacer()
            Text("Add")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(AlmanacPalette.clayDeep)
          }
          .padding(.horizontal, GoalFormMetrics.fieldHorizontalPadding)
          .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .almanacSunkenSurface()
        .accessibilityLabel("Deadline, none")
        .accessibilityHint("Adds an optional calendar day")
        .accessibilityIdentifier("goalForm.deadline.add")
      } else {
        deadlineEditor
      }

      Text("Optional. The deadline is a calendar day, not a time.")
        .almanacTextStyle(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("goalForm.deadline.explanation")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("goalForm.deadline")
  }

  @ViewBuilder
  private var deadlineEditor: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
        DatePicker(
          "Deadline date",
          selection: deadlineDateBinding,
          displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
        .accessibilityHint("Selects the goal's optional calendar deadline")
        .accessibilityIdentifier("goalForm.deadline.picker")

        removeDeadlineButton
      }
      .padding(.horizontal, GoalFormMetrics.fieldHorizontalPadding)
      .padding(.vertical, GoalFormMetrics.fieldVerticalPadding)
      .almanacSunkenSurface()
    } else {
      HStack(spacing: AlmanacMetrics.spacingSmall) {
        DatePicker(
          "Deadline date",
          selection: deadlineDateBinding,
          displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .labelsHidden()
        .frame(minHeight: AlmanacMetrics.minimumTarget)
        .accessibilityLabel("Deadline date")
        .accessibilityHint("Selects the goal's optional calendar deadline")
        .accessibilityIdentifier("goalForm.deadline.picker")

        Spacer(minLength: 0)

        removeDeadlineButton
      }
      .padding(.horizontal, GoalFormMetrics.fieldHorizontalPadding)
      .almanacSunkenSurface()
    }
  }

  private var removeDeadlineButton: some View {
    Button(action: removeDeadline) {
      Text("Remove")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AlmanacPalette.clayDeep)
        .frame(
          minWidth: AlmanacMetrics.minimumTarget,
          minHeight: AlmanacMetrics.minimumTarget
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Remove deadline")
    .accessibilityHint("Returns the deadline to none")
    .accessibilityIdentifier("goalForm.deadline.remove")
  }

  private func configurationErrorSection(_ message: String) -> some View {
    Text(message)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(AlmanacPalette.ochreDeep)
      .fixedSize(horizontal: false, vertical: true)
      .padding(AlmanacMetrics.spacingMedium)
      .frame(maxWidth: .infinity, alignment: .leading)
      .almanacRaisedSurface()
      .accessibilityLabel("Goal cannot be edited. \(message)")
      .accessibilityIdentifier("goalForm.configurationError")
  }

  private func persistenceErrorSection(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text(message)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AlmanacPalette.ochreDeep)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Save failed. \(message)")

      Button(action: save) {
        Text("Try again")
          .font(.body.weight(.semibold))
          .foregroundStyle(isSaveDisabled ? AlmanacPalette.inkMuted : AlmanacPalette.moss)
          .frame(
            minWidth: AlmanacMetrics.minimumTarget,
            minHeight: AlmanacMetrics.minimumTarget
          )
          .contentShape(Rectangle())
      }
      .disabled(isSaveDisabled)
      .accessibilityHint("Retries saving this goal")
      .accessibilityIdentifier("goalForm.retry")
    }
    .padding(AlmanacMetrics.spacingMedium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .almanacRaisedSurface()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("goalForm.persistenceError")
  }

  private func kindChoice(_ kind: GoalKind) -> some View {
    let isSelected = model.kind == kind
    return Button {
      model.selectKind(kind)
    } label: {
      Text(kind.displayName)
        .font(.body.weight(.semibold))
        .foregroundStyle(isSelected ? AlmanacPalette.mossDeep : AlmanacPalette.inkMuted)
        .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
        .padding(.horizontal, AlmanacMetrics.spacingSmall)
        .background(isSelected ? AlmanacPalette.paperRaised : .clear, in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(kind.displayName) goal")
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier("goalForm.kind.\(kind.rawValue)")
  }

  private func fieldLabel(_ value: String) -> some View {
    Text(value)
      .almanacTextStyle(.label)
      .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder
  private func fieldError(for field: GoalFormField) -> some View {
    if let error = model.error(for: field) {
      Text(error.message)
        .font(.caption.weight(.semibold))
        .foregroundStyle(AlmanacPalette.ochreDeep)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("\(field.accessibilityName) error. \(error.message)")
        .accessibilityIdentifier("goalForm.\(field.identifierComponent).error")
    }
  }

  private func save() {
    focusedField = nil
    let persistence = GoalFormPersistence.live(context: modelContext)
    if model.save(
      using: persistence,
      at: now(),
      calendar: calendar,
      timeZone: timeZone
    ) != nil {
      onSaved()
      dismiss()
      return
    }

    focusedField = model.focusedField
    if let persistenceError = model.persistenceError {
      announce("Save failed. \(persistenceError)")
    }
  }

  private func addDeadline() {
    guard
      let deadline = GoalFormDeadlineAdapter.goalDate(
        from: now(),
        calendar: calendar,
        timeZone: timeZone
      )
    else {
      return
    }
    model.deadline = deadline
    announce("Deadline added.")
  }

  private func removeDeadline() {
    model.deadline = nil
    announce("Deadline removed.")
  }

  private func announceInitialErrors() {
    var messages: [String] = []
    if let configurationError = model.configurationErrorMessage {
      messages.append("Goal cannot be edited. \(configurationError)")
    }
    for field in [GoalFormField.name, .target, .unit, .baseline] {
      if let error = model.error(for: field) {
        messages.append("\(field.accessibilityName) error. \(error.message)")
      }
    }
    guard !messages.isEmpty else {
      return
    }
    announce(messages.joined(separator: " "))
  }

  private func announce(
    _ error: GoalFormValidationError?,
    for field: GoalFormField
  ) {
    guard let error else {
      return
    }
    announce("\(field.accessibilityName) error. \(error.message)")
  }

  private func announce(_ message: String) {
    AccessibilityNotification.Announcement(message).post()
  }

  private var title: String {
    switch model.mode {
    case .new: "New goal"
    case .edit: "Edit goal"
    }
  }

  private var saveAccessibilityHint: String {
    switch model.mode {
    case .new: "Creates this goal"
    case .edit: "Saves changes to this goal"
    }
  }

  private var isSaveDisabled: Bool {
    !model.canSave || model.isSaving
  }

  private var nameBinding: Binding<String> {
    Binding(
      get: { model.name },
      set: {
        model.name = $0
        model.markInteracted(with: .name)
      }
    )
  }

  private var targetBinding: Binding<String> {
    Binding(
      get: { model.targetText },
      set: {
        model.targetText = $0
        model.markInteracted(with: .target)
      }
    )
  }

  private var unitBinding: Binding<String> {
    Binding(
      get: { model.unit },
      set: {
        model.unit = $0
        model.markInteracted(with: .unit)
      }
    )
  }

  private var baselineBinding: Binding<String> {
    Binding(
      get: { model.baselineText },
      set: {
        model.baselineText = $0
        model.markInteracted(with: .baseline)
      }
    )
  }

  private var deadlineDateBinding: Binding<Date> {
    Binding(
      get: {
        guard let deadline = model.deadline else {
          return now()
        }
        return GoalFormDeadlineAdapter.date(
          for: deadline,
          calendar: calendar,
          timeZone: timeZone
        )
      },
      set: { date in
        guard
          let deadline = GoalFormDeadlineAdapter.goalDate(
            from: date,
            calendar: calendar,
            timeZone: timeZone
          )
        else {
          return
        }
        model.deadline = deadline
      }
    )
  }
}

extension GoalKind {
  fileprivate var displayName: String {
    switch self {
    case .accumulate: "Accumulate"
    case .measure: "Measure"
    }
  }
}

extension GoalFormField {
  fileprivate var accessibilityName: String {
    switch self {
    case .name: "Name"
    case .target: "Target"
    case .unit: "Unit"
    case .baseline: "Baseline"
    }
  }

  fileprivate var identifierComponent: String {
    switch self {
    case .name: "name"
    case .target: "target"
    case .unit: "unit"
    case .baseline: "baseline"
    }
  }
}

extension GoalFormValidationError {
  fileprivate var message: String {
    switch self {
    case .emptyName: "Enter a goal name."
    case .invalidTarget: "Enter a whole number greater than zero."
    case .emptyUnit: "Enter a unit."
    case .missingBaseline: "Enter a baseline."
    case .invalidBaseline: "Enter a signed whole number."
    }
  }
}
