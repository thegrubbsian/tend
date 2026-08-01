# 02. Domain Model

This document defines the core concepts and the exact rules that govern them. It is the source of truth for behavior. Anything here is testable, and the release criteria require that all of it is tested.

## Habit

A habit is a recurring commitment with these properties:

| Property | Rules |
|---|---|
| Name | Required. Short free text. |
| Cadence | Required. `daily` or `weekly`. Immutable after creation (see Editing rules). |
| Target | Required. Positive integer. The amount that satisfies one bucket. |
| Unit | Required. Short free-text label such as `times`, `min`, `oz`, `steps`. Defaults to `times`. Carries no conversion semantics; it is a label the user chooses and the app displays. |
| Pinned days | Weekly habits only. Zero or more weekdays. Pinned days aim reminders and nothing else; they never constrain when logging counts (see Reminders in [03-user-experience.md](03-user-experience.md)). |
| Reminder time | Optional. One time of day. |
| Active flag | Boolean. New habits start active. See Active and inactive. |
| Created at | Timestamp, set at creation. |

Target and unit together form the habit's **requirement**. A target of 1 with unit `times` is the simplest habit: do the thing once. A target of 8000 with unit `steps` is the same mechanism with different numbers. There are no habit types.

## Buckets

A bucket is one evaluation period for one habit.

- For a daily habit, a bucket is one calendar day.
- For a weekly habit, a bucket is one calendar week, Monday through Sunday.



Buckets are determined by the device's local calendar. A day runs to local midnight. Daylight saving transitions do not create special cases: a 23-hour or 25-hour day is still exactly one bucket, and standard calendar arithmetic governs. If the device changes time zones, bucket boundaries follow the new local time; the app performs no time zone normalization and keeps no record of where an entry was logged.

### Bucket lifecycle

Every bucket moves through three states, in order:

1. **Open.** The current period. Entries can be added and deleted.
2. **Grace.** For exactly one day after the bucket closes, it remains editable. Yesterday's daily bucket is in grace today; last week's weekly bucket is in grace on Monday. Entries can still be added and deleted. The grace period exists because forgetting to log isn't the same as not doing the thing.
3. **Final.** After grace ends, the bucket is immutable. Its entries can no longer be added to or deleted, and its verdict is settled permanently.



### Verdicts

A bucket's verdict is **met** when the sum of its entries' amounts is greater than or equal to the requirement in force for that bucket, and **missed** otherwise. Verdicts are only settled at finality. While a bucket is open or in grace, its verdict is provisional: **pending-met** if the sum already meets the requirement, **pending-unmet** if it doesn't yet.

### Requirement snapshots

The open bucket and any grace bucket are always evaluated against the habit's current requirement. When a bucket becomes final, the requirement in force at that moment is frozen into the bucket's record, and the bucket is judged against that frozen requirement forever.

Consequence: editing a target or unit affects the open bucket, the grace bucket, and the future. It never re-judges history. Raising piano practice from 20 min to 30 min does not retroactively convert past successes into failures.

## Log entries

A log entry records one contribution toward a bucket: the habit, a timestamp, an amount (positive integer), and the bucket it belongs to.

- Entries default to the current open bucket.
- Entries may be added to the grace bucket explicitly. This is the back-fill path.
- Entries are append and delete only. There is no in-place edit; correcting a mistake means deleting the entry and adding a new one.
- Entries in final buckets cannot be deleted. Immutability of final buckets applies to the whole bucket, verdict and contents alike.
- No entry can ever be added to a bucket older than the grace bucket. Once a miss goes final, it fossilizes.



## Streaks

A streak counts consecutive satisfied buckets, and the unit of the count follows the cadence: daily habits have streaks measured in days, weekly habits in weeks. The two are never compared or combined, and the interface always names the unit ("12 days," "9 weeks").

### The chain

Walking backward from the present, the streak is the number of consecutive buckets that are met (final) or pending-met (open or grace), stopping at the first final missed bucket. Buckets that fall in an inactive period are skipped entirely; they are links removed from the chain, not breaks in it (see Active and inactive).

A final missed bucket resets the streak to zero. There is no partial credit: a 3-per-day habit with 2 completions in a final bucket is a missed bucket, full stop.

### Provisional display

Because open and grace buckets aren't settled, the displayed streak is optimistic: pending buckets are assumed savable. A pending-unmet grace bucket does not yet break the displayed streak, because the user can still back-fill it. The interface must make this state visible: when a habit's displayed streak depends on a grace bucket that is still unmet, the streak is **at risk**, and the user must be able to see that at a glance. When the grace expires unmet, the bucket goes final as missed and the streak collapses to whatever the chain supports from that point.

### Best streak

Each habit records its best streak: the longest chain it has ever achieved under the rules above. The best streak updates whenever the current chain exceeds it.

## Active and inactive

Some habits have seasons. A vegetable garden in Chicago doesn't need tending in January, and a habit shouldn't accumulate misses while the world makes it impossible.

- Deactivating a habit suspends tracking. The habit disappears from daily use, stops producing buckets, and fires no reminders.
- **Deactivation exempts every bucket that is not yet final.** The open bucket and any unmet grace bucket are removed from the chain rather than judged. The streak freezes at its last settled value.
- While inactive, no buckets exist for the habit. The inactive period is a gap in the timeline, not a run of misses.
- Reactivating resumes tracking immediately. **The bucket containing the reactivation moment is the next required link in the chain.** Reactivate on a Tuesday afternoon and Tuesday is due, with whatever remains of the day to meet it.
- The frozen streak carries across the gap. A 40-day garden streak paused in November resumes at 40 in April, and the first met bucket after reactivation makes it 41.



### The loophole, on purpose

These rules permit a dodge: at 11:58 PM with a habit unmet, deactivate, then reactivate tomorrow, and the streak survives. This is known and accepted. The product's honesty model is self-honesty (see [01-overview.md](01-overview.md)); a user who cheats this way is lying to the only person the streak reports to. Do not build countermeasures.

## Editing rules

| Property | Editable after creation? | Effect |
|---|---|---|
| Name | Yes | Display only. |
| Target | Yes | Applies to open and grace buckets and the future. Final buckets keep their frozen requirement. |
| Unit | Yes | Same snapshot rule as target. |
| Pinned days | Yes | Affects future reminders only. |
| Reminder time | Yes | Affects future reminders only. |
| Active flag | Yes | See Active and inactive. |
| Cadence | **No.** | Immutable. |

Cadence is immutable because a day-chain and a week-chain are different species; splicing one onto the other manufactures fake continuity. To change a habit's cadence, deactivate (or delete) the old habit and create a new one. The old habit's history stays intact and readable.

Deleting a habit is permitted, permanently removes the habit and its entire history, and requires explicit confirmation. Deactivation is the recommended path for anything the user might want back.

## Worked examples

These examples are normative. They should translate directly into test cases.

**Grace save.** Piano (daily, 30 min). Monday: 30 min logged. Tuesday: nothing logged. Wednesday morning, the user back-fills 30 min into Tuesday's grace bucket. Tuesday settles as met. The streak is unbroken.

**Fossilized miss.** Same habit. Tuesday: nothing logged. Wednesday: nothing back-filled. At Wednesday's end, Tuesday's grace expires and Tuesday goes final as missed. The streak resets to zero, and Thursday it is too late: Tuesday can never be edited again.

**Multi-count reset.** Meditation (daily, 3 times). Two entries logged Monday. Monday finalizes with 2 of 3. Monday is missed. Streak resets. Two out of three is zero out of one bucket.

**Weekly slip.** LinkedIn (weekly, 1 times, pinned Wednesday). Nothing logged by Wednesday; a post is logged Thursday. The week's bucket is met. Pinned days never gate completion.

**Seasonal gap.** Garden (daily, 1 times), streak 40, deactivated November 1 with November 1 unmet. November 1 is exempted, not missed; the streak freezes at 40. Reactivated April 15. April 15 is the next required bucket. Tending on April 15 makes the streak 41.

**Target raise.** Piano target raised from 20 to 30 min on the 10th. Buckets final before the 10th keep the 20-min requirement they were judged against. The 10th and onward, including a 9th still in grace, require 30.

## Decision notes

Non-obvious judgment calls, recorded so nobody re-litigates them by accident:

1. **The grace period is one universal rule, not a daily-only exception.** The previous bucket stays editable for one day after it closes, whatever the cadence. For weekly habits that means last week is editable on Monday only. One rule, both cadences.
2. **Final means fully immutable.** Deletion is blocked in final buckets, not just addition. History that can be quietly edited isn't history.
3. **Deactivation exempts all non-final buckets, grace included.** Anything not yet settled when the user steps away is removed from judgment, which is consistent with the accepted loophole above.
4. **Reactivation makes the current bucket due, not the next one.** Rejoining mid-week or mid-day puts the habit immediately back in play. Reactivating at 11:59 PM is the user's own problem.
5. **Amounts and targets are positive integers in v1.** Every seed habit's natural quantity (steps, minutes, ounces, counts) fits integers. Fractional quantities are complexity with no current customer.
6. **Units snapshot with targets.** Changing `oz` to `ml` going forward must not garble what past buckets meant.