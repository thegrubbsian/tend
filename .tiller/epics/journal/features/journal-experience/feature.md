# Journal Experience

## Summary

Give the Journal its complete Almanac home: a fourth root destination, a
today-first overview, reverse-chronological entries, a binary month garden, an
automatic prose editor, and each written day's live Habit garden. The owner can
reach today's blank page in one action, back-fill yesterday while its window is
open, revisit any written day, edit its prose forever, and delete only today or
yesterday.

The feature presents and orchestrates the rules supplied by
`journal/journal-entry-records (F-rsayqb)`. It never stores Habit results in an
entry and never turns Journal activity into a Habit, streak, reminder, target,
score, prompt, or verdict.

## Behavior

### Root destination and routing

Add `Journal` after `Habits` in the existing floating tab pill, producing the
stable order Today, Goals, Habits, Journal. Use the Almanac book symbol and the
same selected capsule, accessibility focus, hit target, and label behavior as
the other destinations. Cold launch still selects Today; background/foreground
preserves the active destination; a terminated relaunch returns to Today.

One Journal routing model owns overview, entry, and compose selection. Route
requests carry a `LocalDate`, resolve persisted identity through
`JournalEntryQuery`, and remain local to the shell. A missing, deleted, or
foreign entry returns to a truthful overview state rather than retaining a
stale model object.

All root-destination changes go through the shell routing model rather than a
direct mutable tab binding. While an editor has unsaved or pending text, it
registers one navigation guard that flushes the current revision before a tab,
back, date, or notification route commits. A failed flush cancels the route,
keeps Journal selected, and returns focus to the retryable editor error.

### Journal overview

The Journal screen leads with today:

- when today's entry exists, a raised Today page shows its date and derived
  first line and opens that entry;
- when it does not exist, the Today page opens a blank editor with today's date
  and keyboard focus in one action; and
- a load failure replaces derived Journal content with one retry state without
  inventing an empty history.

Beneath Today, show past entries in reverse local-day order. Each row contains
the localized day and first line derived from the current body; an empty body
uses a quiet content-empty fallback, never a stored title. Rows open the exact
persisted entry. No pagination or search is added in v1.

A month garden reuses Habit history's month navigation and cell geometry but
not its judgment states. Written days are moss; absent days are paper. There is
no missed, withered, grace, risk, future failure, count, or streak. Today keeps
the established clay marker without implying an obligation. Written cells open
their entry; absent cells are not fabricated. Month navigation spans from the
earliest entry month through the current month and clamps safely after entry
deletion.

The overview refreshes from one explicit current context on first appearance,
scene activation, local-day rollover, time-zone or locale change, entry query
mutation, and retry. Repeated refreshes preserve selected month and route when
their targets remain valid.

### Automatic editor

The editor is only the selected date, a full-width prose page, the keyboard, and
quiet persistence status. It has no title field, prompt, draft, publish state,
or Save button.

The answer to Q-jyd9k4 is normative:

- opening a blank editor creates no entry;
- after the body contains non-whitespace text, a short deterministic debounce
  calls the shared create operation;
- once an entry exists, every later debounced body change—including an empty
  body—calls the shared edit operation and never deletes existence;
- pending text flushes immediately before back navigation, tab changes, scene
  backgrounding, or another date selection;
- a successful write reports a quiet saved state and updates overview/query
  consumers;
- a failed write retains the in-memory body, keeps the editor open when
  navigation requested the flush, exposes the concrete failure with Retry, and
  never claims the body was saved; and
- retries are idempotent and never create a duplicate day.

The editor offers Today and Yesterday as its only new-entry scope while both
are legal. Selecting an existing entry in either scope edits it. Selecting an
absent yesterday opens its blank page. Older entries open from history and
remain editable forever, but their date cannot change.

Deletion is available only when the shared operations authorize the selected
entry's day. It requires deliberate confirmation, returns to the overview on
success, and leaves the editor intact with a retryable error on failure. Old
entries expose no delete affordance.

### Written day's garden

An entry view places that day's live Habit garden beneath the prose. Project
the Habit graph for the entry's `LocalDate` at the current refresh instant using
the existing bucket evaluation and activity-period rules. Show every Habit that
was active for that day with its truthful name, progress/result, and Almanac
state. Isolate a malformed Habit graph to an unavailable row while retaining
valid siblings.

The garden is read from current Habit data every time the entry view refreshes.
JournalEntry stores none of it. Habit logging, correction, archive/reactivation,
time-zone, and local-day changes update the garden through the established
Habit source of truth; Journal never writes or reconciles Habit history merely
to render it.

### Accessibility and layout

Support the iPhone-only product contract in portrait and landscape, keyboard
appearance, two larger Dynamic Type steps, VoiceOver reading and focus order,
Reduce Motion, increased contrast, and forced light appearance. Entry prose
remains readable above the keyboard and floating tab pill. Month cells retain
minimum hit targets through an accessible overlay without changing their fixed
visual geometry.

Errors name the failed operation and the available recovery. Empty Journal
copy invites writing without praise, pressure, streak language, or a missed-day
judgment.

## Notes

The first line is always derived at projection time. Editing an old first line
updates every overview row immediately without changing identity or day.

The month garden is a finding aid, not analytics. The live Habit garden belongs
only to a written entry's view; an absent day has no synthetic page or Habit
snapshot.

Photos, mood scores, tags, titles, prompts, templates, search, export, native
reminders, habit auto-logging, and Journal streaks remain outside v1.
