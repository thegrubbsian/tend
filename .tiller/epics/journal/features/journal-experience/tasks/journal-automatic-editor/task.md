# Build the automatic Journal editor

## Approach

Create `JournalEditorModel` and `JournalEditorView` for one immutable
`LocalDate`. Inject the operation boundary, current-time source, and a
cancel-safe 500-millisecond debounce clock. Opening a missing day starts with
an in-memory blank body and no model. The first debounced non-whitespace body
creates; once identity exists, every later revision edits verbatim, including
empty content.

Track a monotonic revision so stale debounce completions cannot overwrite newer
text. Expose explicit idle, pending, saved, and failed presentation states.
Before back navigation, tab changes, date changes, or scene backgrounding,
cancel the debounce and flush the latest revision immediately. A failed
navigation flush vetoes departure, retains text and focus, and exposes Retry.
Retry writes the same revision idempotently.

Offer Today and Yesterday scope only for legal new-entry dates. Existing old
entries open directly and remain editable. Show Delete only when operations
authorize it; require confirmation and return to overview only after a
successful delete.

## Surfaces

- `App/Tend/Journal/JournalEditorModel.swift`
- `App/Tend/Journal/JournalEditorView.swift`
- A small injectable debounce-clock protocol or closure beside the model
- Journal route flush coordination
- `App/TendTests/JournalEditorModelTests.swift`
- `App/TendUITests/JournalEditingUITests.swift`

## Tests

Write model tests with a manual clock before implementation. Cover no creation
on open, whitespace-only new text, debounce cancellation/coalescing, first
create, later empty edit, stale revision suppression, exact timestamp behavior,
immediate lifecycle flush, navigation veto, retry, duplicate prevention, old
entry editing, date-scope eligibility, and legal/forbidden deletion. UI tests
prove keyboard focus, no Save button, persistence status, retained failure
text, confirmation, VoiceOver naming, relaunch, and first-line propagation.

## Edge cases

IME composition and rapid Unicode edits must not persist partial marked text.
A background flush may fail while the app is inactive; keep the failure and
body for the next active scene instead of claiming success. Cancelling a blank
new editor creates nothing. Clearing an existing body is never translated into
delete. A process kill inside the debounce can lose only the not-yet-saved
revision; no draft record is created.
