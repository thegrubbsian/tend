import Accessibility
import Foundation
import SwiftData
import SwiftUI
import TendCore

struct HabitFormView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Environment(\.timeZone) private var timeZone

    @State private var model: HabitFormModel
    @FocusState private var focusedField: HabitFormField?
    @ScaledMetric(relativeTo: .body) private var splitFieldMinimumWidth: CGFloat = 150

    init(mode: HabitFormMode) {
        _model = State(initialValue: HabitFormModel(mode: mode))
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
                    cadenceSection

                    if let configurationError = model.configurationErrorMessage {
                        configurationErrorSection(configurationError)
                    }
                    targetAndUnitSection

                    if model.showsPinnedWeekdays {
                        pinnedDaysSection
                    }

                    if model.showsReminderControl {
                        reminderSection
                    }

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
        .onChange(of: model.showsUnscheduledReminderWarning) { wasShown, isShown in
            if !wasShown && isShown {
                announce("Reminder warning. No reminder will fire until a day is pinned.")
            }
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
        Text(model.title)
            .font(.system(.title3, design: .serif, weight: .semibold))
            .foregroundStyle(AlmanacPalette.ink)
            .accessibilityAddTraits(.isHeader)
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

            Spacer()

            Button(action: save) {
                Text("Save")
                    .fontWeight(.semibold)
                    .frame(
                        minWidth: AlmanacMetrics.minimumTarget,
                        minHeight: AlmanacMetrics.minimumTarget
                    )
                    .contentShape(Rectangle())
            }
            .foregroundStyle(AlmanacPalette.moss)
            .disabled(!model.canSave)
            .opacity(model.canSave ? 1 : 0.35)
            .accessibilityHint("Saves this habit")
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
            fieldLabel("Name")

            TextField("Morning walk", text: nameBinding, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)
                .focused($focusedField, equals: .name)
                .onSubmit { focusedField = .target }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: AlmanacMetrics.minimumTarget)
                .almanacSunkenSurface()
                .accessibilityLabel("Habit name")
                .accessibilityHint("Required")

            fieldError(for: .name)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var cadenceSection: some View {
        VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
            fieldLabel("Cadence")

            if model.isCadenceLocked {
                HStack(spacing: AlmanacMetrics.spacingSmall) {
                    Text(model.cadenceDisplayName)
                        .almanacTextStyle(.body)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(AlmanacPalette.inkMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: AlmanacMetrics.minimumTarget)
                .almanacSunkenSurface()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Cadence, \(model.cadenceDisplayName), locked")

                Text("Set at creation. To change cadence, archive this habit and plant a new one.")
                    .almanacTextStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(
                        "Cadence locked. Set at creation. To change cadence, archive this habit and plant a new one."
                    )
            } else {
                HStack(spacing: 4) {
                    cadenceChoice(.daily)
                    cadenceChoice(.weekly)
                }
                .padding(4)
                .almanacSunkenSurface(radius: AlmanacMetrics.tabPillRadius)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var targetAndUnitSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AlmanacMetrics.spacingMedium) {
                targetSection
                    .frame(minWidth: splitFieldMinimumWidth, maxWidth: .infinity)
                unitSection
                    .frame(minWidth: splitFieldMinimumWidth, maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
                targetSection
                unitSection
            }
        }
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
            fieldLabel("Target")

            TextField("1", text: targetBinding)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .target)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget, alignment: .leading)
                .almanacSunkenSurface()
                .accessibilityLabel("Target")
                .accessibilityHint("Required positive whole number")

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
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget, alignment: .leading)
                .almanacSunkenSurface()
                .accessibilityLabel("Unit")
                .accessibilityHint("Required, for example times, minutes, or steps")

            fieldError(for: .unit)
        }
        .accessibilityElement(children: .contain)
    }

    private var pinnedDaysSection: some View {
        let labels = HabitFormWeekday.localizedLabels(calendar: calendar, locale: locale)
        let maximumRowWidth =
            AlmanacMetrics.minimumTarget * CGFloat(labels.count)
            + 8 * CGFloat(labels.count - 1)
        return VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
            fieldLabel("Pinned days")

            HStack(spacing: 0) {
                ForEach(labels.indices, id: \.self) { index in
                    let label = labels[index]
                    let isPinned = model.isPinned(label.weekday)
                    Button {
                        model.togglePinnedWeekday(label.weekday)
                    } label: {
                        Text(label.short)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isPinned ? AlmanacPalette.paper : AlmanacPalette.inkMuted)
                            .frame(width: 40, height: 40)
                            .background(
                                isPinned ? AlmanacPalette.clay : AlmanacPalette.paperSunken,
                                in: Circle()
                            )
                            .frame(
                                width: AlmanacMetrics.minimumTarget,
                                height: AlmanacMetrics.minimumTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label.accessibility)
                    .accessibilityValue(isPinned ? "Selected" : "Not selected")
                    .accessibilityAddTraits(isPinned ? .isSelected : [])

                    if index != labels.indices.last {
                        Spacer(minLength: 4)
                    }
                }
            }
            .frame(maxWidth: maximumRowWidth, alignment: .leading)

            Text("Reminders fire on pinned days. Logging any day still counts.")
                .almanacTextStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)

            if model.showsUnscheduledReminderWarning {
                Text("No reminder will fire until a day is pinned.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AlmanacPalette.ochreDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Reminder warning. No reminder will fire until a day is pinned.")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
            fieldLabel("Reminder")

            if model.hasReminder {
                HStack(spacing: AlmanacMetrics.spacingSmall) {
                    DatePicker(
                        "Reminder time",
                        selection: reminderDateBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .frame(minHeight: AlmanacMetrics.minimumTarget)

                    Spacer()

                    Button {
                        model.setReminderEnabled(false)
                    } label: {
                        Text("Clear")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AlmanacPalette.clayDeep)
                            .frame(
                                minWidth: AlmanacMetrics.minimumTarget,
                                minHeight: AlmanacMetrics.minimumTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .accessibilityHint("Removes the reminder time but keeps pinned days")
                }
                .padding(.horizontal, 14)
                .almanacSunkenSurface()
            } else {
                Button {
                    model.setReminderEnabled(true)
                } label: {
                    HStack {
                        Text("None")
                            .foregroundStyle(AlmanacPalette.inkMuted)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AlmanacPalette.inkFaint)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .almanacSunkenSurface()
                .accessibilityLabel("Reminder, none")
                .accessibilityHint("Sets a local reminder time")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func configurationErrorSection(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AlmanacPalette.ochreDeep)
            .fixedSize(horizontal: false, vertical: true)
            .padding(AlmanacMetrics.spacingMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .almanacRaisedSurface()
            .accessibilityLabel("Habit cannot be edited. \(message)")
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
                    .foregroundStyle(AlmanacPalette.moss)
                    .frame(
                        minWidth: AlmanacMetrics.minimumTarget,
                        minHeight: AlmanacMetrics.minimumTarget
                    )
                    .contentShape(Rectangle())
            }
            .accessibilityHint("Retries saving this habit")
            .disabled(!model.canSave)
            .opacity(model.canSave ? 1 : 0.35)
        }
        .padding(AlmanacMetrics.spacingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .almanacRaisedSurface()
        .accessibilityElement(children: .contain)
    }

    private func cadenceChoice(_ cadence: HabitCadence) -> some View {
        let isSelected = model.cadence == cadence
        return Button {
            model.selectCadence(cadence)
        } label: {
            Text(cadence.displayName)
                .font(.body.weight(.semibold))
                .foregroundStyle(isSelected ? AlmanacPalette.mossDeep : AlmanacPalette.inkMuted)
                .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
                .background(isSelected ? AlmanacPalette.paperRaised : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cadence.displayName) cadence")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func fieldLabel(_ value: String) -> some View {
        Text(value)
            .almanacTextStyle(.label)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func fieldError(for field: HabitFormField) -> some View {
        if let error = model.error(for: field) {
            Text(error.message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AlmanacPalette.ochreDeep)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(field.accessibilityName) error. \(error.message)")
        }
    }

    private func announceInitialErrors() {
        var messages: [String] = []
        if let configurationError = model.configurationErrorMessage {
            messages.append("Habit cannot be edited. \(configurationError)")
        }
        for field in [HabitFormField.name, .target, .unit] {
            if let error = model.error(for: field) {
                messages.append("\(field.accessibilityName) error. \(error.message)")
            }
        }
        guard !messages.isEmpty else {
            return
        }
        announce(messages.joined(separator: " "))
    }

    private func save() {
        focusedField = nil
        let persistence = HabitFormPersistence.live(context: modelContext)
        if model.save(using: persistence, at: .now, timeZone: timeZone) != nil {
            dismiss()
        } else if let persistenceError = model.persistenceError {
            announce("Save failed. \(persistenceError)")
        }
    }

    private func announce(
        _ error: HabitFormValidationError?,
        for field: HabitFormField
    ) {
        guard let error else {
            return
        }
        announce("\(field.accessibilityName) error. \(error.message)")
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
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

    private var reminderDateBinding: Binding<Date> {
        Binding(
            get: {
                HabitFormReminderDateAdapter.date(
                    for: model.reminderTime,
                    calendar: calendar,
                    timeZone: timeZone
                )
            },
            set: { value in
                guard let reminderTime = HabitFormReminderDateAdapter.reminderTime(
                    from: value,
                    calendar: calendar,
                    timeZone: timeZone
                ) else {
                    return
                }
                model.reminderTime = reminderTime
            }
        )
    }
}

private extension HabitCadence {
    var displayName: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }
}

private extension HabitFormField {
    var accessibilityName: String {
        switch self {
        case .name: "Name"
        case .target: "Target"
        case .unit: "Unit"
        }
    }
}

private extension HabitFormValidationError {
    var message: String {
        switch self {
        case .emptyName: "Enter a habit name."
        case .invalidTarget: "Enter a whole number greater than zero."
        case .emptyUnit: "Enter a unit."
        }
    }
}
