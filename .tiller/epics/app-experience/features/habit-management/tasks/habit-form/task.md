# Build the Almanac New and Edit habit form

## Approach

Build one reusable sheet form on
app-experience/habit-management/habit-management-operations (T-w74oy2).
Separate owner-editable draft state and validation from SwiftUI layout so app
unit tests can exercise behavior without querying view hierarchy.

Define a main-actor observable form model with explicit New and Edit modes. New
initializes name empty, cadence Daily, target text `1`, unit `times`, no pinned
days, and no reminder. Edit copies the persisted values once, retains the Habit
identity for Save, and exposes cadence as read-only. The draft never binds
directly to `Habit` properties.

The form model must:

- normalize through the TendCore operation rather than maintaining a competing
  normalization rule;
- report whether name, target text, and unit are valid enough to enable Save;
- parse only a positive base-10 integer target without accepting fractions,
  signs without digits, overflow, or locale grouping punctuation as stored
  value;
- show pinned-day state only in Weekly New mode or for a persisted Weekly habit;
- clear selected pinned days when a New draft switches Weekly to Daily and not
  resurrect them if switched back;
- retain reminder time across cadence changes;
- expose the no-pinned-day reminder warning without making a valid Weekly draft
  unsaveable;
- call create or update exactly once per Save attempt with injected instant and
  time zone; and
- preserve every draft value plus an announced retryable error if the operation
  throws.

Implement `HabitFormView` as a scrollable Almanac sheet, not a native `Form`.
Match the Edit Habit board and feature contract: Cancel/New or Edit habit/Save
navigation row; tracked uppercase labels; sunken rounded fields; responsive
Target/Unit row; Daily/Weekly creation choice; locked cadence in Edit with lock
glyph and exact explainer; seven 40-point day circles with 44-point interaction
regions; pinned-day note; and an optional local-time control with a clear/None
path.

Use semantic `TextField`, numeric keyboard, buttons, and `DatePicker` behavior
where it provides the required accessibility without leaking native list
chrome. Localize full weekday accessibility labels through the owner's calendar
while keeping the comp's single-letter visual labels. Selected chips expose
`.isSelected`.

Save remains disabled until the draft is valid. After a field has been
interacted with, expose concise inline guidance and an accessibility
announcement for invalid name, target, or unit. Show the Weekly reminder warning
in ochre-deep. Save success calls an injected completion so the presenting
surface dismisses; Cancel calls dismissal with no operation.

Do not install the form into Today or Habits yet; the roster and integration
tasks own presentation. Do not request notification permission, schedule or
cancel reminders, change a Habit directly, reconcile buckets in the app target,
add haptics, or introduce a coordinator/repository.

## Surfaces

- Create app-target form sources under `App/Tend/Habits/`, including the form
  model, `HabitFormView`, and only the small reusable field/day components the
  layout earns.
- Create `App/TendTests/HabitFormModelTests.swift`.
- Reuse `AlmanacPalette`, `AlmanacTypography`, `AlmanacMetrics`, surface styles,
  and `AlmanacIcon`; add no parallel design tokens.
- Modify the Xcode project only if filesystem-synchronized groups do not include
  the new files automatically.
- Do not modify TendCore beyond fixing a proven defect in T-w74oy2, the shell
  destination views, the Pencil comp, persistence schema, or notification code.

## Tests

Write failing app-unit tests before implementing the model. Use a real in-memory
TendCore container and real `HabitManagementOperations` for successful
create/update paths. A narrow injected throwing closure is allowed only to prove
draft preservation and retry behavior.

Cover:

- exact New defaults and initially disabled Save;
- whitespace name/unit, target zero/negative/fraction/overflow, and the first
  valid boundary;
- Daily/Weekly switching, pin clearing, reminder retention, and warning
  visibility;
- Monday-through-Sunday bit mapping and accessible weekday labels under a
  non-English locale/calendar;
- Edit copying all values once, locking cadence, and leaving the persisted Habit
  unchanged while fields change or Cancel is selected;
- exact create versus update dispatch with injected instant/time zone;
- one Save call, success completion, and no duplicate write from repeated view
  rendering;
- failure preserving every field and enabling a retry that can succeed; and
- `ReminderTime` conversion at 00:00 and 23:59 without date/time-zone drift.

Run:

- `Scripts/tiller-xcode-test TendTests/HabitFormModelTests`
- `Scripts/tiller-swift-test
  Tests/TendCoreTests/Management/HabitManagementOperationsTests.swift`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination
  'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

The task's smoke test presents New and Edit modes from a local development host
or deterministic preview with no sample persistence, enters fields with the
software keyboard, saves to an in-memory development container, and observes
the resulting Habit. Final comp/device acceptance remains in T-94vmmx.

## Edge cases

- An Edit draft for invalid imported cadence/value data shows an honest error
  and cannot Save; it never guesses a replacement.
- A New draft switched away from Weekly clears pins even if the day controls are
  offscreen.
- No pinned days is valid; warning depends on a reminder being present.
- Clearing a reminder removes only the reminder, not pinned days.
- Cancel after a failed Save still performs no additional write.
- Owner text and inline guidance wrap at larger Dynamic Type sizes; Target/Unit
  stacks before either truncates.
- The keyboard cannot cover the focused field or Save/error recovery path.
