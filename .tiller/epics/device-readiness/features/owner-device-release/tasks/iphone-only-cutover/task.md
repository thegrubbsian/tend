# Remove Native iPad Support

Implement `.tiller/decisions/2026-08-06-iphone-only.md` and the detailed
execution sequence in `.tiller/plans/2026-08-05-iphone-only-support.md` after
`app-experience/fast-logging/iphone-only-acceptance` (T-aocwl9) is done. The
result is one clean cutover: project metadata, production code, UI tests, and
forward acceptance all agree that Tend v1 supports native iPhone only.

## Approach

First change Debug and Release build settings for `Tend`, `TendTests`, and
`TendUITests` from device families `1,2` to `1`, and delete the app’s
iPad-specific orientation entries. Verify the effective settings before
touching Swift.

Then delete explicit iPad production behavior: remove regular-width device
detection from `TodayView`, remove the `showsCloseButton` input and iPad Close
control from `QuantityLogSheet`, and retain the standard iPhone sheet title and
swipe dismissal.

Finally collapse the UI suites to their existing iPhone branches. Remove iPad
sheet expansion, centered-tablet geometry, device-named fixture and screenshot
branches, iPad audit inventories, readable-column checks, split-view checks,
700-point tablet thresholds, and the iPad-only Dashboard test. Keep every
compact-iPhone geometry, owner behavior, Dynamic Type, keyboard, accessibility,
Reduce Motion, forced-light, persistence, relaunch, and failure assertion.

Characterize each retained iPhone suite before its edit and rerun it afterward.
No new source-text unit test is added merely to prove deletion; effective build
settings, behavioral suites, a bounded residue review, and a direct app launch
are the acceptance evidence.

## Surfaces

- `Tend.xcodeproj/project.pbxproj`
- `App/Tend/Today/TodayView.swift`
- `App/Tend/Today/QuantityLogSheet.swift`
- `App/TendUITests/HabitManagementUITests.swift`
- `App/TendUITests/HabitDetailUITests.swift`
- `App/TendUITests/TodayDashboardUITests.swift`
- `App/TendUITests/FastLoggingUITests.swift`
- Generated Tiller task/feature state and events after verification

Do not modify TendCore behavior, SwiftData models, fixtures, Almanac tokens,
completed task specs, completed plans, historical evidence, prior events, or
`app-experience/today-dashboard/today-dashboard-acceptance` (T-m66b11).
General responsive-width and safe-area code is not an iPad surface and remains.

## Tests

Prove all target families:

```bash
xcodebuild -project Tend.xcodeproj -target Tend -showBuildSettings -json | jq -e '.[0].buildSettings.TARGETED_DEVICE_FAMILY == "1"'
xcodebuild -project Tend.xcodeproj -target TendTests -showBuildSettings -json | jq -e '.[0].buildSettings.TARGETED_DEVICE_FAMILY == "1"'
xcodebuild -project Tend.xcodeproj -target TendUITests -showBuildSettings -json | jq -e '.[0].buildSettings.TARGETED_DEVICE_FAMILY == "1"'
```

Run focused iPhone characterization before and after each owning edit:

```bash
Scripts/tiller-xcode-test TendUITests/HabitManagementUITests
Scripts/tiller-xcode-test TendUITests/HabitDetailUITests
Scripts/tiller-xcode-test TendUITests/TodayDashboardUITests
Scripts/tiller-xcode-test TendUITests/FastLoggingUITests
```

Run final verification once:

```bash
swift build
Scripts/tiller-swift-test
Scripts/tiller-xcode-test TendTests
Scripts/tiller-xcode-test TendUITests
xcodebuild -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
swift format lint --recursive --strict Sources Tests App
```

Then directly launch the deterministic compact-iPhone app and exercise Today,
All Habits, Habit Detail, and quantity logging through keyboard submit/cancel,
Undo, and standard swipe dismissal. Run `tiller check task`, evaluate
`device-readiness/owner-device-release` (F-3vz7ho), and request code review
before submission.

## Edge cases

- The existing iPhone `SET WEEK TOTAL` contrast failure belongs to
  `app-experience/fast-logging/iphone-only-acceptance` (T-aocwl9); this task may
  neither inherit a red baseline nor waive the failure.
- Removing an iPad branch cannot remove an assertion that still protects iPhone
  behavior. Inline the current iPhone branch before deleting the condition.
- `AlmanacMetrics.readableContentWidth`, safe-area constraints, and flexible
  widths remain for iPhone landscape and accessibility.
- The final live-tree review excludes historical `.tiller` artifacts from its
  zero-iPad assertion and reports any unrelated pre-existing drift separately.
- A deterministic test failure receives one root-cause investigation, not a
  rerun-until-green loop.
