# Verify iPhone-Only Fast Logging Journey

This task supersedes
`app-experience/fast-logging/fast-logging-acceptance` (T-p7kknm) under the
iPhone-only decision in
`.tiller/decisions/2026-08-06-iphone-only.md`. It replaces that task’s
uncompleted universal-device acceptance contract; it does not waive or inherit
an iPad requirement.

## Approach

Exercise the complete merged Fast Logging feature on the supported compact
iPhone, from editable TendCore projection through the logging model, persisted
mutation, Today regrouping, quantity sheet, Undo, relaunch, accessibility,
motion, and feedback decisions. Run C1 through C5 first, then deterministic
daily and weekly current/grace journeys covering times and quantity habits,
empty/in-progress/complete states, validation, entry deletion, completed access,
Undo, and same-store relaunch.

Repeat representative journeys at two larger Dynamic Type steps with VoiceOver
settings, Reduce Motion, keyboard presentation, and forced-light appearance.
Run XCTest accessibility audits for contrast, hit region, sufficient
description, clipping, and traits. Record physical-device haptic and manual
VoiceOver work as pending unless the human actually observes it.

Generate final iPhone-only screenshots and a machine-readable evidence manifest
after the final source/test commit. Every record names the task and feature,
tested commit, iPhone runtime, fixture/store, injected instant and time zone,
scope/state, accessibility settings, exact command, artifact path, byte count,
pixel dimensions, SHA-256, observed result, and honest limitations.

## Surfaces

- The application and every test target must already declare device family `1`.
- Extend `App/TendUITests/FastLoggingUITests.swift` only when an iPhone
  acceptance gap or witnessed defect requires stronger executable coverage.
- Modify `App/Tend/Today/*`,
  `App/Tend/Shell/TodayDestinationChrome.swift`, fixtures, or focused tests only
  when a failing iPhone acceptance run proves a production or coverage defect.
- Create `.tiller/evidence/fast-logging/manifest.json` with schema
  `tend.fast-logging.evidence.v1` and deterministic lowercase `iphone-*` PNGs.
- Do not create, require, skip, or waive any iPad journey, screenshot, audit
  inventory, geometry assertion, or sheet-chrome behavior.
- Do not change domain semantics, Pencil comps, Almanac token values, unrelated
  feature surfaces, completed work, the in-review Today Dashboard task, or human
  gate state merely to make evidence pass.

## Tests

Run the exact feature bindings:

```bash
Scripts/tiller-swift-test Tests/TendCoreTests/Logging/HabitLoggingComputationTests.swift
Scripts/tiller-xcode-test TendTests/TodayLoggingModelTests
Scripts/tiller-xcode-test TendUITests/FastLoggingUITests/testTimesLoggingJourneys
Scripts/tiller-xcode-test TendUITests/FastLoggingUITests/testQuantityLoggingJourneys
Scripts/tiller-xcode-test TendUITests/TodayDashboardUITests
Scripts/tiller-xcode-test TendUITests/HabitManagementUITests
Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests
Scripts/tiller-swift-test Tests/TendCoreTests/Logging/LogEntryOperationsTests.swift
```

Then run the complete package/app suites and build gates:

```bash
Scripts/tiller-swift-test
Scripts/tiller-xcode-test TendTests
Scripts/tiller-xcode-test TendUITests
swift build
xcodebuild -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
swift format lint --recursive --strict Sources Tests App
```

Run every evidence journey after the final source/test commit. The manifest’s
`testedCommit` is that exercised commit before the evidence-only commit.

## Edge cases

- The existing iPhone `SET WEEK TOTAL` contrast finding must pass by corrected
  production behavior; removing iPad scope cannot suppress or waive it.
- Evidence asserts persisted progress and entry counts before and after each
  action; screenshots cannot prove dispatch, identity, rollback, or relaunch.
- Same-store relaunch omits reset and fixture arguments and proves transient
  sheet, editor, and Undo state is absent.
- Compact-iPhone geometry is exact. A substituted runtime is unavailable, not
  passed.
- Pixel evidence cannot prove VoiceOver speech, keyboard focus, Reduce Motion,
  haptic character, save dispatch, or persistence; pair images with observed
  test facts and record the remaining limitations.
- Every evidence path is lowercase, relative, unique, exists, has nonzero bytes
  and dimensions, and matches its recorded SHA-256.
- Evidence generation starts only after C1 through C5 are green.
