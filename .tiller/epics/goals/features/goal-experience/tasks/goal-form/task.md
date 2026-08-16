# Build the validated New and Edit goal form

## Approach

Build the reusable goal form on goals/goal-lifecycle (F-5aficd), using the
public create and update operations from that feature rather than mutating
SwiftData models in SwiftUI. Start with `GoalFormModelTests` and make the draft,
validation, save, and failure contracts fail before building the sheet.

Add a main-actor observable form model with explicit New and Edit modes. New
owns string drafts for name, target, unit, and measure baseline; an optional
deadline; and a kind choice initialized to Accumulate. Edit copies the
persisted values once, retains the goal identity for Save, and exposes kind as
read-only. Keep string drafts intact while the owner types so incomplete or
invalid input is not coerced into fake values.

Validation must:

- trim name and unit and reject either when empty;
- parse target as an integer greater than zero;
- require and parse an integer baseline only for a measure goal;
- ignore and clear a stale baseline when a New draft switches back to
  Accumulate;
- preserve an optional calendar deadline without inventing a time-of-day
  promise;
- focus the first invalid field and expose one local error beside it.

Inject create and update closures plus the current instant and calendar needed
by the domain operation. Save exactly once after the complete draft validates.
Keep the persisted model untouched until the operation succeeds, dismiss only
after success, and retain the entire draft plus the diagnostic failure on
error. Cancel performs no write.

Build one scrollable `GoalFormView` sheet. Match the existing habit form's
Almanac navigation row, labels, sunken fields, spacing, keyboard handling,
validation summary, and adaptive field stacking without copying its large view
or introducing a generic form framework. Use a kind choice only in New mode.
In Edit, show the stored kind and an adjacent explanation that changing kind
requires a new goal. Show Baseline only when the draft kind is Measure. Add an
explicit optional-deadline control with a local-calendar date picker and a way
to remove the deadline.

This task ends with a reusable form and unit-tested model. It does not add the
Goals shell destination, build the roster, present Goal Detail, or create UI
fixtures.

## Surfaces

- Create `App/Tend/Goals/GoalFormModel.swift`.
- Create `App/Tend/Goals/GoalFormView.swift`.
- Create `App/TendTests/GoalFormModelTests.swift`.
- Modify the Xcode project only if the synchronized filesystem groups do not
  discover the new files.
- Do not modify TendCore goal rules, existing habit forms, shell navigation,
  Today, reminders, or Pencil comps.

## Tests

Write `GoalFormModelTests` against injected persistence closures. Cover New
defaults; accumulate and measure payloads; whitespace normalization; empty
name and unit; zero, negative, fractional, overflowing, and malformed target;
missing and signed measure baseline; kind switching; optional deadline add and
remove; immutable Edit kind; untouched persisted state before Save and on
Cancel; one successful create or update; focus of the first invalid field; and
draft retention after a thrown save.

Run:

- `Scripts/tiller-xcode-test TendTests/GoalFormModelTests`
- `Scripts/tiller-xcode-test TendTests/HabitFormModelTests`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination
  'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Manually exercise the sheet at compact width with the keyboard visible and at
two larger Dynamic Type steps. Verify every field, kind choice, date control,
Cancel, and Save has a meaningful VoiceOver label and at least a 44-point hit
target.

## Edge cases

- Switching a New draft Measure → Accumulate → Measure must not silently
  restore a discarded baseline.
- A decreasing measure goal accepts a baseline above its target; an increasing
  one accepts a baseline below it. Equality is passed to the domain operation
  for its documented validation rather than guessed in the view.
- Signed baseline input is valid; signed or zero target input is not.
- Edit may change the baseline, target, unit, name, or deadline of a closed
  goal, but never its kind.
- A deadline selected near midnight or a daylight-saving transition remains
  the owner's calendar date.
- Save cannot be double-submitted while an operation is in flight.
- Persistence failure leaves the sheet open with no optimistic goal mutation.
