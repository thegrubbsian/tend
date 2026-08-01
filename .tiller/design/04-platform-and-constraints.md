# 04. Platform and Constraints

## Technology selections

These are product decisions, made deliberately:

- **Platform**: iOS, native. iPhone is the primary device. The app is universal and must run acceptably on iPad, but v1 requires no iPad-specific layouts; the iPhone experience adapting reasonably is enough.
- **Minimum OS**: iOS 26. This is a single-user personal app on a device that stays current, so the deployment target tracks the latest major release and the build uses the current toolchain (Xcode 26, Swift 6 language mode).
- **UI framework**: SwiftUI.
- **Persistence**: SwiftData, on-device.
- **Dependencies**: no third-party runtime dependencies without explicit owner approval. Apple's frameworks cover everything this product needs, and a personal app should stay light enough to rebuild in a weekend.


How the codebase is organized, what patterns it uses, and how the work is sequenced are engineering decisions and are intentionally not specified here.

## Data requirements

- **All data lives on the device.** No server component exists. No network calls, no analytics, no telemetry, no crash reporting to third parties. The app should function identically in airplane mode forever.
- **Sync-ready shape.** Device-to-device sync via CloudKit is a plausible future. The persistent model must be structured so that adopting CloudKit sync later does not require destructive migration of existing data. This constrains model design now (in the ways Apple documents for CloudKit-compatible SwiftData models) without adding any sync behavior in v1.
- **Durability.** Log entries and bucket records are the user's history and the whole value of the product. Writes must be safe against app termination; a force-quit immediately after logging must not lose the entry.
- **History is unbounded.** The model and queries should assume years of daily entries across a dozen habits without degrading. This is small data by any real measure; treat it that way and don't add complexity for scale that will never come.


## Quality requirements

- **The domain rules are deterministic and fully unit-tested.** Every rule in [02-domain-model.md](02-domain-model.md), including all worked examples and each decision note, must be covered by automated tests that run without a device or simulator UI. Bucket boundaries, grace expiry, verdict settlement, requirement snapshots, streak chains across inactive gaps, and the at-risk state are the behaviors the whole product stands on; they must be provably correct, not visually spot-checked.
- **Time is testable.** Bucket and streak logic must be verifiable at arbitrary points in time (midnight boundaries, DST transitions, week rollovers) without waiting for wall-clock time to pass. However the engineering team achieves that, the tests must exercise those boundaries directly.
- **Responsiveness.** Logging from Today reflects instantly. No spinners exist anywhere in v1; nothing the app does justifies one.
- **Reminder correctness.** Scheduled reminders fire at their times and are suppressed when the bucket is already met, verified on a real device as part of the release criteria.


## Privacy posture

Everything the user records stays on the device, full stop. No account, no identifier, no data leaves the phone. This isn't a compliance stance; it's the product. A tool for private self-honesty earns that honesty by having no audience.

## Distribution

Tend is installed directly onto the owner's iPhone through personal developer provisioning. There is no App Store presence, no TestFlight audience, and no release process beyond building and installing. The release criteria in [01-overview.md](01-overview.md) define what v1.0.0 means.