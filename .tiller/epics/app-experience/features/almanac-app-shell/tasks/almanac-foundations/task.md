# Implement the Almanac visual foundations

## Approach

Implement the reusable Almanac vocabulary inside the Tend app target created by
app-experience/almanac-app-shell/ios-application-composition (T-9vxtaq). Keep
tokens in focused Swift files and use them from views; do not reproduce hex
values, font choices, or spacing literals at call sites.

Define `AlmanacPalette` as exact sRGB color values for paper, paper-raised,
paper-sunken, ink, ink-muted, ink-faint, hairline, moss, moss-deep, clay,
clay-deep, ochre, ochre-deep, and withered. Use a small internal sRGB value type
to make the source values explicit, then expose SwiftUI `Color` values from
those definitions. Do not use semantic system colors for these normative roles.

Define `AlmanacMetrics` with spacing values 8/16/24/40, 20-point screen
padding, radii 14/10/7/36, a 62-point tab-pill height, and the 44-point minimum
target. Metrics that belong to later components remain with those components;
do not turn this into a catch-all constants file.

Define relative Dynamic Type typography rather than fixed-size custom fonts.
The permanent interfaces are:

- `AlmanacTextStyle.screenTitle`
- `AlmanacTextStyle.body`
- `AlmanacTextStyle.secondary`
- `AlmanacTextStyle.label`
- `AlmanacTextStyle.caption`
- `AlmanacTextStyle.meaningfulNumeral(_ relativeStyle: Font.TextStyle)`
- `View.almanacTextStyle(_:)`

Screen titles and meaningful numerals use the system serif design that maps to
New York on iOS; numerals add monospaced digits. Body styles remain the system
sans face. Labels are uppercase, semibold, and tracked. Keep the definitions
compatible with Dynamic Type and do not hard-code the comp's specimen sizes as
non-scaling fonts.

Add narrow raised and sunken surface modifiers. Raised surfaces provide only
paper-raised fill, their requested radius, and the 1-point hairline. Sunken
surfaces provide only paper-sunken fill and their requested radius. Neither may
apply a shadow. Add a screen-container style that fills safe areas with paper,
uses ink by default, and centers an optional readable-width content column
without introducing screen-specific layout.

Create the app asset catalog, its AccentColor role, and `Sprout.symbolset`.
Author the sprout as a valid monochrome custom-symbol SVG whose layers inherit
foreground style and symbol weight. Validate it in the built app. If Xcode's
custom-symbol validation rejects the asset after a concrete correction attempt,
use `leaf` through the single `AlmanacIcon.today` mapping and record that
sanctioned departure in the task readout; do not leave both paths selected by
runtime conditionals.

Apply the foundations to the existing permanent views. `TendRootView` becomes a
paper screen with a correctly styled Today title while retaining its owned
composition boundary. `StoreFailureView` uses Almanac title/body/primary-action
styles, the exact approved copy, a 44-point Retry action, deep accessible text
where applicable, and no decorative error color or shadow. Set the app target's
`UIUserInterfaceStyle` Info.plist value to `Light` at build time; do not rely
only on a view-local preferred color scheme that system presentations can
escape.

## Surfaces

- Create `App/Tend/Almanac/AlmanacPalette.swift`.
- Create `App/Tend/Almanac/AlmanacMetrics.swift`.
- Create `App/Tend/Almanac/AlmanacTypography.swift`.
- Create `App/Tend/Almanac/AlmanacSurface.swift`.
- Create `App/Tend/Almanac/AlmanacIcon.swift`.
- Create `App/Tend/Assets.xcassets/Contents.json`.
- Create `App/Tend/Assets.xcassets/AccentColor.colorset/Contents.json`.
- Create `App/Tend/Assets.xcassets/Sprout.symbolset/Contents.json` and its
  monochrome SVG.
- Modify `App/Tend/TendApp.swift`,
  `App/Tend/Application/StoreFailureView.swift`, and
  `App/Tend/TendRootView.swift` to consume the foundations.
- Modify the Xcode project only to attach the asset catalog or new source files
  if the chosen project group is not filesystem-synchronized.
- Do not modify the Pencil comp, TendCore, persistence schema, or domain tests.

## Tests

For this visual change, verification is the built app rather than a test that
repeats source constants. Build the app first, launch it in an iOS 26 simulator,
exercise both the ready and injected failure previews/tests, and capture the
Today title and startup failure surfaces in light appearance. Compare palette,
New York/SF Pro roles, label tracking, paper surfaces, hairlines, spacing, and
absence of shadows against the Almanac Foundations board in
`.tiller/design/comps/tend.pen`.

Run the preceding application-model tests, the cold-launch UI smoke test, the
complete TendCore suite and Swift build, and the generic iOS Tend app build.
Check Dynamic Type at the default size and two larger steps. Verify the failure
copy wraps without truncation on the smallest supported iPhone width and the
Retry target remains at least 44 points.

## Edge cases

- Color construction must use sRGB rather than display-dependent generic RGB.
- Small clay and ochre text always chooses clay-deep or ochre-deep; base hues
  remain valid for fills, strokes, dots, and numerals at least 20 points.
- New York and SF Pro are system faces; never bundle font files or use the
  Pencil stand-ins Lora and Inter.
- Meaningful numerals carry monospaced digits, while prose does not.
- Dynamic Type may increase text height but may not silently clip or ellipsize
  the owner-facing failure copy.
- Forced light appearance applies to sheets and alerts inherited from this
  root, not only the first screen background.
- The custom symbol must render as a template at every tab weight. No raster
  sprout or multicolor asset is acceptable.
- The palette and surface APIs stay app-internal until another product needs a
  stable public UI module.
