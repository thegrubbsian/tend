# Build the truthful All Habits roster

## Approach

Build the persistent roster and management actions on
app-experience/habit-management/habit-management-operations (T-w74oy2) and
app-experience/habit-management/habit-form (T-me8qsx). Replace only the empty
body of `HabitsDestinationChrome`; retain the shell's destination identity,
paper background, readable width, floating pill, and selection ownership.

Query every `Habit` from the injected production `ModelContext`. Keep a
main-actor roster model responsible for deterministic partitioning, formatting,
streak-state loading, mutation dispatch, and retryable errors; keep SwiftUI
responsible for rendering and presentation. Do not copy Habit records into a
second store.

For each refresh, compute current/frozen streaks with the real
`HabitStreakComputation` at an injected instant and time zone. Preserve every
row when one computation fails, mark only that streak unavailable, and expose a
retry. Never use `bestStreak`, cached UI state, or zero as a substitute for an
unknown current streak. Refresh after create/edit/archive/reactivate/delete and
from `LocalDayTimelineSchedule` at calendar-local midnight.

Partition by `isActive` exactly once, active first. Sort within each section by
localized owner-visible name, then `createdAt`, then UUID. Format locale-aware
requirements and cadence; singularize only the built-in target `1`/unit `times`
pair to `1 time`. Format current streak as N day(s)/week(s) and inactive streak
as `held at N day(s)/week(s)`. Include localized pinned-day abbreviations for
Weekly habits when present.

Implement the All Habits board:

- New York `Habits` title and a filled moss plus button, visually 40 points with
  a 44-point target, “New habit” label, and stable identifier;
- tracked ACTIVE/INACTIVE section labels only when their section is nonempty;
- raised active rows with hairline, name/requirement at leading, and status
  streak at trailing;
- sunken inactive rows with muted name, dormant metadata, and faint held streak;
- no shadows, progress controls, placeholder detail, native List background, or
  sample rows.

Present `HabitFormView` in New mode from add and Edit mode from a row action.
Expose Edit, Archive/Reactivate, and Delete as trailing swipe actions. Mirror
them in the row context menu and VoiceOver custom actions so swipe is never the
only route.

Use `HabitActivityOperations` for Archive and Reactivate. Inject the current
instant/time zone at action time, disable only the in-flight action against
double dispatch, and move sections only after success. A failure keeps the row
in its truthful section and presents a retryable inline/accessible error; never
optimistically flip `isActive`.

Delete first presents a custom Almanac confirmation surface. For an active
habit, name the habit and permanent loss, then offer Cancel, Archive as the
reversible primary alternative, and a withered Delete action. For an inactive
habit, state that it is already archived and offer Cancel/Delete. Only confirmed
Delete calls `HabitManagementOperations.delete`; cancel and Archive never call
delete. Keep failure recoverable with the model intact.

Rows are not navigation links in this task. Habit Detail and History owns their
eventual destination. Do not add an interim screen, router, disabled chevron, or
empty navigation destination.

## Surfaces

- Create roster/model/row/action/confirmation sources under
  `App/Tend/Habits/`.
- Modify `App/Tend/Shell/HabitsDestinationChrome.swift` to host the roster body
  while retaining its root accessibility identifier.
- Create `App/TendTests/HabitRosterModelTests.swift`.
- Reuse the existing Habit form, lifecycle/streak operations, Almanac APIs, and
  local-day schedule; do not duplicate any of them.
- Do not modify `AlmanacShellView`, `FloatingTabPill`, Today content, TendCore
  semantics, persistence schema, Pencil comp, or notification code except to
  fix a directly proven prerequisite defect.

## Tests

Write failing app-unit tests against real in-memory model containers and the
real TendCore operation graph. Test projection and operation outcomes, not Swift
source or incidental hierarchy.

Cover:

- zero, active-only, inactive-only, and mixed partitioning with every Habit
  appearing exactly once;
- localized case-insensitive name order plus creation-time/UUID ties;
- target/unit/cadence/pinned-day and streak singular/plural formatting;
- truthful active, at-risk, inactive-held, and per-row unavailable states;
- local-midnight refresh advancing the injected instant and recomputing rather
  than reusing stale state;
- create/edit completion refresh;
- exact Archive/Reactivate dispatch and current-bucket lifecycle effects;
- prevention of duplicate lifecycle dispatch while an action is active;
- active/inactive deletion confirmation content, Cancel, Archive alternative,
  confirmed cascade deletion, final-row removal, and failure retry;
- all row actions being represented in accessibility metadata independent of
  swipe discovery; and
- a computation/mutation failure preserving the row and truthful section.

Run:

- `Scripts/tiller-xcode-test TendTests/HabitRosterModelTests`
- `Scripts/tiller-xcode-test TendTests/HabitFormModelTests`
- `Scripts/tiller-swift-test`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination
  'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Smoke test with a real in-memory development container: create one Daily and one
Weekly habit through the form, observe both active rows, archive/reactivate one,
cancel then confirm deletion, and observe persisted model/query changes without
relaunch. Final compact/iPad and assistive-technology acceptance remains in
T-94vmmx.

## Edge cases

- A zero streak is shown as `0 days` or `0 weeks`, never hidden.
- At-risk text uses ochre-deep at roster size; inactive text remains faint and
  never implies a miss.
- Long names and units wrap without displacing the trailing streak offscreen.
- Equal localized names remain stable across refreshes.
- The midnight schedule follows calendar days through DST and time-zone changes.
- An operation failure does not dismiss its sheet or confirmation, reorder a
  row, or claim success.
- Delete while active does not silently deactivate first.
- Empty sections disappear; the add control remains when the roster is empty.
