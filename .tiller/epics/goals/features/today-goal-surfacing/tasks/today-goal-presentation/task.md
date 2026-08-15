# Project needful goals into Today

## Approach

Extend the `TodayModel` produced by app-experience/today-dashboard (F-skoqxt)
after the Goals app and lifecycle prerequisites are present. Write
`TodayGoalModelTests` and `TodayGoalRefreshTests` first. Keep one Today
presentation generation and one refresh context; do not bolt a second
observable model onto the view.

Add a narrow injectable Goal projection operation beside the existing habit
operation. The live implementation accepts one persisted Goal plus
`TodayRefreshContext`, reads checked closure, computes kind-specific progress,
then computes standing through the existing TendCore APIs. It returns immutable
facts including progress, standing, deadline, and next time-only transition.
It performs no write, refresh scheduling, formatting, or copied pace math.

Extend the Today presentation with `TodayGoalRow` values and the earliest next
Goal transition. Use live Goal and SwiftData `PersistentIdentifier` for row
identity. Project every checked open Goal exactly once before eligibility
filtering; valid closed Goals require no progress computation and are absent.

Centralize eligibility in one private app-policy helper:

- include behind and past-due Goals;
- include an on-pace Goal whose GoalDate deadline is Today through the seventh
  next owner-calendar date, inclusive;
- exclude on-pace Goals without a deadline or with a later deadline;
- convert unknown closure or failed progress/standing/date state into a visible
  unavailable row rather than treating it as closed or ineligible.

Use GoalDate and explicit calendar arithmetic, never seconds. Sort unavailable,
past due, behind, then deadline-near on pace; inside each rank sort by deadline,
localized case-insensitive name, creation timestamp, and persistent identifier.
Reuse or extend existing goal formatting helpers for exact progress, deadline,
standing, and accessibility copy instead of inventing another vocabulary.

Build all habit rows, Goal rows, header facts, all-tended visibility, and next
refresh date before one published assignment. Goal rows never enter TO TEND,
TENDED, or the habit fraction. Suppress page-level `All tended.` while any
eligible or unavailable Goal exists. Preserve first-launch and inactive-only
habit state as a body that can compose with conditional Goal rows.

Extend `LocalDayTimelineSchedule` with at most one optional earlier transition.
It must emit the supplied start, then the earlier of the next local-day boundary
and valid Goal transition. Reconstruct it after refresh changes the transition;
do not retain an obsolete date or add another TimelineView. A transition at or
before the refresh instant is not rescheduled into a tight loop.

Goal retry addresses one persistent identity using a fresh context. If the Goal
disappeared, closed, or changed eligibility, run a complete refresh. Publish a
replacement row only after complete success. Query changes, scene activation,
calendar/TimeZone/Locale changes, day rollover, and transition ticks all run the
same atomic refresh path.

## Surfaces

- Modify `App/Tend/Today/TodayModel.swift` for Goal input, operation injection,
  rows, eligibility, deterministic ordering, retry, atomic publication, and
  earliest-transition output.
- Modify `App/Tend/Today/TodayPresentationFormatter.swift` only for Goal
  deadline, standing, progress, and combined accessibility copy not already
  exposed by the Goals feature.
- Modify `App/Tend/Shell/LocalDayTimelineSchedule.swift` to merge one optional
  earlier Goal transition with the local-day boundary.
- Create `App/TendTests/TodayGoalModelTests.swift`.
- Create `App/TendTests/TodayGoalRefreshTests.swift`.
- Reuse Goal progress/standing APIs and presentation values from the three
  recorded prerequisites.
- Modify the Xcode project only if synchronized groups do not discover new
  tests.
- Do not modify TendCore, SwiftData schema, goal mutation APIs, reminders,
  notification clients, shell destinations, SwiftUI cards, or Pencil comps.

## Tests

Bind feature criterion C1 to `TodayGoalModelTests`. Cover:

- behind before, inside, and outside seven days;
- past due at its exact exclusive boundary and long afterward;
- on pace Today, one day, exactly seven days, and eight days before deadline;
- no-deadline, harvested, and let-go exclusion plus reopened re-evaluation;
- over-target open Goal eligibility without auto-closure;
- spring-forward, fall-back, month/year, and TimeZone-change windows;
- every Goal projected once from the same captured refresh context;
- ordinary UUID collisions with distinct persistent identities;
- urgency, deadline, localized-name, creation, and identity ordering;
- truthful Accumulate and both Measure directions;
- malformed closure, date, progress, standing, and relationship failures kept
  as isolated unavailable rows;
- failed retry retention and success/removal by persistent identity;
- habit grouping/fraction independence and honest all-tended suppression.

Bind C2 to `TodayGoalRefreshTests`. Cover one atomic generation after Goal query
mutation, closure, reopening, deletion, scene activation, environment change,
day boundary, and domain transition. Prove an absent on-pace Goal enters when it
becomes behind, a Goal leaves when progress restores pace outside the proximity
window, and a near-deadline Goal stays.

Test schedule sequences for no transition, transition before midnight,
transition equal to midnight, stale transition, DST boundaries, and a refreshed
replacement transition. Assert exactly one schedule, no busy loop, no model
write, no reminder/notification call, and no mixed-generation publication.

Run:

- `Scripts/tiller-xcode-test TendTests/TodayGoalModelTests`
- `Scripts/tiller-xcode-test TendTests/TodayGoalRefreshTests`
- `Scripts/tiller-xcode-test TendTests/TodayModelTests`
- `Scripts/tiller-xcode-test TendTests`
- `swift build`

## Edge cases

- Seven dates away is eligible; eight dates away is not, regardless of whether
  a DST transition makes the instant interval shorter or longer than 168 hours.
- A deadline stays near through its full local day and becomes past due at the
  next local-day boundary.
- An unavailable Goal sorts first because the app cannot prove it is safe to
  hide; a valid closed Goal never appears as unavailable.
- An on-pace Goal outside the window still contributes its next time-only
  transition so it can enter Today without a store mutation.
- A Goal can be above target and past due simultaneously; its truthful progress
  and past-due standing both survive.
- No eligible Goal means no Goal rows and no Goal-only state object for the view
  to interpret.
