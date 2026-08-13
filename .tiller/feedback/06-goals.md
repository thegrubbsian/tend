# 06. Goals

Goals are trackable arcs: a quantity moving toward a target, optionally against a deadline. They sit beside habits, not inside them. Habits are rhythms judged bucket by bucket; goals are single arcs judged once, by you. Nothing in this document changes habit behavior.

## What a goal is

| Property | Rules |
|---|---|
| Name | Required. Short free text. |
| Kind | Required. `accumulate` or `measure`. Immutable after creation. |
| Target | Required. Positive integer. |
| Unit | Required. Short free-text label (`books`, `lbs`, `hours`). Defaults to `times`. |
| Baseline | Measure goals only. Required. Integer captured at creation, the value you're starting from. Correctable later. |
| Deadline | Optional. A calendar date. |
| Created at | Timestamp, set at creation. Serves as the start of the arc for pace math. |

Every goal is trackable by construction. Untrackable aspirations ("visit Barcelona") are out of scope: if it has no quantity, it isn't a Tend goal. Maintenance targets ("stay under 180") are also out: a goal is an arc with an end, not a state to hold.

## Two kinds

**Accumulate.** Progress is the sum of logged amounts. "Read 6 books this quarter": each finished book is an entry of 1, progress is the running sum against 6. Entries carry a date and a positive integer amount. Over-achievement is allowed and displayed honestly ("7 of 6 books").

**Measure.** Progress is your latest reading against the target, measured from the baseline. "Lose 30 lbs by January 1": baseline 195 captured at creation, target 165, and progress is how far the latest reading has traveled along that span. Direction is derived from which side of the baseline the target sits on; nothing is ever configured as "increase" or "decrease." Readings carry a date and an integer value; when a day has multiple readings, the latest one is that day's effective value. A reading past the target clamps progress at complete; the goal still waits for you to close it.

The two kinds exist because sum-of-events and latest-of-readings are different truths and unifying them would make one of them a lie. This is a deliberate departure from the habit system's single mechanism, made with eyes open.

## Entries and readings

Both follow the habit log discipline: append and delete, never edit in place, and both operations are limited to items dated today or yesterday. You cannot back-fill last month's weigh-in or delete March's book. There are no buckets, no verdicts, and no streaks anywhere in goals.

## States and standings

A goal is **open** or **closed**.

While open, its standing is computed, never stored:

- **On pace** (moss): no deadline, or tracking at or ahead of expectation.
- **Behind** (ochre): a deadline exists and progress trails expectation.
- **Past due** (withered): the deadline has passed and the goal remains open.

Expectation is linear: from zero progress at creation to full progress at the deadline, evaluated at the current instant. Goals without deadlines have no pace; they're simply open, shown in moss, and progress at whatever rate life allows.

Closing is always manual and comes in two flavors: **harvested** (you got there, or close enough to call it) and **let go** (you're done wanting it). A past-due goal is not failed; it's a goal waiting for an honest conversation. Nothing auto-closes, ever. Closed goals can be reopened if closing was a mistake.

## Editing and deletion

Name, target, unit, deadline, and baseline are editable at any time. Kind is immutable; an accumulate arc and a measure arc are different species, and converting one to the other means deleting and creating anew.

Unlike habit requirements, goal edits are not snapshotted: changing the target re-judges the whole arc immediately, past and present alike. Habits snapshot because settled buckets hold verdicts that must not be rewritten; goals hold no verdicts until you close them, so there is nothing to protect and re-scoping mid-arc is legitimate.

Deleting a goal removes it and its entries or readings permanently, behind an explicit confirmation.

## Experience

**The Goals screen** (a new top-level destination) lists open goals with behind-pace ones first, past-due goals in their own section, and closed goals (harvested and let go together) collapsed at the bottom. Creation and editing use a form consistent with the habit form; the kind choice locks after creation with an in-place explanation, same pattern as cadence.

**Each open goal shows a progress visual in its own terms:**

- Accumulate: the standard progress track plus the fraction ("2 of 6 books"), with a pace mark on the track when a deadline exists showing where expectation sits today.
- Measure: a span from baseline to target with the current reading marked along it, the same pace mark when deadlined, and the plain numbers beside it ("183 · 12 of 30 lbs").

Standing colors follow the house grammar; nothing new is invented.

**Goal detail** shows the progress visual large, the deadline and days remaining when one exists, the entry or reading list with deletes limited to the two-day window, edit access, and the close actions.

**On Today**, goals appear only when they need you: behind pace, or within 7 days of deadline. They render in a GOALS section below the habit sections and leave Today the moment they're back on pace or closed. Today remains a place of things-that-need-you, not a trophy shelf.

**No notifications** for goals in v1. Today surfacing is the whole nudge apparatus.

## Out of scope for v1

- Habit linking (auto-feeding an accumulate goal from a habit's logs). Deliberately deferred, not rejected; the manual path must not preclude it.
- Untrackable or someday goals, step lists, and milestone treatments.
- Maintenance goals.
- Non-integer quantities.
- Charts or trend lines; the progress visuals above are the ceiling.

## Worked examples

**Books on pace.** "Read 6 books this quarter," created October 1, deadline December 31. On November 15 (half the span), expectation is 3; logged progress is 4. On pace, moss, absent from Today.

**Books behind.** Same goal with 2 logged on November 15. Behind, ochre, present on Today until the third book lands.

**Weight arc.** "Lose 30 lbs by January 1," baseline 195, target 165. Latest reading 183: progress is 12 of 30. Expectation on the date of evaluation determines moss or ochre. A January 9 reading of 165 shows complete and past due simultaneously; the user closes it as harvested, and the lateness is nobody's business but theirs.

**The deadline passes.** Any deadlined goal still open on deadline day plus one wears withered and moves to the past-due section. It counts nothing as failed and waits.

## Decision notes

1. **Kind is immutable** for the same reason cadence is: splicing species manufactures fake continuity.
2. **Goal edits are not snapshotted.** Goals hold no settled verdicts, so re-judging the arc on edit is honest, not revisionist. The contrast with habit snapshots is intentional and documented here so nobody "fixes" it into consistency.
3. **Creation date is the pace anchor.** No separate start-date field; you planted it when you planted it.
4. **Over-achievement displays truthfully** and never auto-harvests. Closing is a human act in both directions.
5. **Deadlines are optional.** A no-deadline accumulate goal ("100 hours of piano, whenever") is legitimate and simply has no pace.
6. **Target-1 goals are permitted but not optimized for.** The form allows them; the progress visual degrades to empty-or-full. If they proliferate, that's a signal to revisit the someday-goal cut, not to bolt on special cases now.
