# Almanac App Shell

## Summary

Create Tend's native iOS application target and the reusable Almanac shell that
future app-experience features build inside. The result launches against the
real on-device SwiftData store, presents honest recovery if that store cannot
open, and provides accessible Today/Habits destination chrome in the normative
Almanac visual language.

This feature owns application composition, visual foundations, and root
navigation. It does not query or mutate habits, render dashboard cards or
rosters, offer creation or logging actions, or infer behavior owned by dependent
features.

## Application architecture

Commit a native `Tend.xcodeproj` with a shared `Tend` scheme, an iOS application
target, an app-unit-test target, and a UI-test target. The app is universal,
requires iOS 26, uses Swift 6, imports the repository's local `TendCore` package
product, and uses the stable bundle identifier `com.jcgrubbs.tend`. Keep
SwiftUI and app-lifecycle code in the app target; do not add a `TendUI` package,
framework target, project generator, or third-party dependency.

`TendApp` creates `TendModelContainer.production()` and attaches the resulting
container at the application root. A main-actor application model owns the
container factory and exactly two observable outcomes:

- **Ready:** the real production `ModelContainer` is injected into the shell.
- **Failed:** the app renders a dedicated startup failure surface and retains
  enough diagnostic information for local debugging.

Container creation is synchronous, so there is no loading state and no spinner.
The failed surface says, “Tend couldn't open your garden.” and “Your records
were not changed. Try again.”, then offers a 44-point **Retry** action. Retry
calls the same production factory again. Never substitute an in-memory store,
discard the error, create a second production store, or enter the shell without
a valid container. Raw error details may go to the local unified log but never
to telemetry or user-facing copy.

## Almanac foundations

Implement one reusable source of truth in the app target for the visual grammar
defined by `.tiller/design/05-visual-design.md` and
`.tiller/design/comps/tend.pen`.

- Color roles use the exact comp values: paper `#F7F2E7`, paper-raised
  `#FCF9F1`, paper-sunken `#EDE6D6`, ink `#2B2A26`, ink-muted `#6F6A5E`,
  ink-faint `#A79F8F`, hairline `#E6DEC9`, moss `#3D5A3D`, moss-deep
  `#2F462F`, clay `#C1704F`, clay-deep `#A4573C`, ochre `#D9A441`,
  ochre-deep `#9C7414`, and withered `#8A6A52`.
- Typography maps display text and meaningful numerals to the system New York
  face, all other text to SF Pro, and numerals to monospaced digits. Use
  relative Dynamic Type styles rather than fixed custom-font sizes.
- Spacing tokens are 8, 16, 24, and 40 points. Screen horizontal padding is
  20 points. Cards use radius 14, inset fields radius 10, garden cells radius 7,
  and the tab pill radius 36.
- Raised and sunken surface styles use color shifts plus the 1-point hairline;
  no drop shadow exists anywhere.
- Small clay or ochre text uses its deep variant. Base hues remain available
  for fills, strokes, dots, and numerals at least 20 points.
- The app declares light appearance and renders the paper palette regardless of
  system appearance.

Create an asset catalog containing the app accent role and a custom sprout
symbol compatible with SF Symbol rendering modes and weights. The Today tab
uses that custom symbol. `leaf` is the sanctioned fallback only if the custom
symbol cannot be made valid in the current asset toolchain; use one icon path,
not device- or state-specific alternatives.

## Destination shell

The root shell owns a two-case destination value: Today and Habits. A cold
process launch always initializes it to Today. Selection remains stable while
the scene backgrounds and foregrounds, but it is not persisted across process
launches.

Both destinations render full-screen paper and real, intentionally limited
chrome:

- **Today:** the owner's localized current date as an uppercase tracked eyebrow
  and the New York screen title “Today”.
- **Habits:** the New York screen title “Habits”.

Do not add model queries, first-launch copy, a create button, disabled controls,
 sample data, empty-state placeholders, cards, roster rows, or navigation
destinations that this feature cannot complete. app-experience/habit-management
and app-experience/today-dashboard own those bodies and actions.

Render navigation as the custom floating pill from the comps, not native tab
bar chrome:

- 62-point height, radius 36, paper-raised fill, 1-point hairline.
- At least 21 points from the horizontal and bottom safe-area edges.
- Two equal destinations. The active destination is a solid moss capsule with
  paper icon and uppercase label; the inactive destination is transparent with
  faint ink.
- Today uses the sprout symbol and Habits uses `list.bullet`.
- Each destination is a semantic button with a 44-point minimum target, a
  VoiceOver label, selected-state traits, and a stable UI-test identifier.

On compact iPhone layouts the shell follows the 402-point reference geometry
proportionally through safe-area and flexible-width layout rather than fixed
screen coordinates. On iPad, keep paper full-screen while centering destination
content and the pill at readable maximum widths; do not stretch either across
the entire display and do not introduce an iPad-only navigation model.

The shell needs no custom animation. Any incidental destination transition must
respect Reduce Motion. The fixed-height pill and symbols keep their geometry
while text scales through two Dynamic Type steps without truncation. User-owned
text is absent from this feature, so destination labels must never ellipsize.

## Verification

Add a repository script that selects an available iOS 26 simulator and runs a
named app-unit or UI-test target without relying on a developer's booted-device
state.

App-unit tests use an injected container factory to prove:

- successful startup retains and exposes exactly the produced container;
- failed startup enters the failure state without a fallback;
- Retry invokes the same factory once per attempt and can recover to ready;
- repeated rendering does not create additional containers.

UI tests prove:

- a cold launch shows Today selected;
- each pill button has the expected label, identifier, and selected semantics;
- tapping Habits switches the destination and updates selection;
- background/foreground preserves selection;
- terminating and relaunching initializes Today again.

Manual feature acceptance compares the foundations and floating pill against
the Almanac Foundations, Today, and All Habits comp boards on a compact iPhone
and iPad. A second manual pass verifies Dynamic Type through two larger steps,
VoiceOver labels and selection, 44-point targets, deep-variant contrast, forced
light appearance, and Reduce Motion behavior.

## Ownership and non-goals

This feature may add the Xcode project, app/test sources, asset catalog, and
app-specific verification script. It consumes `TendModelContainer` and
`TendSchemaV1` through the existing `TendCore` product without changing their
ownership.

No persistence schema, domain operation, habit query, lifecycle action, logging
action, dashboard or roster body, detail navigation, form, notification,
haptic, dark appearance, network call, analytics path, app-store packaging, or
release-device evidence belongs here.
