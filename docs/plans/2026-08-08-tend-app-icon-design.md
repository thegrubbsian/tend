# Tend App Icon Design

## Goal

Ship the approved **Sprout & Sun** graphic as Tend's native iPhone app icon without changing the graphic's character or introducing a second design source.

## Approved source

The source artwork is `Tile 06 · SPROUT & SUN` in the companion design file `../tend-design/tend-app-icons.pen`.

Its visual elements are:

- parchment background: `#F7F2E7`
- terracotta sun: `#C1704F`
- soft gray cloud: `#D5D6D2`
- moss sprout: `#3D5A3D`
- layer order: sun, cloud, sprout

The selected comp's proportions and relative positions remain unchanged.

## Production artwork

Add a dedicated `Production Export · SPROUT & SUN` frame beside the concept board in the Pencil design file. The frame is a 1024×1024 vector composition derived directly from the approved 160×160 comp.
Scale every child position and dimension uniformly by 6.4 so the production frame preserves the comp's geometry exactly.

The production frame differs from the preview tile in only two ways:

- its parchment background fills the square edge to edge
- it has no baked corner radius, border, shadow, gradient, or text

Apple applies the device-specific app icon mask. Baking the preview tile's 36 px radius into the image would create a smaller, double-rounded icon.

## Tend asset catalog integration

Create `App/Tend/Assets.xcassets/AppIcon.appiconset` containing:

- `AppIcon.png`, one 1024×1024 PNG exported from the production frame
- `Contents.json`, with one image entry using filename `AppIcon.png`, idiom `universal`, platform `ios`, and size `1024x1024`

Set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` for the Tend target's Debug and Release configurations. The current asset catalog has no app-icon set and the project has no app-icon build setting.

Keep the existing uncommitted signing configuration unchanged:

- development team `H3N925G7NW`
- bundle identifier `com.oxbowlabs.tend`

Those values are required for the owner's device installation but are not part of the icon change.

## Appearance variants

Provide the standard icon only. Dark and tinted source variants are outside this change because no approved variant artwork exists. iOS may apply its normal system presentation to the standard icon.

## Verification

- Confirm the Pencil production frame is complete, unclipped, and visually matches the approved comp.
- Confirm the exported PNG is exactly 1024×1024 and contains the four approved base colors.
- Build Tend for a generic iOS device so the asset catalog compiler validates the app-icon set and build setting.
- Inspect the exported PNG at full size and reduced app-icon size for clipping, unintended borders, and loss of legibility.

No behavior tests are required: this change adds a static asset and build configuration only.

## Out of scope

- redesigning or repositioning the approved artwork
- dark or tinted icon variants
- alternate icons selectable at runtime
- changing signing, bundle identity, deployment target, or supported device family
