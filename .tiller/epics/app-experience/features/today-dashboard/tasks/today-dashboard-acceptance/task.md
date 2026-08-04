# Verify Today Dashboard Journey

## Approach

Exercise the complete merged Today feature from persisted model state through
TendCore projection, presentation, SwiftUI, relaunch, and the custom shell.
Strengthen only tests or production behavior where the run witnesses a real
feature-contract failure; do not perform unrelated cleanup.

Run all command-backed feature criteria first. Then launch the approved
deterministic mixed, all-tended, inactive-only, and unavailable-row fixtures on
compact iPhone and centered iPad. Compare each complete surface with the
approved Pencil `Today` board and the feature’s explicit truthful differences,
including the computed fraction and static ring semantics.

Repeat the mixed and failure journeys at two larger Dynamic Type steps. Run
XCTest accessibility audits for contrast, hit region, sufficient description,
text clipping, and traits. Inspect VoiceOver order and exact labels/values,
section headings, retry, decorative progress silence, ring traits, safe-area
clearance, forced light appearance, and Reduce Motion. Record what was
observed, what was unavailable to deterministic automation, and never present
an unavailable physical VoiceOver traversal as passed evidence.

Capture deterministic screenshots and write a machine-readable evidence
manifest. The manifest records task and feature keys, device/runtime, fixture,
state, accessibility settings, exact command, source/test commit, image path,
byte count, SHA-256, pass/fail observation, and honest limitations. Generate the
manifest from the final PNG bytes; do not hard-code hashes or self-reference the
manifest.

Finish with the complete feature command gates and baseline habit-management
and shell suites. Keep C5/C6 in the feature acceptance contract pending human
attestation; this task supplies evidence but never attests those gates.

## Surfaces

- Extend `App/TendUITests/TodayDashboardUITests.swift` only when an acceptance
  gap or witnessed defect requires stronger coverage.
- Create `.tiller/evidence/today-dashboard/manifest.json` using schema
  `tend.today-dashboard.evidence.v1`.
- Create deterministic lowercase PNGs under
  `.tiller/evidence/today-dashboard/` for all four states on compact iPhone and
  centered iPad, plus mixed/failure larger-type evidence.
- Modify `App/Tend/Today/*` or `App/Tend/Shell/TodayDestinationChrome.swift`
  only when a failing acceptance run proves a production defect.
- Do not change domain semantics, fixtures, visual tokens, other feature
  surfaces, or human gate state merely to make evidence pass.

## Tests

Run the exact feature bindings:

```bash
Scripts/tiller-swift-test Tests/TendCoreTests/Today/HabitTodayComputationTests.swift
Scripts/tiller-xcode-test TendTests/TodayModelTests
Scripts/tiller-xcode-test TendUITests/TodayDashboardUITests
Scripts/tiller-xcode-test TendUITests/HabitManagementUITests
Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests
```

Then run the complete affected suites and build gates:

```bash
Scripts/tiller-swift-test
Scripts/tiller-xcode-test TendTests
Scripts/tiller-xcode-test TendUITests
swift build
xcodebuild -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
swift format lint --recursive --strict Sources Tests App
```

Run every dedicated compact-iPhone, centered-iPad, Dynamic Type, accessibility,
forced-light, and Reduce Motion evidence journey after the final source/test
commit. Re-run any affected command after a code or test correction. The
manifest’s `testedCommit` is the source/test commit exercised before the
evidence-only commit.

## Edge cases

- Device dates and localized labels come from the app under test, not a
  hard-coded test-runner `Date()` or locale.
- Evidence must include the top, middle, and bottom of scrollable content when
  one screenshot cannot show the complete surface.
- Relaunch uses the same named store without fixture or reset arguments.
- Pixel evidence cannot prove VoiceOver speech, action dispatch, persistence,
  or Reduce Motion; pair images with observed test facts and record remaining
  limitations.
- Simulator-only checks are not physical-device or full manual VoiceOver
  attestation.
- Every image path is relative, exists, is unique, uses lowercase naming, has
  nonzero dimensions and bytes, and matches its recorded SHA-256.
- Evidence generation runs only after C1 through C4 command bindings are green.
