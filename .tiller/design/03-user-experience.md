# 03. User Experience

This document specifies screens, flows, and interaction requirements. It deliberately describes capabilities and information, not visual design. Where it says "an affordance to log progress," the control that satisfies it (a button, a stepper, a slider, something better) is a design decision to be made during the build, not here. The one aesthetic direction worth recording: Tend's identity leans on cultivation and growth, and the visual language should feel like that rather than like a to-do list or a fitness dashboard.

## Structure

Four surfaces:

1. **Today**: the daily driver. What's due now, how it's going.
2. **All Habits**: the roster. Create, edit, activate, deactivate, delete.
3. **Habit Detail**: one habit's story. Streaks, history, recent entries.
4. **Add / Edit Habit**: the form behind create and edit.



Today is the landing surface on every launch.

## Today

Today shows every active habit with an unsettled current bucket, which means:

- All active daily habits, every day.
- All active weekly habits, every day of the week. A weekly habit is present Monday through Sunday with its week-to-date progress, not just on its pinned day. Pinned days aim reminders; they do not schedule appearances.



For each habit, Today must show:

- Name.
- Progress toward the current bucket's requirement, in the habit's own terms (for example, 20 of 30 min; 2 of 3 times; 5200 of 8000 steps).
- Current streak with its unit (days or weeks).
- The at-risk indicator when the displayed streak depends on an unmet grace bucket (see [02-domain-model.md](02-domain-model.md), Provisional display).



For each habit, Today must provide:

- A lightweight logging affordance scaled to the habit's shape. A target-1 `times` habit completes in a single interaction. Quantity habits (minutes, ounces, steps) accept a numeric amount quickly; a full form for "add 8 oz" is a failure.
- Undo of the most recent entry, immediately after logging, without leaving the screen.
- A path to back-fill the grace bucket. Reachable in at most 2 interactions from Today, because the grace save is a core mechanic, not an edge case buried in settings.



Default ordering: habits with unmet current buckets first, completed habits below them, alphabetical within each group. This is a default, open to refinement during design, and any replacement must keep unmet work more prominent than finished work.

When every current bucket is met, Today says so plainly. A moment of quiet satisfaction, not confetti.

### First launch

With no habits, Today explains what Tend is in a sentence or two and offers creation as the single obvious action.

## All Habits

Two sections: active and inactive. Every habit appears in exactly one.

- Active entries show name, requirement, cadence, and current streak.
- Inactive entries show name and the frozen streak, visibly dormant.
- From this screen the user can create a habit, open any habit's detail, activate or deactivate any habit, and delete a habit.
- Deletion requires explicit confirmation that names what is lost: the habit and its entire history, permanently. The confirmation should point toward deactivation as the reversible alternative.



## Habit Detail

One habit's full story:

- Current streak and best streak, each with its unit.
- The requirement and cadence, plus pinned days and reminder time where set.
- A history grid at bucket grain: day cells for daily habits, week rows or strips for weekly habits. Each cell communicates its state: met, missed, pending (open or grace), inactive gap, or before the habit existed. The grid covers at least the trailing 3 months and may extend further.
- Recent log entries for the open and grace buckets, each deletable here. Entries in final buckets are visible in aggregate through the grid but are not individually editable anywhere, matching the immutability rule.
- Access to Edit, and to activate or deactivate.



## Add / Edit Habit

Fields per the domain model: name, cadence, target, unit, pinned days (weekly only), reminder time.

- Create requires name, cadence, target, and unit; unit defaults to `times`.
- Edit exposes everything except cadence, which is displayed but locked. The lock deserves a one-line explanation in place, so the user learns the rule instead of filing a bug about it.
- Validation: name nonempty, target a positive integer. Pinned days only offered when cadence is weekly.
- Reminder time on a weekly habit with no pinned days should warn, in place, that no reminder will fire until a day is pinned.



## Logging interaction model

The logging affordance on every habit row is the log ring: a circular control that doubles as ambient progress. Empty, it shows an add mark inside a hairline ring. As the bucket fills, a moss arc grows around it. At target, it blooms into a solid filled check. The card's linear progress bar remains the precise readout; the ring is the glanceable one, and the two never disagree.

Behavior splits by habit shape:

- **Habits with unit `times` never open an entry surface.** A tap on the ring logs one instance. Target-1 habits complete in a single tap. Multi-count habits tick upward with each tap and complete on the last one.
- **Quantity habits open the log sheet on tap.** The sheet contains, in order: a scope control (Today, plus Yesterday whenever the grace bucket is still open, marked when unfinished), the bucket's progress, quick-add chips, a custom amount entry, a set-day-total entry, and the open bucket's logged entries with per-entry delete.
- **Quick-add chips are derived from the target,** rounded to friendly values, and the rightmost chip always logs exactly the remaining amount, labeled with it (for example, Finish · 10 min). At any progress level, one tap can close the bucket.
- **Set day total** exists for habits tracked as a running external total, such as steps: the user enters the day's current total and the app appends the difference as a new entry. It is entry sugar; the domain model still only ever appends.
- **The at-risk line on a card is a direct back-fill path.** On a quantity habit it opens the log sheet scoped to Yesterday. On a `times` habit it logs yesterday's instance immediately, no sheet.
- **Undo is inline and transient.** Immediately after any log, the card's meta line shows the logged amount with an Undo action for a few seconds, then reverts. Entries remain individually deletable in the log sheet and in Habit Detail, within open and grace buckets only.

Motion language: logging fills like liquid, completion blooms the ring into its check, and nothing ever bursts or celebrates beyond that. Haptics accompany logging and completion and are tuned on device.

## Notifications

Local notifications only. No server, no push.

- A habit with a reminder time fires one notification per scheduled occasion: daily habits at that time every day; weekly habits at that time on each pinned day. A weekly habit with no pinned days fires nothing, whatever its reminder time says; a nag needs an anchor.
- **A reminder is suppressed once the current bucket's requirement is met.** Completing the bucket before the reminder's time means it does not fire. No nagging about finished things.
- One reminder per habit per occasion. A 3-times daily habit gets one daily nudge, not three.
- Notification content: habit name and a short line about what's due. Tapping opens the app to Today.
- Notification permission is requested the first time the user sets a reminder time, in context, never at first launch.
- Notifications are not actionable in v1. Logging from the notification itself is a future capability.



## Interaction principles

- Logging is the highest-frequency action in the product and must be the cheapest. Every design decision on Today gets weighed against the speed of "I just did the thing, record it."
- Destructive actions (delete habit) confirm. Routine actions (log, undo, back-fill) never do.
- Streak states never lie and never soften. The at-risk state exists so the truth arrives while it's still actionable.
- The app is fully functional offline forever, trivially, because nothing in it touches a network.