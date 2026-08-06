---
node: F-3vz7ho
criteria:
  - id: C1
    statement: The Tend application, app-unit-test, and UI-test targets build only for iPhone device family 1 in Debug and Release, retain the existing iPhone orientations, and carry no iPad-specific orientation override.
    polarity: introduce
    binding: { type: command, run: "xcodebuild -project Tend.xcodeproj -target Tend -showBuildSettings -json | jq -e '.[0].buildSettings.TARGETED_DEVICE_FAMILY == \"1\"' && xcodebuild -project Tend.xcodeproj -target TendTests -showBuildSettings -json | jq -e '.[0].buildSettings.TARGETED_DEVICE_FAMILY == \"1\"' && xcodebuild -project Tend.xcodeproj -target TendUITests -showBuildSettings -json | jq -e '.[0].buildSettings.TARGETED_DEVICE_FAMILY == \"1\"'" }
    required: true
  - id: C2
    statement: Live project configuration, application code, and UI tests contain no explicit iPad idiom detection, iPad-only control, tablet geometry or sheet branch, tablet screenshot path, tablet audit inventory, compatibility shim, or iPad-only skipped test, while historical Tiller work and evidence remain untouched.
    polarity: introduce
    binding: { type: manual }
    required: true
  - id: C3
    statement: The complete iPhone-only UI suite preserves Today, All Habits, Habit Detail, and Fast Logging owner journeys, exact compact-iPhone geometry, Dynamic Type, keyboard, VoiceOver audit, Reduce Motion, forced-light, persistence, Undo, and failure behavior with no device-scope waiver.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests" }
    required: true
  - id: C4
    statement: TendCore, app-unit behavior, package compilation, and the generic iOS application build remain green after the supported-device cutover.
    polarity: introduce
    binding: { type: command, run: "Scripts/tiller-swift-test && Scripts/tiller-xcode-test TendTests && swift build && xcodebuild -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build" }
    required: true
  - id: C5
    statement: A direct compact-iPhone launch reaches Today, All Habits, Habit Detail, and the quantity Log Sheet; the latter supports custom amount keyboard submit and cancel, Undo, and standard swipe dismissal without an iPad-only Close control.
    polarity: introduce
    binding: { type: manual }
    required: true
---

# Acceptance

C1 reads the effective build settings for all three targets. A passing app target
alone is insufficient because an iPad-capable UI-test target can silently retain
and execute tablet-only contracts. Review the project file with the command
result to confirm both app configurations also omit
`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` while retaining the existing
iPhone orientation list.

C2 is a bounded live-tree review over `Tend.xcodeproj/project.pbxproj`,
`App/Tend`, and `App/TendUITests`. Search case-insensitively for iPad terminology
and inspect former device branches by symbol, including `userInterfaceIdiom`,
`showsCloseButton`, `expandSheet`, `evidenceDeviceName`, `splitGroups`,
`log-sheet.close`, 1024×1366 geometry, 600.5-point sheet width, and 700-point
tablet thresholds. General readable-width and safe-area code remains valid.
Exclude `.tiller/evidence`, completed task specifications, old plans, and events
from the zero-residue claim because they are historical records.

C3 and C4 run once from the same final source/test commit. A deterministic iPhone
failure is a product or test failure to diagnose; it is never retried away or
reclassified because iPad support was removed. C3 must contain no expected
`Requires an iPad` skip.

C5 uses the configured 402×874 compact-iPhone simulator and deterministic DEBUG
stores. Record the runtime, exact fixture and injected instant, and observed
surface state. Screenshots support the observation but do not prove persistence,
keyboard focus, VoiceOver speech, Reduce Motion, or haptic character.
