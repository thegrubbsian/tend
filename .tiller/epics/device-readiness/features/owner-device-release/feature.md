# Owner Device Release

## Summary

Tend v1 ships as a native iPhone-only application under
`.tiller/decisions/2026-08-06-iphone-only.md`. This feature is the forward owner
of the supported-device contract: it removes native iPad targeting and every
live iPad-specific production or test path while preserving the responsive,
accessible iPhone experience already built by App Experience.

The cutover supersedes device-support promises forward. It does not rewrite
completed work or `app-experience/today-dashboard/today-dashboard-acceptance`
(T-m66b11), whose iPad evidence remains truthful history.

## Behavior

The `Tend`, `TendTests`, and `TendUITests` targets declare device family `1` in
Debug and Release. The app retains its existing iPhone portrait, landscape-left,
and landscape-right orientations and removes the iPad-specific orientation
override.

Live application and UI-test code contain no explicit iPad idiom detection,
iPad-only Close control, tablet sheet expansion, tablet geometry branch,
tablet-named screenshot path, tablet audit inventory, or iPad-only skipped test.
These paths are deleted rather than hidden behind a flag or preserved as a
compatibility shim.

General SwiftUI adaptation remains. Safe-area layout, flexible widths,
`AlmanacMetrics.readableContentWidth`, Dynamic Type reflow, keyboard avoidance,
VoiceOver behavior, Reduce Motion, forced-light appearance, and iPhone landscape
support are not tablet features and must not be narrowed during the cutover.

The final supported-device proof runs the complete TendCore, app-unit, and
iPhone UI suites from one tested commit, builds the generic iOS application, and
directly exercises Today, All Habits, Habit Detail, and quantity logging on the
named compact iPhone runtime. Build-setting evidence and a live-code residue
review accompany the behavioral run.

## Boundaries

- Do not change TendCore domain behavior, SwiftData schema, fixtures, logging
  semantics, Almanac tokens, bundle identity, minimum OS, or dependency policy.
- Do not touch done task specifications, completed plans, prior events, or
  historical evidence.
- Do not modify
  `app-experience/today-dashboard/today-dashboard-acceptance` (T-m66b11) while
  it remains in review.
- Do not use the scope reduction to waive an iPhone failure. The Fast Logging
  replacement task owns its existing `SET WEEK TOTAL` contrast finding.
- Reintroducing native iPad support requires a new product decision,
  specification, adaptive implementation, tests, and device-specific evidence.
