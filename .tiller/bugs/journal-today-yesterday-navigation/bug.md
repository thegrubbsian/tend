# Journal Today/Yesterday navigation ignores taps and can blank the editor

The Journal editor's Today/Yesterday control does not reliably change the
selected day. The failure is deterministic enough to block yesterday back-fill
and can leave the editor surface empty.

Owner report: first observed from a fresh, empty Journal. The root-cause
investigation was completed on 2026-08-27 and recovered from the persisted OMP
session transcript.

## Reproduction

1. Launch with no entry for today or yesterday and open Journal.
2. From the Journal overview, tap **Write today's page**.
3. Confirm that the Today editor opens, Today is selected, and the keyboard is
   visible.
4. Before writing anything, tap **Yesterday** once.
5. Tap **Yesterday** again if the first tap did not change the selected day.

## Expected

- The first tap flushes the current editor and then atomically changes the
  route, visible editor model, selected scope, and date header to Yesterday.
- Selecting the already-active day is an idempotent no-op.
- The editor remains present throughout the transition.
- Any prose entered after the transition is persisted only against the visibly
  selected day.

## Actual

- The first tap commonly dismisses the keyboard while Today remains selected.
- Further taps may do nothing, eventually select Yesterday, or replace the
  editor with a blank screen.
- Keyboard dismissal proves the button action ran: `requestDate(_:)` in
  `App/Tend/Journal/JournalEditorView.swift` explicitly clears focus after a
  successful flush and before it calls the date-selection callback.

## Impact

Yesterday back-fill is unreliable from the primary fresh-Journal journey. The
visible editor and the installed navigation guard can also reference different
models. That mismatch creates an unconfirmed risk of saving prose against the
wrong day or losing a pending revision.

## Root cause

Two defects interact.

### Split editor-model ownership

`JournalDestinationChrome` owns `editorModel`, replaces it in
`resolveEditor(at:)`, and installs the navigation guard for that replacement.
`JournalEditorView` then copies the injected model into its own `@State` in its
initializer.

SwiftUI retains that state while it considers the child view to have the same
identity. Replacing the parent's model therefore does not reliably replace the
model rendered by the existing child. After a Today-to-Yesterday request, the
parent and navigation guard can own the new Yesterday model while the visible
view continues to render the old Today model.

Relevant surfaces:

- `App/Tend/Journal/JournalDestinationChrome.swift`
  - `editorModel`
  - `resolveEditor(at:)`
  - `installEditorNavigationGuard(for:)`
- `App/Tend/Journal/JournalEditorView.swift`
  - `@State private var model`
  - `init(model:...)`
  - `requestDate(_:)`

### Non-idempotent route replacement

`JournalDestinationChrome.showComposer(_:)` always calls `discardEditor()` after
asking `ShellRoutingModel.prepareJournalRoute(_:)` to prepare the destination.
The routing method intentionally does nothing when that route is already
active.

On a repeated Yesterday request, the route and entry graph may therefore remain
unchanged while `showComposer(_:)` clears `editorModel`. The synchronization
task is keyed by `refreshStamp(at:)`; because its identifier did not change, it
does not have to rerun. The compose route then renders with no editor model,
which is the observed blank screen.

Relevant surfaces:

- `App/Tend/Journal/JournalDestinationChrome.swift`
  - `showComposer(_:)`
  - `discardEditor()`
  - `.task(id: refreshStamp(at:))`
- `App/Tend/Application/ShellRoutingModel.swift`
  - `prepareJournalRoute(_:)`

Both behaviors were introduced together by commit `e5c60a7`,
`T-3hwtmu assemble Journal destination`.

## Coverage gap

`JournalExperienceUITests
.testEmptyJournalCreatesTodayBackfillsYesterdayAndRelaunchesToToday` does not
exercise the failing sequence. It writes and saves Today, returns to the
overview, reopens the persisted Today entry, and only then selects Yesterday.
The save changes the entry graph and retriggers synchronization, masking the
fresh-editor failure.

After tapping Yesterday, that test waits for `journalEditor.prose`, which
already existed before the tap. It does not first assert that Yesterday became
selected or that the date header changed.

No existing test covers:

1. an empty Journal;
2. opening **Write today's page** with the keyboard visible;
3. immediately selecting Yesterday;
4. asserting the selected scope and displayed date changed; and
5. repeating the active selection without losing the editor.

## Recommended correction

1. Make `JournalDestinationChrome` the sole owner of `JournalEditorModel`.
   `JournalEditorView` should observe the injected instance rather than copy it
   into independent `@State`.
2. Make date selection atomic and idempotent. After a successful flush, resolve
   and install the target editor directly. Never discard the editor when the
   requested route is already active, and do not rely on a task-identifier
   change as the only way to recreate it.
3. Add the exact fresh Today-to-Yesterday regression journey. Assert selected
   scope, date header, editor presence, and the persisted day. Repeat the active
   selection and prove it leaves the editor intact.

## Fixed when

- From a fresh empty Journal, one Yesterday tap changes the selected scope and
  date header while keeping the editor present.
- Re-selecting Yesterday is a no-op and never blanks or replaces the editor.
- Repeated Today/Yesterday switching keeps the visible editor, navigation
  guard, and persistence target on the same day.
- A failed flush vetoes the day change and retains the current editor and
  retryable prose.
- The exact reported journey has deterministic UI regression coverage that
  fails against the current implementation and passes with the correction.
