# Prove the complete Goals owner journey

## Approach

Complete and verify goals/goal-experience (F-xowx7x) on
goals/goal-experience/goals-roster-shell (T-99bqdn). Add deterministic
file-backed UI-test composition for goals, exercise the real form, roster,
detail, progress, lifecycle, and persistence paths, run the preservation suite,
and capture the manual visual and accessibility evidence required by the
feature contract. Fix defects in their owning production files; do not weaken
assertions or add test-only behavior to production models.

Create a goal UI-test fixture selected only by launch arguments. Seed stable
accumulate and increasing/decreasing measure goals covering on-pace, behind,
past-due, harvested, let-go, over-target, same-day multiple-reading, and
no-deadline presentations. Use the app's normal file-backed model container and
domain operations. Inject a stable local instant and calendar through the
existing UI-test composition seams so deadline, Today/Yesterday eligibility,
ordering, and displayed dates do not depend on wall-clock time.

Build `GoalExperienceUITests` around owner-visible labels and values plus stable
identifiers. One complete persistent journey must:

1. cold-launch on Today and select Goals;
2. create an accumulate goal and a measure goal through validated forms;
3. verify open ordering, both progress visuals, past-due grouping, and collapsed
   closed count;
4. open detail, append Today and Yesterday progress, delete an eligible item,
   and verify an older item has no delete action;
5. edit target, baseline or deadline and observe recomputed presentation;
6. harvest one goal, let go of another, expand Closed, and reopen one;
7. confirm permanent deletion, relaunch without resetting the store, and verify
   the deleted goal and its history remain absent.

Add focused accessibility automation where XCTest can make a deterministic
claim. Keep screenshot recording diagnostic rather than using pixel snapshots
as behavior tests. Run the existing complete UI target from the recorded
pre-change baseline to protect shell, Today, habits, detail, logging, and
reminders.

Then launch the actual feature and compare the compact roster with the Goals
board in `/Users/jcgrubbs/dev/tend-design/comps/tend.pen`. Exercise compact
portrait, landscape, two larger Dynamic Type steps, VoiceOver, Reduce Motion,
and failure/retry paths. Record evidence through Tiller without attesting the
human manual gate.

## Surfaces

- Create `App/Tend/Application/GoalExperienceUITestFixture.swift`.
- Create `App/TendUITests/GoalExperienceUITests.swift`.
- Modify `App/Tend/Application/TendUITestStore.swift` and app launch composition
  only to select the deterministic goal fixture from explicit UI-test
  arguments.
- Modify `App/Tend/Goals/**`, shell files, Almanac primitives, or focused tests
  only for defects exposed by acceptance.
- Modify `Tend.xcodeproj/project.pbxproj` only if synchronized groups do not
  discover the new files.
- Add Tiller evidence artifacts through `tiller`; never hand-edit machine-owned
  state.
- Do not change goal semantics, Today goal surfacing, Journal, reminders,
  Pencil comps, or production defaults to simplify the test.

## Tests

Run every feature binding:

- `Scripts/tiller-xcode-test TendTests/GoalRosterModelTests`
- `Scripts/tiller-xcode-test TendTests/GoalFormModelTests`
- `Scripts/tiller-xcode-test TendTests/GoalDetailModelTests`
- `Scripts/tiller-xcode-test TendUITests/GoalExperienceUITests`
- `Scripts/tiller-xcode-test TendUITests`

Also run:

- `Scripts/tiller-xcode-test TendTests`
- `Scripts/tiller-swift-test`
- `swift build`
- `xcodebuild -project Tend.xcodeproj -scheme Tend -destination
  'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

For visual evidence, compare the implemented compact roster and selected Goals
tab with the Goals comp; inspect form and detail against the approved Almanac
form, surface, typography, progress, and action grammar. For accessibility,
verify meaningful combined progress values, standing and closure without color,
disclosure and selected traits, logical focus after tab and sheet transitions,
44-point controls, readable larger text, and restrained motion.

## Edge cases

- UI fixtures must be unreachable without explicit test launch arguments and
  must never replace production persistence after a normal launch.
- Relaunch without reset must prove file-backed persistence; an in-memory
  fixture cannot satisfy the journey.
- Stable fixture time must not leak into production or make scene activation
  skip real-time refresh.
- The owner journey must cover both increase and decrease measure directions,
  not only the weight-loss example.
- Over-achievement, target equality, no deadline, past due, harvested, let go,
  reopened, and no-goals states each need observable evidence.
- Deletion confirmation must prove both Cancel and Delete, and the latter must
  remove dependent history after relaunch.
- The preservation run must use the complete `TendUITests` target; selecting
  only new Goals tests does not satisfy C5.
- Manual visual and accessibility criteria remain human gates even after
  evidence is attached.
