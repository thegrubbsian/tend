import Foundation
import Observation
import SwiftData
import TendCore

enum GoalFormMode {
  case new
  case edit(Goal)
}

enum GoalFormField: Hashable {
  case name
  case target
  case unit
  case baseline
}

enum GoalFormValidationError: Error, Equatable {
  case emptyName
  case invalidTarget
  case emptyUnit
  case missingBaseline
  case invalidBaseline

  fileprivate var field: GoalFormField {
    switch self {
    case .emptyName:
      .name
    case .invalidTarget:
      .target
    case .emptyUnit:
      .unit
    case .missingBaseline, .invalidBaseline:
      .baseline
    }
  }
}

private enum GoalFormConfigurationError: CaseIterable, Hashable {
  case unsupportedKind
  case invalidDeadline

  var message: String {
    switch self {
    case .unsupportedKind:
      "This goal has an unsupported stored kind and can’t be edited."
    case .invalidDeadline:
      "This goal has an invalid stored deadline and can’t be edited."
    }
  }
}

@MainActor
struct GoalFormPersistence {
  typealias Create = (
    _ fields: GoalCreationFields,
    _ instant: Date,
    _ timeZone: TimeZone
  ) throws -> Goal
  typealias Update = (
    _ goal: Goal,
    _ fields: GoalEditableFields,
    _ calendar: Calendar,
    _ timeZone: TimeZone
  ) throws -> Void

  let create: Create
  let update: Update

  static func live(context: ModelContext) -> Self {
    let creationOperations = GoalCreationOperations(context: context)
    let managementOperations = GoalManagementOperations(context: context)
    return Self(
      create: { fields, instant, timeZone in
        try creationOperations.create(
          fields: fields,
          at: instant,
          timeZone: timeZone
        )
      },
      update: { goal, fields, calendar, timeZone in
        try managementOperations.update(
          goal,
          fields: fields,
          calendar: calendar,
          timeZone: timeZone
        )
      }
    )
  }
}

enum GoalFormDeadlineAdapter {
  static func goalDate(
    from date: Date,
    calendar _: Calendar,
    timeZone: TimeZone
  ) -> GoalDate? {
    var gregorianCalendar = Calendar(identifier: .gregorian)
    gregorianCalendar.timeZone = timeZone
    let components = gregorianCalendar.dateComponents([.year, .month, .day], from: date)
    guard
      let year = components.year,
      let month = components.month,
      let day = components.day
    else {
      return nil
    }
    return GoalDate(year: year, month: month, day: day)
  }

  static func date(
    for goalDate: GoalDate,
    calendar _: Calendar,
    timeZone: TimeZone
  ) -> Date {
    var gregorianCalendar = Calendar(identifier: .gregorian)
    gregorianCalendar.timeZone = timeZone
    let components = DateComponents(
      year: goalDate.year,
      month: goalDate.month,
      day: goalDate.day,
      hour: 12
    )
    guard let date = gregorianCalendar.date(from: components) else {
      preconditionFailure("The Gregorian calendar cannot represent this goal date.")
    }
    return date
  }
}

@MainActor
@Observable
final class GoalFormModel {
  let mode: GoalFormMode

  var name = ""
  private(set) var kind: GoalKind = .accumulate
  var targetText = "1"
  var unit = "times"
  var baselineText = ""
  var deadline: GoalDate?
  private(set) var isSaving = false
  private(set) var focusedField: GoalFormField?
  private(set) var persistenceError: String?

  private var interactedFields: Set<GoalFormField> = []
  private var configurationErrors: Set<GoalFormConfigurationError> = []

  init(mode: GoalFormMode) {
    self.mode = mode

    guard case .edit(let goal) = mode else {
      return
    }

    name = goal.name
    if let storedKind = GoalKind(rawValue: goal.kindRawValue) {
      kind = storedKind
    } else {
      configurationErrors.insert(.unsupportedKind)
    }
    targetText = String(goal.target)
    unit = goal.unit
    baselineText = goal.baseline.map(String.init) ?? ""
    if let deadlineKey = goal.deadlineKey {
      if let storedDeadline = GoalDate(rawValue: deadlineKey) {
        deadline = storedDeadline
      } else {
        configurationErrors.insert(.invalidDeadline)
      }
    }
    interactedFields.formUnion([.name, .target, .unit, .baseline])
  }

  var isKindLocked: Bool {
    if case .edit = mode {
      true
    } else {
      false
    }
  }

  var configurationErrorMessage: String? {
    let messages = GoalFormConfigurationError.allCases
      .filter(configurationErrors.contains)
      .map(\.message)
    return messages.isEmpty ? nil : messages.joined(separator: " ")
  }

  var canSave: Bool {
    configurationErrors.isEmpty && !isSaving && firstValidationError() == nil
  }

  func markInteracted(with field: GoalFormField) {
    interactedFields.insert(field)
  }

  func error(for field: GoalFormField) -> GoalFormValidationError? {
    guard interactedFields.contains(field) else {
      return nil
    }
    return validationError(for: field)
  }

  func selectKind(_ selectedKind: GoalKind) {
    guard case .new = mode else {
      return
    }
    kind = selectedKind
    if selectedKind == .accumulate {
      baselineText = ""
    }
  }

  func save(
    using persistence: GoalFormPersistence,
    at instant: Date,
    calendar: Calendar,
    timeZone: TimeZone
  ) -> Goal? {
    guard !isSaving else {
      return nil
    }

    guard configurationErrors.isEmpty else {
      return nil
    }

    interactedFields.formUnion([.name, .target, .unit, .baseline])
    persistenceError = nil

    let draft: ValidatedDraft
    do {
      draft = try validatedDraft()
    } catch let error as GoalFormValidationError {
      focusedField = error.field
      return nil
    } catch {
      return nil
    }

    focusedField = nil
    isSaving = true
    defer { isSaving = false }

    do {
      switch mode {
      case .new:
        return try persistence.create(
          GoalCreationFields(
            name: draft.name,
            kind: kind,
            target: draft.target,
            unit: draft.unit,
            baseline: draft.baseline,
            deadline: deadline
          ),
          instant,
          timeZone
        )
      case .edit(let goal):
        try persistence.update(
          goal,
          GoalEditableFields(
            name: draft.name,
            target: draft.target,
            unit: draft.unit,
            baseline: draft.baseline,
            deadline: deadline
          ),
          calendar,
          timeZone
        )
        return goal
      }
    } catch {
      persistenceError = persistenceMessage(for: error)
      return nil
    }
  }

  private func firstValidationError() -> GoalFormValidationError? {
    validationError(for: .name)
      ?? validationError(for: .target)
      ?? validationError(for: .unit)
      ?? validationError(for: .baseline)
  }

  private func validationError(for field: GoalFormField) -> GoalFormValidationError? {
    switch field {
    case .name:
      return normalized(name).isEmpty ? GoalFormValidationError.emptyName : nil
    case .target:
      return parseTarget(targetText) == nil ? GoalFormValidationError.invalidTarget : nil
    case .unit:
      return normalized(unit).isEmpty ? GoalFormValidationError.emptyUnit : nil
    case .baseline:
      guard kind == .measure else {
        return nil
      }
      if baselineText.isEmpty {
        return .missingBaseline
      }
      return parseBaseline(baselineText) == nil ? .invalidBaseline : nil
    }
  }

  private func validatedDraft() throws -> ValidatedDraft {
    let name = normalized(name)
    guard !name.isEmpty else {
      throw GoalFormValidationError.emptyName
    }
    guard let target = parseTarget(targetText) else {
      throw GoalFormValidationError.invalidTarget
    }
    let unit = normalized(unit)
    guard !unit.isEmpty else {
      throw GoalFormValidationError.emptyUnit
    }

    let baseline: Int?
    switch kind {
    case .accumulate:
      baseline = nil
    case .measure:
      guard !baselineText.isEmpty else {
        throw GoalFormValidationError.missingBaseline
      }
      guard let parsedBaseline = parseBaseline(baselineText) else {
        throw GoalFormValidationError.invalidBaseline
      }
      baseline = parsedBaseline
    }

    return ValidatedDraft(
      name: name,
      target: target,
      unit: unit,
      baseline: baseline
    )
  }

  private func parseTarget(_ text: String) -> Int? {
    guard isDecimalInteger(text, allowsSign: false), let target = Int(text), target > 0 else {
      return nil
    }
    return target
  }

  private func parseBaseline(_ text: String) -> Int? {
    guard isDecimalInteger(text, allowsSign: true) else {
      return nil
    }
    return Int(text)
  }

  private func isDecimalInteger(_ text: String, allowsSign: Bool) -> Bool {
    let bytes = text.utf8
    guard !bytes.isEmpty else {
      return false
    }

    var index = bytes.startIndex
    if allowsSign, bytes[index] == 43 || bytes[index] == 45 {
      bytes.formIndex(after: &index)
      guard index != bytes.endIndex else {
        return false
      }
    }

    while index != bytes.endIndex {
      guard (48...57).contains(bytes[index]) else {
        return false
      }
      bytes.formIndex(after: &index)
    }
    return true
  }

  private func persistenceMessage(for error: Error) -> String {
    if let localizedError = error as? LocalizedError,
      let description = localizedError.errorDescription,
      !description.isEmpty
    {
      return description
    }
    return "We couldn’t save this goal. Your changes are still here."
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private struct ValidatedDraft {
  let name: String
  let target: Int
  let unit: String
  let baseline: Int?
}
