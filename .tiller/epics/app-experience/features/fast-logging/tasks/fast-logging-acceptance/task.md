# Verify Fast Logging Journey

## Approach

Exercise the complete merged feature from editable TendCore projection through
logging model, persisted mutation, Today regrouping, quantity sheet, Undo,
relaunch, accessibility, motion, and feedback decisions. Strengthen only tests or
production behavior where the run witnesses a real contract failure; do not
perform unrelated cleanup or attest human gates.

Run C1 through C5 command bindings first. Then launch deterministic daily and
weekly current/grace journeys on compact iPhone and centered iPad. Capture the
complete Today and sheet surfaces for empty, in-progress, complete, transient
Undo, current/grace, validation, empty entries, completed access, and long
content. Compare against Pencil nodes `Zl4uG`, `KUuoB`, and `afx4Y`, allowing
only the feature contract’s truthful data and standard iPad sheet-chrome
differences.

Repeat representative times and quantity journeys at two larger Dynamic Type
steps with VoiceOver settings, Reduce Motion, keyboard presentation, and forced
light appearance. Run XCTest accessibility audits for contrast, hit region,
sufficient description, clipping, and traits. Inspect exact reading order,
labels, values, hints, selected/unfinished state, focus after errors/scope
changes, duplicate announcements, scroll reachability, safe areas, and tab-pill
clearance. Record physical-device haptic and manual VoiceOver work as pending
unless actually observed by the human; simulator events never prove either.

Capture deterministic screenshots and write a machine-readable evidence
manifest. Each record includes task/feature keys, tested source commit,
device/runtime, fixture/store, injected instant/time zone, scope/state,
accessibility settings, exact command, image path, bytes, pixel dimensions,
SHA-256, observed pass/fail, and honest limitations. Generate records from final
PNG bytes; never hard-code hashes or self-reference the manifest.

Finish with complete package/app suites, generic iOS build, and repository Swift
format gate. Re-run every affected command and evidence journey after any source
or test correction. Keep manual C6/C7 pending human attestation.

## Surfaces

- Extend `App/TendUITests/FastLoggingUITests.swift` only when an acceptance gap
  or witnessed defect requires stronger executable coverage.
- Create `.tiller/evidence/fast-logging/manifest.json` using schema
  `tend.fast-logging.evidence.v1`.
- Create deterministic lowercase PNGs under
  `.tiller/evidence/fast-logging/` for required iPhone/iPad, daily/weekly,
  current/grace, Undo, validation, empty/complete, and larger-type surfaces.
- Modify `App/Tend/Today/*`,
  `App/Tend/Shell/TodayDestinationChrome.swift`, fixtures, or focused tests only
  when a failing acceptance run proves a production/coverage defect.
- Do not change domain semantics, feature criteria, Pencil comps, Almanac token
  values, unrelated feature surfaces, or human gate state merely to make
  evidence pass.

## Tests

Run exact feature bindings:

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

Then run complete affected suites and build gates:

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

- Evidence asserts persisted progress and entry counts before/after each action;
  screenshots alone cannot prove dispatch, identity, rollback, or relaunch.
- Fixed instants and localized labels come from the app/fixture, not runner
  `Date()` or assumed locale.
- Scrollable dashboard/sheet content records top, middle, and bottom when one
  viewport cannot show the whole surface.
- Same-store relaunch omits reset and fixture arguments and proves transient
  sheet/editor/Undo state is absent.
- Device geometry must match the named compact-iPhone or centered-iPad journey;
  a substituted runtime is recorded as unavailable, not passed.
- Pixel evidence cannot prove VoiceOver speech, keyboard focus, Reduce Motion,
  haptic character, save dispatch, or persistence; pair images with observed
  test facts and record remaining limitations.
- Every evidence path is lowercase, relative, unique, exists, has nonzero bytes
  and dimensions, and matches recorded SHA-256.
- Evidence generation starts only after C1 through C5 command bindings are green.
