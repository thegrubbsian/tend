# Integrate the Goals roster and shell destination

## Approach

Integrate the complete Goals destination on
goals/goal-experience/goal-detail (T-bvcyq8). Start with
`GoalRosterModelTests`, then extend the existing shell and build the roster
against one production `ModelContext`. Reuse the goal form, detail, and progress
components; do not introduce a second navigation or persistence architecture.

Add a main-actor observable `GoalRosterModel` that fetches every goal and asks
the TendCore lifecycle/standing boundary for presentation facts at an injected
instant and calendar. Partition every goal exactly once into open, past-due, or
closed. Sort open goals with behind before on pace, then deadline, localized
name, creation time, and identifier; sort past-due by deadline and the same
tie-breakers; keep harvested and let-go goals together in deterministic closed
order. Model the closed disclosure state separately from persisted goal state.

Refresh after initial load, successful form or detail mutations, scene
activation, local-day rollover, and any earlier next-standing transition
reported by the domain computation. Keep the prior saved rows during a failed
refresh and expose retry instead of substituting sample data or zeros.

Build `GoalRosterView` with:

- the Goals reference-board title row and accessible New goal control;
- kind-specific progress rows using `GoalProgressView`;
- owner-visible deadline, standing, and closure text in Almanac colors;
- omitted empty sections and a collapsed `CLOSED · N` disclosure row;
- a useful no-goals explanation and New goal action;
- full-screen row selection into `GoalDetailView`;
- New and Edit presentation through `GoalFormView`;
- restoration to the same scroll context after dismissing sheets or detail.

Extend `ShellDestination`, `FloatingTabPill`, `AlmanacShellView`, and routing
tests with a Goals case between Today and Habits. Use `flag` for the icon,
`shell.tab.goals` for the tab, and `shell.destination.goals` for the
destination. Preserve Today as the cold-launch default, selection across
backgrounding, focus transfer, selected traits, root store ownership, safe-area
insets, and the absence of native tab chrome. Do not add the Journal case,
placeholder content, or a disabled fourth tab.

Match the Goals board's roster content, progress treatment, warm surfaces,
typography, hairlines, spacing, section labels, selected tab, and no-shadow
grammar. Adapt the existing pill to three equal accessible buttons without
hard-coded phone coordinates. Today and Habits content must not change.

## Surfaces

- Create `App/Tend/Goals/GoalRosterModel.swift`.
- Create `App/Tend/Goals/GoalRosterView.swift`.
- Create `App/Tend/Shell/GoalsDestinationChrome.swift`.
- Create `App/TendTests/GoalRosterModelTests.swift`.
- Modify `App/Tend/Shell/ShellDestination.swift`.
- Modify `App/Tend/Shell/FloatingTabPill.swift`.
- Modify `App/Tend/Shell/AlmanacShellView.swift`.
- Modify `App/Tend/Application/ReminderRoutingModel.swift` only where exhaustive
  destination handling requires the new non-reminder destination.
- Modify `App/TendUITests/AlmanacShellUITests.swift` for the third functional
  destination and preserved selection semantics.
- Modify Almanac metrics or icons only when the existing APIs cannot express
  the approved board.
- Modify the Xcode project only if required for new file discovery.
- Do not modify TendCore goal behavior, Today or Habits content, reminder
  planning, Journal, or Pencil comps.

## Tests

Write `GoalRosterModelTests` before the roster. Cover empty data; each standing
and closure state; exact-on-target and over-target accumulate facts; increasing
and decreasing measure facts; no-deadline rows; behind-before-on-pace ordering;
past-due partitioning; deterministic ties; closed count and disclosure;
refreshes after time and mutation changes; and honest fetch/computation
failure.

Update `AlmanacShellUITests` to assert Today remains selected on cold launch;
Today, Goals, and Habits are owner-visible accessible buttons; Goals selection
shows only the Goals destination; background/foreground preserves Goals; a new
process returns to Today; and no native tab bar or Journal tab appears.

Run:

- `Scripts/tiller-xcode-test TendTests/GoalRosterModelTests`
- `Scripts/tiller-xcode-test TendTests/GoalFormModelTests`
- `Scripts/tiller-xcode-test TendTests/GoalDetailModelTests`
- `Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination
  'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Launch the roster on a compact iPhone and in landscape. Compare it with the
Goals board in `/Users/jcgrubbs/dev/tend-design/comps/tend.pen`, checking the
three implemented destinations rather than requiring Journal. Verify closed
disclosure, long localized values, two larger Dynamic Type steps, VoiceOver
row summaries, selected tab state, 44-point controls, and no content beneath
the floating pill.

## Edge cases

- No goals shows no decorative OPEN, PAST DUE, or CLOSED section.
- A goal moving behind or past due while the app remains open changes group at
  the next domain-reported transition without a relaunch.
- No-deadline goals are on pace but sort after deadlined goals within that
  standing.
- Names equal under localized comparison remain stable through creation time
  and identifier tie-breakers.
- Closed disclosure state survives roster reloads during the same view
  lifetime but is not persisted.
- Long names, units, and large integers grow rows rather than overlap progress
  marks or truncate essential facts.
- Failed row refresh, form save, or detail mutation keeps the last saved roster
  and exposes retry.
- Adding Goals must not schedule reminders, fetch network data, initialize
  another model container, or alter Today/Habits navigation stacks.
