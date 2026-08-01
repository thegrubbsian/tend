# Create the TendCore package foundation

Create the buildable Swift package and the persisted value vocabulary that every
model in this feature shares.

## Approach

- Add a dependency-free `TendCore` library package using Swift tools 6, Swift 6
  language mode, and iOS 26 as the product platform.
- Add macOS 26 only as a device-free test host; do not create a macOS executable
  or product.
- Define scalar-backed value types for cadence, bucket verdict, pinned weekdays,
  and local reminder time. Persisted representations remain strings or integers
  with stable documented meanings so later schema versions can decode them.
- Keep the package free of app navigation, SwiftUI views, repositories, and
  domain engines.

## Surfaces

- `Package.swift`
- `Sources/TendCore/Persistence/ModelValues.swift`
- `Tests/TendCoreTests/Persistence/ModelValueTests.swift`

## Tests

- Add Swift Testing coverage for cadence and verdict raw-value round trips,
  every weekday bit, empty and multi-day masks, and local reminder minute
  boundaries.
- Run `swift test`.
- Build `TendCore` for a generic iOS device with `xcodebuild`.
- Verify `swift package show-dependencies --format json` reports no dependency.

## Edge cases

- Keep persisted raw values stable and fail explicitly on unknown values rather
  than silently mapping them to a valid case.
- Represent reminder time without a date or time zone and reject values outside
  `00:00...23:59`.
- Keep the package manifest usable from a clean checkout with no generated
  project or package-resolution file.
