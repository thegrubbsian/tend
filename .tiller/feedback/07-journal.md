# 07. Journal

The journal is a daily place to write prose. One entry per calendar day, in your own words, kept on the device with everything else. It has no targets, no streaks, and no verdicts; it is the one surface in Tend where nothing is measured.

## What an entry is

| Property | Rules |
|---|---|
| Day | The local calendar day the entry belongs to. One entry per day, maximum. |
| Body | Unbounded prose. The first line serves as the entry's display title; there is no separate title field. |
| Created / edited at | Timestamps, maintained automatically. |

No photos, no mood scores, no tags, no prompts in v1. A blank page and a date.

## The write window and the edit doctrine

Creation and deletion follow grace symmetry with the rest of Tend: an entry can be created or deleted only for today or yesterday. You cannot fabricate an entry for last March, and you cannot quietly remove one after its window closes. The record of *whether* you wrote is history and fossilizes like history.

Editing is different, and deliberately so: **the body of any entry stays editable forever.** Prose is not evidence. Fixing February's typo, or softening a sentence you regret, is a writer tending their own words, not history fraud. The doctrine split, precisely: existence is immutable after grace; content never is.

## Relationship to habits

None, in v1. The journal is not a habit, saving an entry logs nothing, and no streak is computed. If the user wants a journaling streak, they create a "Journal" habit themselves and log it manually after writing; double entry is the accepted cost for now. Auto-linking an entry-save to a habit log is deliberately deferred, not rejected. This also settles reminders: the journal has no native reminder; a self-made habit's reminder does that job with machinery that already exists.

## Experience

**The Journal screen** (a new top-level destination) leads with today: the day's entry if written, or the compose surface if not, one tap from words. Beneath it, past entries in reverse chronological order showing day and first line. A month grid in the garden-bed style marks which days carry entries, with the same month navigation as habit history; cells are binary here, written or not, in moss and paper, with no missed state because an unwritten day is an absence, not a failure.

**The entry view** shows the prose, and beside or beneath it, that day's garden: the day's habit results rendered live from data that already exists, stored nowhere in the entry itself. The day you wrote about and the day you tended, on one page.

**Composing** is unceremonious: the date, the page, the keyboard. Saving is automatic or one action; no drafts, no publish step. Yesterday's entry is reachable from the compose surface during its window, the same one-step back-fill spirit as habit logging.

**On Today**, a journal card sits with the day's work until the entry is written, offering the first line's worth of invitation; once written, the card leaves Today and the entry lives on the Journal tab. The card is an invitation, not an obligation: it carries no streak, no risk state, and no nag.

**No search in v1.** Reverse chronology and the month grid are the finding aids.

## Out of scope for v1

- Any coupling to habits or streaks (deferred; see above).
- Native reminders.
- Photos, mood tracking, tags, titles, prompts, and templates.
- Search and export.

## Worked examples

**The morning after.** Tuesday evening gets away from you; Wednesday morning you write Tuesday's entry. Legal: Tuesday is in its window through Wednesday. Thursday it would not be.

**The old typo.** In November you notice February 12th reads "the recital went bandly." You fix it. Legal forever; the edited-at timestamp updates and nothing else changes.

**The regretted page.** You want to delete an entry from last month. Refused: its window closed, its existence is history. You may edit it down to a single line, but the day keeps its mark.

## Decision notes

1. **Existence fossilizes, content doesn't.** The one place Tend's immutability doctrine bends, bent on purpose for prose and documented here so the bend is never mistaken for a bug.
2. **No journal-habit coupling in v1.** Manual double entry is accepted; the auto-log toggle is a named future enhancement, and the design must not preclude it.
3. **An unwritten day is an absence, not a miss.** The journal grid has no withered state. Measurement stops at the journal's door.
4. **The day's garden renders live** in the entry view and is never denormalized into the entry. One source of truth for habit history.
