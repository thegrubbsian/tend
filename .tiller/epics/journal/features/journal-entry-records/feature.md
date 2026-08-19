# Journal Entry Records

## Summary

Add the durable, local-only record and domain APIs behind Tend's Journal. One
entry represents one canonical local day and owns only prose plus audit
timestamps. This feature establishes the invariant that the existence of an
entry becomes history after the today-and-yesterday grace window, while its
body remains editable forever.

This feature owns persistence, migration, lifecycle authorization, and
deterministic read queries. It does not add a Journal destination, compose
surface, Today invitation, reminders, search, habit logging, streaks, or any
other presentation.

## Behavior

### Shared civil-day value

Generalize the existing `GoalDate` value into one shared `LocalDate` type before
Journal records use it. The clean cutover renames every Goal caller, test, and
file; no alias or second date-key implementation remains. `LocalDate` keeps the
existing canonical `YYYY-MM-DD` representation, strict validation, ordering,
adjacent-day arithmetic, and time-zone-aware start-of-day behavior across DST
and extreme offsets.

### Durable entry

Advance the SwiftData store through the next versioned schema with a
`JournalEntry` model containing:

- a stable UUID identity;
- one canonical `LocalDate` key;
- an unbounded body stored without a separate title;
- an immutable creation timestamp; and
- an edited timestamp maintained by the mutation API.

The model remains permissive for migration and CloudKit-compatible graph
loading: it adds no unique constraint or deny rule. `JournalEntryOperations`
enforces at most one entry per day, and queries report corrupt duplicates
truthfully. The migration carries every existing Habit, Goal, history,
reminder-adjacent, and closure record forward unchanged. A Journal entry has no
relationship to a Habit, bucket, log entry, Goal, reminder, streak, or verdict.
The first line is presentation data derived from the body, never a persisted
title.

### Lifecycle operations

One operation boundary owns creation, editing, and deletion. It receives the
operation instant and owner time zone explicitly so authorization is
deterministic.

- Creation is legal only for today or yesterday at the operation instant.
- A second entry for the same day is refused rather than merged or overwritten.
- Deletion is legal only while that entry's day is today or yesterday.
- The body of any persisted entry may be replaced at any age.
- Creation sets both timestamps. A body change updates only `editedAt`; a no-op
  edit changes neither timestamp.
- The body is stored as supplied. The persistence layer does not invent a
  title, draft state, prompt, score, tag, attachment, or publication state.
- Detached, deleted, foreign-container, malformed-day, duplicate-day, and save
  failures are reported truthfully. A failed write restores the complete
  pre-operation state.

The existence rules and content rules stay deliberately separate: an old entry
cannot be deleted, but its prose remains editable.

### Read queries

Read APIs provide:

- zero-or-one entry for a `LocalDate`;
- all entries in reverse day order with a deterministic identity tie-break;
- the set of written days in an inclusive month window; and
- explicit failure when persisted data violates the unique-day or canonical-day
  invariants.

Queries do not interpret an absent day as missed and do not compute counts,
targets, streaks, standing, or reminders.

## Notes

The owner calendar is a presentation concern; the durable key remains the
canonical civil date already proven by Goal behavior. Moving that value to a
shared name is required to avoid a second, subtly different civil-day
implementation.

Empty or whitespace-only bodies are not normalized by this layer. Entry
existence is explicit—created by the experience layer's chosen save
interaction—and remains distinct from prose content.

Search, export, attachments, prompts, templates, habit coupling, automatic
habit logging, and native Journal reminders are outside this feature.
