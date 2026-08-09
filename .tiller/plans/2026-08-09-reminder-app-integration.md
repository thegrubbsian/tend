# Reminder App Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect local reminder permission, reconciliation refresh signals, application lifecycle, and notification response routing without changing authoritative habit or logging behavior.

**Architecture:** A process-lifetime `ReminderRoutingModel` and `ReminderNotificationDelegate` are created before the store opens. Each successfully opened `ModelContainer` gets exactly one `ReminderAppRuntime`, which retains the container-bound `ReminderCoordinator`, an authorization controller, the shared router, and the delegate; `TendApplicationModel` replaces that runtime after store recovery. Views pass two narrow closures—`ReminderRefreshSignal` and `ReminderAuthorizationRequest`—to existing models, and every model invokes the refresh signal synchronously only after an authoritative write succeeds. The shell binds its selection to the shared router so tab taps and owned notification responses use one state and one accessibility-focus handoff.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, UserNotifications, Observation, TendCore, Swift Testing, XCTest/XCUITest, Xcode 26, Tiller.

## Global Constraints

- Work only on `tiller/device-readiness/local-reminders` in `.worktrees/local-reminders`; every authored commit message includes `T-hpts9u`.
- Use one container-bound `ReminderCoordinator`; do not duplicate scheduling or notification-content logic.
- Install and retain the `UNUserNotificationCenterDelegate` before a response can arrive, including while the SwiftData store is failed.
- Never construct a container-bound runtime while the store is failed; store retry replaces the old runtime with one bound to the replacement container.
- Request only alert and sound authorization, only from the first eligible no-reminder-to-time gesture, and never from launch, foreground entry, persisted reminder loading, time edits, pin edits, or a draft that started with a reminder.
- Permission denial preserves the draft and saved reminder, produces no repeated system request, and triggers reconciliation after the request resolves.
- Every reminder refresh callback is default-no-op, nonthrowing, and invoked only after an authoritative mutation succeeds.
- Reminder refresh cannot delay Save dismissal, change haptics or animation, extend the five-second Undo window, or convert a successful write into a visible failure.
- Preserve existing failure, retry, duplicate-interaction, read-only refresh, and post-mutation projection behavior.
- Owned notification responses select Today only; they never open a sheet, choose a habit, or mutate data. Foreign responses are ignored.
- Preserve Today as the cold-launch destination, ordinary tab behavior, the existing accessibility-focus transfer, forced-light styling, copy, visual tokens, logging semantics, and iPhone-only support.
- Do not modify SwiftData models, TendCore operations, reminder planning/content, or feature acceptance attestations.

---

### Task 1: Runtime, Authorization, and Store Lifecycle

**Files:**
- Create: `App/Tend/Reminders/ReminderAppRuntime.swift`
- Create: `App/TendTests/ReminderAppIntegrationTests.swift`
- Modify: `App/Tend/Reminders/ReminderNotificationCenter.swift`
- Modify: `App/Tend/Application/TendApplicationModel.swift`
- Modify: `App/Tend/TendApp.swift`
- Modify: `App/TendTests/TendApplicationModelTests.swift`
- Modify: `App/TendTests/ReminderCoordinatorTests.swift`

**Interfaces:**
- Produces: `typealias ReminderRefreshSignal = @MainActor () -> Void` and `typealias ReminderAuthorizationRequest = @MainActor () async -> Void`.
- Produces: `@MainActor protocol ReminderRuntimeClient` with `routing`, `refresh()`, and `requestAuthorizationIfNeeded()`.
- Produces: `ReminderRuntimeFactory = @MainActor (ModelContainer) -> any ReminderRuntimeClient` and `TendApplicationReadyState(container:reminders:)`.
- Produces: a live notification-client authorization API that accepts observable alert/sound options.

- [ ] **Step 1: Add failing authorization tests**

In `ReminderAppIntegrationTests.swift`, define a main-actor fake notification client that records authorization options and deterministic status changes. Add tests equivalent to:

```swift
@Test("eligible reminder gesture requests alert and sound once then refreshes")
func eligibleGestureRequestsPermissionOnce() async throws {
  let center = FakeReminderNotificationCenter(status: .notDetermined, requestResult: false)
  let refreshes = RefreshSpy()
  let controller = ReminderAuthorizationController(
    notificationCenter: center,
    reminderRefresh: refreshes.signal
  )

  await controller.requestIfNeeded()
  await controller.requestIfNeeded()

  #expect(center.requestedOptions == [.alert, .sound])
  #expect(center.requestAuthorizationCallCount == 1)
  #expect(refreshes.count == 1)
}

@Test("determined permission does not request or refresh")
func determinedPermissionDoesNotPrompt() async {
  for status in [ReminderAuthorizationStatus.denied, .authorized, .unavailable] {
    let center = FakeReminderNotificationCenter(status: status)
    let refreshes = RefreshSpy()
    let controller = ReminderAuthorizationController(
      notificationCenter: center,
      reminderRefresh: refreshes.signal
    )
    await controller.requestIfNeeded()
    #expect(center.requestAuthorizationCallCount == 0)
    #expect(refreshes.count == 0)
  }
}
```

Assert that an authorization error does not throw into the caller or alter reminder draft state.

- [ ] **Step 2: Add failing store-lifecycle tests**

Extend `TendApplicationModelTests` using a `FakeReminderRuntime` and factory recorder:

```swift
@Test("ready store owns one runtime and starts one refresh")
func readyStoreStartsRuntime() throws {
  let container = try TendModelContainer.inMemory()
  let runtime = FakeReminderRuntime()
  let model = TendApplicationModel(
    makeContainer: { container },
    makeReminderRuntime: { received in
      #expect(received === container)
      return runtime
    }
  )

  let ready = try #require(model.readyState)
  #expect(ready.container === container)
  #expect(ready.reminders === runtime)
  #expect(runtime.refreshCount == 1)
}
```

Cover failed construction creating no runtime, retry-to-ready creating one runtime for the replacement container, a later failed retry retaining no stale ready runtime, and every explicit scene-active call producing one refresh only while ready.

- [ ] **Step 3: Verify RED**

Run:

```bash
Scripts/tiller-xcode-test TendTests/ReminderAppIntegrationTests
Scripts/tiller-xcode-test TendTests/TendApplicationModelTests
```

Expected: compilation fails because the runtime, authorization controller, option-bearing client method, ready state, and runtime factory do not exist.

- [ ] **Step 4: Implement observable authorization options**

Add an app-owned option set and update the protocol/live adapter:

```swift
nonisolated struct ReminderAuthorizationOptions: OptionSet, Equatable, Sendable {
  let rawValue: Int
  static let alert = Self(rawValue: 1 << 0)
  static let sound = Self(rawValue: 1 << 1)
}

@MainActor
protocol ReminderNotificationCenterClient: AnyObject {
  func authorizationStatus() async throws -> ReminderAuthorizationStatus
  func requestAuthorization(options: ReminderAuthorizationOptions) async throws -> Bool
  // existing pending-request methods remain unchanged
}
```

Map `.alert` and `.sound` to `UNAuthorizationOptions` only in `LiveReminderNotificationCenter`. Migrate the coordinator test fake without changing coordinator behavior.

- [ ] **Step 5: Implement the ready-only runtime**

Create the narrow contracts and concrete runtime:

```swift
typealias ReminderRefreshSignal = @MainActor () -> Void
typealias ReminderAuthorizationRequest = @MainActor () async -> Void

@MainActor
protocol ReminderRuntimeClient: AnyObject {
  var routing: ReminderRoutingModel { get }
  func refresh()
  func requestAuthorizationIfNeeded() async
}
```

`ReminderAuthorizationController.requestIfNeeded()` reads status once, requests `[.alert, .sound]` only for `.notDetermined`, suppresses overlapping requests, and calls its refresh signal once after the request resolves, regardless of grant or denial. It catches client errors and never throws into model/UI behavior.

`ReminderAppRuntime` retains one `ReminderCoordinator`, one controller, the shared `ReminderRoutingModel`, and the process delegate. Its synchronous `refresh()` launches coordinator work in a main-actor `Task`; callers never await reconciliation.

- [ ] **Step 6: Integrate runtime replacement with application state**

Replace the bare ready payload with:

```swift
struct TendApplicationReadyState {
  let container: ModelContainer
  let reminders: any ReminderRuntimeClient
}

enum TendApplicationState {
  case ready(TendApplicationReadyState)
  case failed
}
```

Require `makeReminderRuntime` in `TendApplicationModel.init`. In `openStore`, create the container first, create exactly one runtime only after that succeeds, publish ready state, then signal the initial refresh. On any container failure publish `.failed`, clearing the previous ready payload. Add `sceneDidBecomeActive()` which signals only the current ready runtime.

In `TendApp`, create and retain the shared router and notification delegate before constructing the application model, assign the delegate to `UNUserNotificationCenter.current()`, and inject a runtime factory using the same notification center. Observe `scenePhase` at the application root and call `sceneDidBecomeActive()` for `.active` transitions.

- [ ] **Step 7: Verify GREEN and commit**

Run the two Task 1 suites plus `TendTests/ReminderCoordinatorTests`. Commit runtime/lifecycle production and tests with `T-hpts9u` in the message.

---

### Task 2: Habit Form Permission Gesture and Save Refresh

**Files:**
- Modify: `App/Tend/Habits/HabitFormModel.swift`
- Modify: `App/Tend/Habits/HabitFormView.swift`
- Modify: `App/TendTests/HabitFormModelTests.swift`
- Modify: `App/TendTests/ReminderAppIntegrationTests.swift`

**Interfaces:**
- Consumes: `ReminderRefreshSignal` and `ReminderAuthorizationRequest` from Task 1.
- Produces: `HabitFormModel.setReminderEnabled(_:) -> Bool`, where `true` means this exact user gesture is eligible to check authorization.

- [ ] **Step 1: Add failing gesture-provenance tests**

Cover a new draft returning `true` only on its first nil-to-time gesture; clearing and enabling again returns `false`; a draft loaded with a persisted reminder never returns `true`, even after clear/re-enable; time and pin edits do not call the authorization closure. Assert denial leaves `reminderTime` populated and `canSave == true`.

- [ ] **Step 2: Add failing save-signal tests**

Extend existing persistence-spy tests:

```swift
@Test("successful create and update signal reminder refresh once")
func successfulSavesSignalOnce() throws {
  // Exercise .new and .edit through the real HabitFormModel.save boundary.
  // Assert create/update persisted once and refreshCount == 1 per success.
}
```

Also assert invalid configuration, validation refusal, and persistence throw signal zero times; retry signals only after the successful attempt.

- [ ] **Step 3: Verify RED**

Run `Scripts/tiller-xcode-test TendTests/HabitFormModelTests`; expect missing initializer/callback behavior or wrong signal counts.

- [ ] **Step 4: Implement form seams**

Store whether the draft started with a valid reminder and whether its first eligible enable gesture has been consumed. Return the eligibility result from `setReminderEnabled`. Inject a default-no-op refresh closure into `HabitFormModel`; call it immediately after successful create/update and before returning the saved habit.

Inject both narrow closures into `HabitFormView`. The existing None button calls `setReminderEnabled(true)` and launches a `Task` for authorization only when it returns true. Keep Save synchronous: persistence succeeds, refresh is signaled, `onSaved()` runs, and dismissal follows without awaiting permission or reconciliation. Cancel remains unchanged.

- [ ] **Step 5: Verify GREEN and commit**

Run `TendTests/HabitFormModelTests` and `TendTests/ReminderAppIntegrationTests`. Commit with `T-hpts9u` in the message.

---

### Task 3: Habit Roster and Detail Mutation Refresh

**Files:**
- Modify: `App/Tend/Habits/HabitRosterModel.swift`
- Modify: `App/Tend/Habits/HabitDetailModel.swift`
- Modify: `App/TendTests/HabitRosterModelTests.swift`
- Modify: `App/TendTests/HabitDetailModelTests.swift`

**Interfaces:**
- Consumes: default-no-op `ReminderRefreshSignal`.
- Preserves: existing retry state, duplicate guards, deletion confirmation, reload failures, edit completion, and lifecycle result types.

- [ ] **Step 1: Add failing roster tests**

For archive, reactivation, archive-instead-of-delete, retry success, and confirmed deletion, assert one refresh signal immediately after the successful operation. Assert duplicate dispatch, operation failure, and read-only roster refresh signal zero; failure then retry signals only on retry success. Configure the refresh spy to be nonthrowing and independent of roster reload failure.

- [ ] **Step 2: Add failing detail tests**

For archive, reactivation, and editable-entry `.deleted`, assert one signal. Assert ineligible/reentrant actions, operation failure, and delete result `.missing` signal zero. Preserve the existing successful-write/post-mutation-projection-failure behavior while still signaling after the committed write.

- [ ] **Step 3: Verify RED**

Run roster and detail model suites; expect missing callback parameters or zero observed signals on successful mutations.

- [ ] **Step 4: Implement minimal callbacks**

Add the default-no-op callback to production and test initializers. In `HabitRosterModel.performMutation`, invoke it once after the successful lifecycle/delete operation and before roster reload. In `HabitDetailModel.perform`, invoke it after archive/reactivation; for entry deletion invoke only when the returned result is `.deleted`, never `.missing`, and before month re-projection.

- [ ] **Step 5: Verify GREEN and commit**

Run both model suites. Commit with `T-hpts9u` in the message.

---

### Task 4: Today Logging Mutation Refresh

**Files:**
- Modify: `App/Tend/Today/TodayLoggingModel.swift`
- Modify: `App/TendTests/TodayLoggingModelTests.swift`

**Interfaces:**
- Consumes: default-no-op `ReminderRefreshSignal`.
- Preserves: exact `times` fast path, quantity editor, current/grace authorization, feedback, haptics, Undo deadline, and existing error mapping.

- [ ] **Step 1: Add failing current/grace, set-total, delete, and Undo tests**

Use the existing stateful operation fake. Assert one signal for successful current append, weekly grace append, quantity append, changed set-total, entry deletion, and Undo. Assert zero for ineligible or duplicate taps, unchanged set-total (`nil` mutation), mutation failure, expired/missing Undo, and read-only refresh. Assert failure then retry signals only after success.

Add a post-write projection-failure case proving a committed write still signals once while the existing user-facing projection error remains unchanged. Assert signal ordering occurs after the write but before feedback/Undo publication, without altering the five-second deadline.

- [ ] **Step 2: Verify RED**

Run `Scripts/tiller-xcode-test TendTests/TodayLoggingModelTests`; expect missing callback or zero signals.

- [ ] **Step 3: Implement exact write seams**

Inject the callback into both Today logging initializers. Signal immediately after successful writes in `performEntryMutation`, direct one-count `appendOne`, `deleteEntry`, and `undo`. Do not signal after snapshots/projections and do not wrap the signal in persistence error handling.

- [ ] **Step 4: Verify GREEN and commit**

Run `TendTests/TodayLoggingModelTests`. Commit with `T-hpts9u` in the message.

---

### Task 5: Shared Routing, Delegate, and View Composition

**Files:**
- Create: `App/Tend/Application/ReminderRoutingModel.swift`
- Create: `App/Tend/Reminders/ReminderNotificationDelegate.swift`
- Modify: `App/Tend/TendRootView.swift`
- Modify: `App/Tend/Shell/AlmanacShellView.swift`
- Modify: `App/Tend/Shell/TodayDestinationChrome.swift`
- Modify: `App/Tend/Shell/HabitsDestinationChrome.swift`
- Modify: `App/Tend/Today/TodayView.swift`
- Modify: `App/Tend/Habits/HabitRosterView.swift`
- Modify: `App/Tend/Habits/HabitDetailView.swift`
- Modify: `App/TendTests/ReminderAppIntegrationTests.swift`
- Modify: `App/TendUITests/AlmanacShellUITests.swift` only if existing owner-visible assertions need a narrow regression extension.

**Interfaces:**
- Produces: `@MainActor @Observable final class ReminderRoutingModel` with `selection: ShellDestination = .today` and a direct owned-response handler.
- Produces: process-retained `ReminderNotificationDelegate` projecting `UNNotificationResponse` into the routing model on the main actor.
- Consumes: `ReminderRuntimeClient` and passes its method references through the existing view hierarchy.

- [ ] **Step 1: Add failing routing tests**

In `ReminderAppIntegrationTests`, construct the router directly. Set selection to `.habits`, send an identifier with `ReminderPlanner.identifierPrefix`, required category, and ownership marker, then assert `.today`. Cover cold default `.today`, a response received before any ready container, and foreign identifier/category/marker combinations remaining `.habits`.

Add a fake runtime composition test proving ordinary selection writes and notification route writes mutate the same `ReminderRoutingModel`. Existing `AlmanacShellUITests` remain the owner-visible proof for cold launch, tab selection, selected traits, relaunch, and foreground focus behavior.

- [ ] **Step 2: Verify RED**

Run `TendTests/ReminderAppIntegrationTests`; expect missing router/delegate and shared binding.

- [ ] **Step 3: Implement router and delegate**

The router accepts projected response facts and requires all Tend ownership facts before selecting Today:

```swift
func routeNotificationResponse(
  identifier: String,
  categoryIdentifier: String,
  hasOwnershipMarker: Bool
) {
  guard identifier.hasPrefix(ReminderPlanner.identifierPrefix),
    categoryIdentifier == ReminderPendingRequest.requiredCategoryIdentifier,
    hasOwnershipMarker
  else { return }
  selection = .today
}
```

The delegate extracts those facts from `response.notification.request`, hops to `@MainActor`, invokes the router, and always calls the response completion handler. It performs no data mutation and no navigation beyond setting the shared shell destination.

- [ ] **Step 4: Wire the single dependency path**

`TendRootView` accepts the ready runtime. `AlmanacShellView` accepts the runtime router rather than owning private `@State`, derives a binding for `FloatingTabPill`, and retains the existing `onChange` accessibility-focus assignment. Pass runtime refresh and authorization methods through `TodayDestinationChrome`, `HabitsDestinationChrome`, `TodayView`, `HabitRosterView`, `HabitDetailView`, and every `HabitFormView` construction. Do not introduce a parallel environment dependency convention.

- [ ] **Step 5: Verify GREEN and regressions**

Run:

```bash
Scripts/tiller-xcode-test TendTests/ReminderAppIntegrationTests
Scripts/tiller-xcode-test TendTests/HabitFormModelTests
Scripts/tiller-xcode-test TendTests/HabitRosterModelTests
Scripts/tiller-xcode-test TendTests/HabitDetailModelTests
Scripts/tiller-xcode-test TendTests/TodayLoggingModelTests
Scripts/tiller-xcode-test TendUITests/AlmanacShellUITests
```

Expected: all pass; shell destination identifiers and selected accessibility traits remain unchanged.

- [ ] **Step 6: Build and smoke test**

Run the generic iOS build from the task contract. If the owner iPhone is connected, install the development build, reset notification permission, and execute the exact delivery/suppression/routing/denial scenario from `task.md` lines 100-105. Record observed evidence; never substitute a simulator for real delivery evidence.

- [ ] **Step 7: Run Tiller gates, review, and submit**

Commit production/test changes with `T-hpts9u`, run `tiller check task device-readiness/local-reminders/reminder-app-integration --owner jc`, commit the resulting `.tiller` state, request an independent code review over the complete task diff, fix all valid findings and rerun affected gates, open a task PR whose body names `device-readiness/local-reminders (F-zbcv8j)`, run `tiller submit task ... --pr <number> --owner jc`, commit and push the review-state delta, then render `tiller readout execute`. Stop at `in_review`; do not attest human gates or merge.
