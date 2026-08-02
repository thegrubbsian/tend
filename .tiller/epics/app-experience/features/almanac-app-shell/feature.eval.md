---
node: F-tm2imn
criteria:
  - id: C1
    statement: The committed Tend iOS application and shared scheme build for a generic iOS device at the project's iOS 26 and Swift 6 floor while linking the local TendCore product.
    polarity: introduce
    binding: { type: command, run: "xcodebuild -project Tend.xcodeproj -scheme Tend -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build" }
    required: true
  - id: C2
    statement: Application composition opens exactly the production SwiftData container, exposes it to the ready shell, and on failure shows an honest retryable state that never substitutes in-memory persistence or creates extra containers during rendering.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendTests/TendApplicationModelTests" }
    required: true
  - id: C3
    statement: A cold launch selects Today; the accessible floating pill switches between Today and Habits, preserves selection across scene backgrounding, and returns to Today only after process relaunch.
    polarity: introduce
    binding: { type: test, run: "Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests" }
    required: true
  - id: C4
    statement: On compact iPhone and iPad, the paper background, startup failure and destination chrome, exact color roles, typography, surfaces, custom icons, spacing, and 62-point floating pill match the Almanac Foundations, Today, and All Habits boards in .tiller/design/comps/tend.pen without native tab-bar chrome or shadows.
    polarity: introduce
    binding: { type: manual }
    required: true
  - id: C5
    statement: The shell remains legible through two larger Dynamic Type steps, exposes correct VoiceOver labels and selected traits, keeps every target at least 44 points, uses deep clay and ochre for small text, forces light appearance, and honors Reduce Motion.
    polarity: introduce
    binding: { type: manual }
    required: true
---

# Acceptance

C1 establishes that the repository now produces a native Tend application rather
than only the TendCore package. C2 owns the persistence-composition boundary and
the approved no-fallback startup recovery. C3 owns root navigation behavior and
its automation surface. C4 binds visual fidelity to the normative comp boards;
C5 binds the accessibility and appearance rules that screenshots alone cannot
prove.

All five criteria are satisfiable inside app-experience/almanac-app-shell
(F-tm2imn). Habit queries, first-launch creation, dashboard and roster content,
logging, detail navigation, notification behavior, haptics, distribution, and
release-device evidence stay with the features that can complete those
contracts.
