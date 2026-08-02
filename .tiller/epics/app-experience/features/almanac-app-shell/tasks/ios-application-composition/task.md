# Create the native iOS application composition

## Approach

Add a committed `Tend.xcodeproj` directly, without XcodeGen, Tuist, a workspace,
or a new framework. Define a shared `Tend` scheme with the `Tend` universal iOS
26 app target, `TendTests` app-unit target, and `TendUITests` UI target. Use
Swift 6, the bundle identifier `com.jcgrubbs.tend`, generated Info.plist
metadata where practical, and a local Swift package reference to the repository
root so the app imports the existing `TendCore` product.

Create `Scripts/tiller-xcode-test` as the stable app-test entry point used by the
feature contract. It accepts one `xcodebuild -only-testing` selector, prefers an
already-booted iOS 26 iPhone simulator, otherwise boots the first available iOS
26 iPhone and waits for boot completion, then runs the shared Tend scheme. It
must report the selected destination, preserve `xcodebuild`'s exit status, and
fail clearly when Xcode 26 or an eligible simulator is absent. Do not pin a
developer-specific simulator UUID.

Build application startup test-first around these permanent interfaces:

- `typealias ModelContainerFactory = @MainActor () throws -> ModelContainer`
- `enum TendApplicationState { case ready(ModelContainer); case failed }`
- `@MainActor @Observable final class TendApplicationModel`
- `init(makeContainer: @escaping ModelContainerFactory =
  TendModelContainer.production)`
- `private(set) var state: TendApplicationState`
- `private(set) var diagnosticError: Error?`
- `func retry()`

Initialization invokes the factory once. Success stores that exact container and
clears diagnostics. Failure stores no container, records the error only for
local diagnostics, and enters `.failed`. `retry()` invokes the same captured
factory exactly once per call and replaces the state atomically with the next
success or failure. Reading state or rendering a view never invokes the factory.
Keep the type on the main actor; do not wrap synchronous SwiftData creation in a
task or invent a loading state.

`TendApp` owns one `TendApplicationModel` for the process. In `.ready`, attach
the returned container with SwiftUI's model-container environment at the root
and render the permanent `TendRootView`. In `.failed`, render
`StoreFailureView`. That surface contains the exact approved title, body, and
Retry action; the action calls `model.retry()`. It must not construct or receive
an in-memory container. Log the diagnostic locally if useful, but add no
telemetry.

At this task boundary `TendRootView` renders only the real Today destination
title needed to prove a ready launch; it contains no “coming soon” copy, sample
data, disabled control, or action. The dependent Almanac and shell tasks retain
this composition root and replace its body with the final styled destination
shell.

## Surfaces

- Create `Tend.xcodeproj/project.pbxproj` with app, app-unit, and UI-test targets
  plus the local TendCore product dependency.
- Create `Tend.xcodeproj/xcshareddata/xcschemes/Tend.xcscheme`.
- Create `App/Tend/TendApp.swift` for process-owned startup composition.
- Create `App/Tend/Application/TendApplicationModel.swift` for the injected
  production-container state machine.
- Create `App/Tend/Application/StoreFailureView.swift` for the retryable failure
  surface.
- Create `App/Tend/TendRootView.swift` as the permanent ready composition root.
- Create `App/TendTests/TendApplicationModelTests.swift`.
- Create `App/TendUITests/TendLaunchUITests.swift` for a real cold-launch ready
  smoke test.
- Create `Scripts/tiller-xcode-test`.
- Do not change Package.swift, TendSchema, persistence models, or existing
  TendCore tests.

## Tests

Start with failing `TendApplicationModelTests` covering factory call count,
container object identity, diagnostic clearing, initial failure, repeated
failure, and failure-then-success retry. Use real in-memory containers only as
objects returned by the injected test factory; this is dependency injection,
not a production fallback. Include a test that reads state repeatedly and
confirms the call count remains one.

Run `Scripts/tiller-xcode-test TendTests/TendApplicationModelTests`, then the
cold-launch UI smoke check, the complete existing `Scripts/tiller-swift-test`,
`swift build`, and:

`xcodebuild -project Tend.xcodeproj -scheme Tend -destination
'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

The app-unit tests must observe behavior and container identity rather than
source text, Xcode project text, or implementation-private names.

## Edge cases

- A first failure followed by success must clear the old diagnostic and attach
  only the recovered container.
- Repeated failures replace the diagnostic without retaining multiple
  containers or retry tasks.
- SwiftUI body recomputation and scene activation must not reopen the store.
- The failure surface never exposes a file path or raw SwiftData error to the
  owner.
- Tests may inject in-memory containers; the production default may not.
- Generic device builds disable signing for CI evidence only. Do not bake
  signing-disabled settings into the distributable target.
- The project and script use relative repository paths and shared schemes; no
  user data, DerivedData path, simulator UUID, or local developer team enters
  version control.
