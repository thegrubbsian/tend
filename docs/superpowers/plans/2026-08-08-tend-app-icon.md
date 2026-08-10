# Tend App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export the approved Sprout & Sun vector composition and configure it as Tend's native iPhone app icon.

**Architecture:** Keep `../tend-design/tend-app-icons.pen` as the only artwork source by adding one production export frame derived from the approved comp. Store one modern universal 1024×1024 PNG in Tend's asset catalog and point both Tend build configurations at the `AppIcon` set.

**Tech Stack:** Pencil vector design, Xcode asset catalogs, PNG, Xcode 26

## Global Constraints

- Preserve the approved `Tile 06 · SPROUT & SUN` composition and its relative geometry exactly.
- Use base colors `#F7F2E7`, `#C1704F`, `#D5D6D2`, and `#3D5A3D` in sun, cloud, sprout layer order.
- Export square, edge-to-edge artwork with no baked corner radius, border, shadow, gradient, or text.
- Provide only the standard app icon; do not invent dark, tinted, or alternate variants.
- Do not change deployment target, supported device family, signing team `H3N925G7NW`, or bundle identifier `com.oxbowlabs.tend`.
- Treat the existing signing and bundle-identifier edits in `Tend.xcodeproj/project.pbxproj` as user-owned work; preserve them and exclude them from the icon commit.
- This is generated artwork plus build configuration. The approved design explicitly requires build and visual verification instead of a permanent behavior test.

---

### Task 1: Produce the approved 1024×1024 artwork

**Files:**
- Modify: `../tend-design/tend-app-icons.pen`
- Create: `App/Tend/Assets.xcassets/AppIcon.appiconset/AppIcon.png`

**Interfaces:**
- Consumes: Pencil node `tignF`, named `Tile 06 · SPROUT & SUN`
- Produces: Pencil frame `Production Export · SPROUT & SUN` and a 1024×1024 PNG with the same composition

- [ ] **Step 1: Verify the production PNG is absent**

Run:

```bash
test -f App/Tend/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Expected: exit 1 because Tend currently has no app-icon set.

- [ ] **Step 2: Create the production frame from the approved Pencil node**

Run this Pencil `execute` input against `../tend-design/tend-app-icons.pen`:

```javascript
const productionIcon = Copy("tignF", "document", {
  name: "Production Export · SPROUT & SUN",
  x: 2100,
  y: 0
})
const tree = Get(productionIcon, { depth: 6 })
const sun = tree.children[0].id
const cloud = tree.children[1].id
const sprout = tree.children[2].id
const puffL = tree.children[1].children[0].id
const puffMain = tree.children[1].children[1].id
const puffR = tree.children[1].children[2].id
const cloudBase = tree.children[1].children[3].id
Update(productionIcon, {
  width: 1024,
  height: 1024,
  cornerRadius: 0,
  stroke: "#00000000",
  strokeWidth: 0
})
Update(sun, { x: 128, y: 121.6, width: 345.6, height: 345.6 })
Update(cloud, { x: 268.8, y: 326.4, width: 358.4, height: 166.4 })
Update(puffL, { x: 0, y: 51.2, width: 140.8, height: 102.4 })
Update(puffMain, { x: 76.8, y: 0, width: 166.4, height: 140.8 })
Update(puffR, { x: 192, y: 38.4, width: 140.8, height: 108.8 })
Update(cloudBase, {
  x: 25.6,
  y: 76.8,
  width: 307.2,
  height: 76.8,
  cornerRadius: 38.4
})
Update(sprout, { x: 384, y: 371.2, width: 537.6, height: 537.6 })
Print(productionIcon)
Print(Get(productionIcon, {
  depth: 6,
  resolveVariables: true,
  resolveInstances: true,
  includePathGeometry: true
}))
```

Expected: one new top-level 1024×1024 frame whose children retain the comp's geometry at a uniform 6.4 scale.

- [ ] **Step 3: Inspect the frame structure before export**

Review the resolved structure printed by Step 2.

Expected: a 1024×1024 frame filled `#F7F2E7`, radius `0`, stroke width `0`, with only the scaled sun, cloud, and sprout children.

- [ ] **Step 4: Create the asset export directory**

Run:

```bash
mkdir -p App/Tend/Assets.xcassets/AppIcon.appiconset
```

- [ ] **Step 5: Export the production frame**

Run Pencil `export_nodes` with the production frame ID, PNG format, output directory `App/Tend/Assets.xcassets/AppIcon.appiconset`, and scale `1`.

Expected: Pencil writes one PNG named for the production frame's generated node ID at 1024×1024.

Rename that only PNG:

```bash
mv App/Tend/Assets.xcassets/AppIcon.appiconset/*.png App/Tend/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

- [ ] **Step 6: Verify the PNG dimensions**

Run:

```bash
sips -g pixelWidth -g pixelHeight App/Tend/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Expected: `pixelWidth: 1024` and `pixelHeight: 1024`.

### Task 2: Integrate the app icon with the Tend target

**Files:**
- Create: `App/Tend/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Modify: `Tend.xcodeproj/project.pbxproj:323-380`

**Interfaces:**
- Consumes: `AppIcon.png` from Task 1
- Produces: an `AppIcon` asset-catalog set selected by Tend Debug and Release builds

- [ ] **Step 1: Verify the Tend target does not yet select an app icon**

Run:

```bash
xcodebuild -project Tend.xcodeproj -target Tend -configuration Debug -showBuildSettings -json | jq -e '.[0].buildSettings.ASSETCATALOG_COMPILER_APPICON_NAME == "AppIcon"'
```

Expected: exit 1 because `ASSETCATALOG_COMPILER_APPICON_NAME` is absent.

- [ ] **Step 2: Create the app-icon manifest**

Create `App/Tend/Assets.xcassets/AppIcon.appiconset/Contents.json` with:

```json
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Verify the manifest before relying on Xcode**

Run:

```bash
jq -e '.images == [{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}] and .info == {"author":"xcode","version":1}' App/Tend/Assets.xcassets/AppIcon.appiconset/Contents.json
```

Expected: exit 0.

- [ ] **Step 4: Select `AppIcon` in both Tend build configurations**

Add this build setting immediately before `CODE_SIGN_STYLE` in the Tend target's Debug configuration and again in its Release configuration:

```text
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
```

Do not edit the neighboring `DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER`, deployment-target, or device-family values.

- [ ] **Step 5: Verify both configurations resolve the setting**

Run:

```bash
xcodebuild -project Tend.xcodeproj -target Tend -configuration Debug -showBuildSettings -json | jq -e '.[0].buildSettings.ASSETCATALOG_COMPILER_APPICON_NAME == "AppIcon"'
xcodebuild -project Tend.xcodeproj -target Tend -configuration Release -showBuildSettings -json | jq -e '.[0].buildSettings.ASSETCATALOG_COMPILER_APPICON_NAME == "AppIcon"'
```

Expected: both commands exit 0.

- [ ] **Step 6: Compile the asset catalog through a generic iOS build**

Run:

```bash
xcodebuild -project Tend.xcodeproj -scheme Tend -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit 0 with `** BUILD SUCCEEDED **` and no app-icon asset-catalog errors.

### Task 3: Verify the delivered visual and preserve user work

**Files:**
- Verify: `../tend-design/tend-app-icons.pen`
- Verify: `App/Tend/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
- Verify: `App/Tend/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Verify: `Tend.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: the production Pencil frame and integrated asset set
- Produces: visual and build evidence plus an icon-only repository commit

- [ ] **Step 1: Inspect the production frame visually**

Capture a Pencil screenshot of `Production Export · SPROUT & SUN` and confirm:

- the parchment background reaches all four square edges
- no border or rounded source corners remain
- the sun, cloud, and sprout match the approved comp
- no child is clipped or missing

- [ ] **Step 2: Inspect the exported PNG at full and reduced size**

Open `AppIcon.png` and confirm the full-size artwork has no border, clipping, text, or added effects. Render or inspect it near 60×60 points and confirm the sprout remains recognizable and the cloud/sun overlap remains legible.

- [ ] **Step 3: Verify the complete change again**

Run:

```bash
sips -g pixelWidth -g pixelHeight App/Tend/Assets.xcassets/AppIcon.appiconset/AppIcon.png
jq -e '.images[0].filename == "AppIcon.png" and .images[0].idiom == "universal" and .images[0].platform == "ios" and .images[0].size == "1024x1024"' App/Tend/Assets.xcassets/AppIcon.appiconset/Contents.json
xcodebuild -project Tend.xcodeproj -scheme Tend -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 1024×1024 dimensions, valid manifest, and `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit only icon-owned changes**

Stage:

```text
App/Tend/Assets.xcassets/AppIcon.appiconset/AppIcon.png
App/Tend/Assets.xcassets/AppIcon.appiconset/Contents.json
ASSETCATALOG_COMPILER_APPICON_NAME additions in Tend.xcodeproj/project.pbxproj
```

Exclude the pre-existing development-team and bundle-identifier edits from the commit. Commit with:

```bash
git commit -m "feat: add Sprout and Sun app icon"
```

- [ ] **Step 5: Confirm the remaining working tree contains only user-owned signing changes**

Run:

```bash
git status --short
git diff -- Tend.xcodeproj/project.pbxproj
```

Expected: the app-icon asset set and build-setting additions are committed; only the pre-existing development-team and bundle-identifier changes remain uncommitted.
