# 05. Visual Design

This document specifies Tend's visual language, called **Almanac**, and anchors it to the comp file that renders it. Where prose and comps disagree, the comps win for look unless the prose names a later implementation refinement; the domain model wins for behavior.

## Design language

Almanac treats the app like a well-made field journal: warm paper surfaces, ink text, serif numerals, and a small family of living colors that only appear where life does. Definition comes from hairline strokes and surface shifts, never from heavy shadows. The interface should feel printed rather than rendered, calm rather than motivational. Nothing celebrates loudly and nothing scolds; a missed day looks dried out, not alarming.

## Reference comps

The comp file is `comps/tend.pen` (a Pencil document, versioned alongside these docs). Boards:

| Board | Establishes |
|---|---|
| Almanac Foundations | Color tokens, type scale, bucket-state swatches, specimen habit card |
| Today | The daily screen: sections, habit cards, at-risk treatment, tab bar |
| Log Sheet | The quantity-logging surface over a dimmed Today |
| Affordance States | The log ring's four states |
| Habit Detail | Stats, the garden bed history grid, month navigation, legend |
| All Habits | Active and inactive rosters, add action, tab bar (Habits active) |
| Edit Habit | Form fields, locked cadence, pinned-day chips, reminder row |

**Normative vs illustrative.** Layout, spacing, color roles, and state grammar in the comps are normative. The fictional data (habit names, streak values, July's specific pattern) is illustrative only.

**Canvas stand-ins.** The comp renderer cannot load Apple system fonts or SF Symbols, so the comps use stand-ins. The build uses the real thing:

| In comps | In the app |
|---|---|
| Lora (serif) | New York |
| Inter (sans) | SF Pro |
| Lucide icons | SF Symbols (mapping below) |

## Color

All values exist as variables in the comp file under the same names.

| Token | Hex | Role |
|---|---|---|
| paper | #F7F2E7 | App background |
| paper-raised | #FCF9F1 | Cards, sheets' raised elements, active segments |
| paper-sunken | #EDE6D6 | Progress tracks, input fields, insets, dormant rows |
| ink | #2B2A26 | Primary text |
| ink-muted | #6F6A5E | Secondary text, section labels |
| ink-faint | #A79F8F | Disabled text, inline explainers, inactive icons |
| hairline | #E6DEC9 | Card and pill strokes, dividers |
| moss | #3D5A3D | Met, progress, primary actions, active tab |
| moss-deep | #2F462F | Pressed and highlighted states of moss elements |
| clay | #C1704F | Today markers, selected day chips, editorial actions (Edit, Cancel, Undo) |
| clay-deep | #A4573C | Clay as text below 20 pt |
| ochre | #D9A441 | At-risk fills, strokes, and dots |
| ochre-deep | #9C7414 | Ochre as text below 20 pt |
| withered | #8A6A52 | Missed |

The grammar, which generalizes past any single screen:

- **Moss is life.** It appears only on met states, progress, and the primary action of a screen. It never decorates.
- **Withered replaces red.** A missed bucket is a plant that dried out, not an emergency. Nothing in the app is ever alarm-red.
- **Ochre means "still savable."** At-risk streak numerals, the grace cell's stroke, the risk line, the dot on the Yesterday scope.
- **Clay is the editorial voice.** Today's marker in the grid, the selected pinned day, and text actions (Edit, Cancel, Undo, Set day total).
- **Accessibility rule.** Clay and ochre as text below 20 pt always use their deep variants; the base hues are reserved for fills, strokes, and dots, and for numerals 20 pt and larger. Comps show base hues on small text for palette continuity; the build deepens them. Verify contrast on device as part of acceptance.

## Typography

Two faces, both shipped with the OS: **New York** for display and every numeral that carries meaning, **SF Pro** for everything else. All numerals use tabular (monospaced-digit) figures so counts don't shimmy as they change.

| Style | Face | Size / weight | Use |
|---|---|---|---|
| Streak display | New York Semibold | 56 | Habit Detail hero moments, foundations specimen |
| Stat numeral | New York Semibold | 40 | Current and best streak on Detail |
| Screen title | New York Semibold | 30 | Today, Habits, habit names on Detail |
| Card streak | New York Semibold | 20 (unmet cards), 15 (compact met rows) | Streak on cards and roster rows |
| Habit name | SF Pro Semibold | 17 | Card and sheet titles |
| Body | SF Pro Regular | 17 | General content |
| Secondary | SF Pro Regular | 15 | Progress meta, entry rows, field values |
| Label | SF Pro Semibold | 13, +2.5 tracking, uppercase | Section wayfinding (TO TEND, CURRENT, PINNED DAYS) |
| Caption | SF Pro Regular | 12 | Inline explainers, legend, entry timestamps |

Dynamic Type is supported: map these styles to the platform's text styles so user sizing scales text throughout. Fixed-geometry elements (log ring, garden bed cells, tab pill) keep their dimensions; their labels scale.

## Surfaces, spacing, radius

- Cards and the tab pill sit on `paper-raised` with a 1 pt `hairline` stroke. Cards remain shadowless. As a post-comp refinement, only the floating tab pill has a centered ink shadow at 8% opacity with an 8 pt blur and no directional offset.
- Inputs, progress tracks, and dormant rows sink into `paper-sunken`.
- Radius tokens: 14 for cards and sheets' corners, 7 for garden bed cells, full-round for the ring, chips, day circles, and the tab pill (36).
- Spacing tokens: 8 / 16 / 24 / 40, with 20 pt horizontal screen padding and 16 pt between stacked sections on dense screens.
- Progress tracks are 8 pt tall, `paper-sunken` under a moss fill, fully rounded.

## Iconography

SF Symbols, hairline-consistent weights (regular/medium). Mapping from the comps:

| Comp (Lucide) | Build (SF Symbol) |
|---|---|
| plus | plus |
| check | checkmark |
| chevron-left / chevron-right | chevron.left / chevron.right |
| list | list.bullet |
| lock | lock |
| circle-minus | minus.circle |
| sprout | custom "sprout" symbol asset; fallback: leaf |

The sprout is the one glyph SF Symbols lacks. Author it once as a custom symbol so it inherits weights and Dynamic Type; if that stalls, ship `leaf` and revisit.

## Components

**Habit card (unmet).** Raised surface, radius 14, hairline stroke, 16 pt padding. Anatomy top to bottom: name row (name left; streak numeral + unit right, numeral colored by status), optional risk line, progress track, meta line. The log ring sits at the trailing edge of the name row, vertically leading. Meta line doubles as the transient undo surface.

**Habit card (met, compact).** Single row: name and small streak left, filled moss check circle (44 pt) trailing. Reduced padding. Met cards read as settled, not as invitations.

**Log ring.** 52 pt circle, minimum 44 pt hit target. States: Empty (hairline moss ring, plus mark), In progress (a 4 pt moss arc growing clockwise from 12 o'clock over a sunken ring track, plus mark), Complete (solid moss, paper checkmark), Undo window (Complete plus the transient undo affordance on the card). Behavior per the logging interaction model in [03-user-experience.md](03-user-experience.md).

**Log sheet.** Paper surface, top radius 20, grabber. Order: title, scope segmented control (raised active cell; the Yesterday cell carries a 6 pt ochre dot while that bucket is open and unfinished), progress track and meta, chip row (stroked moss pills; the rightmost Finish chip filled moss with paper text), custom-amount row on sunken fill with the clay Set-day-total action, LOGGED entries with minus.circle deletes.

**Garden bed grid.** Cells 44 pt, radius 7, distributed edge to edge across content width; weekday letters above; month row with tracked month name and faint chevrons; legend below (Met, Missed, Open). Cell states: met (moss), missed (withered), open/grace (raised with 1.5 pt ochre stroke), today (raised with 1.5 pt clay stroke), out of month or pre-creation (sunken at 45% opacity), dormant span (sunken at 45%, same as ghost; the inactive gap reads as absence). Cells are deliberately unnumbered; a tap on any cell reveals its date and state in a lightweight popover.

**Tab bar.** Floating pill, 62 pt, radius 36, raised with hairline stroke, a subtle even shadow, and 21 pt side and bottom insets. Active tab is a solid moss capsule with paper icon and label; inactive tabs are transparent with faint ink. Two destinations: TODAY (sprout), HABITS (list).

**Day chips.** 40 pt circles: sunken with muted text unselected, clay with paper text selected.

**Form fields.** Tracked uppercase label above a sunken field, radius 10, padding 12/14. Locked fields show the value in muted ink with a trailing lock glyph and a one-line faint explainer beneath. Inline notes are caption-size faint ink.

## Screens

**Today.** Eyebrow date, serif title, serif fraction count in moss at the trailing edge. Sections TO TEND and TENDED; unmet cards first, met compact rows after, alphabetical within groups. Weekly habits present all week. When everything is tended, the TO TEND section gives way to a single quiet serif line, "All tended.", above the TENDED list. No illustration, no celebration.

**First launch.** One sentence of introduction in body type and a single primary action to create the first habit. Nothing else on the screen.

**Habit Detail.** Back link and clay Edit in the nav row, serif habit name, requirement subline, CURRENT and BEST stat pair (CURRENT wears the status color), risk line when applicable, then the garden bed with month navigation. The bed covers at least the trailing 3 months via the chevrons.

**All Habits.** Serif title with a filled moss add button. ACTIVE rows: name, requirement subline, serif streak trailing (status-colored). INACTIVE rows sink into `paper-sunken` with muted name, a "dormant" subline, and the frozen streak phrased as "held at N days" in faint serif.

**Add and Edit Habit.** Same form. Add titles "New habit" with no lock and Save disabled until valid; Edit titles "Edit habit" and locks cadence with the explainer "Set at creation. To change cadence, archive this habit and plant a new one." Pinned-day chips appear only for weekly cadence, with the note "Reminders fire on pinned days. Logging any day still counts."

## Motion and haptics

Starting values, tuned on device during acceptance:

- Logging fills move like liquid: track and ring arcs animate over ~350 ms with an ease-out curve.
- Completion blooms: the ring scales 1 → 1.06 → 1 on a soft spring while cross-fading to the check, ~450 ms total.
- The log sheet uses the platform's standard sheet spring and detents.
- Haptics: light impact on any log, success notification on bucket completion, a lighter tick on undo.
- Reduce Motion replaces fills and blooms with cross-fades; nothing conveys meaning through motion alone.
- Nothing bursts, bounces for attention, or loops. Confetti remains banned.

## Appearance and accessibility

- **v1 is light-appearance only.** Almanac is a paper object; the app declares light appearance and renders identically regardless of system setting. A dark "night garden" variant is future work, not a v1 requirement.
- Dynamic Type per the typography section; layouts must tolerate two size steps up without truncating habit names (wrap or tighten, never ellipsize a name the user wrote).
- Colored text follows the deep-variant rule above; verify contrast on device.
- VoiceOver: the log ring announces habit, progress toward target, and streak, and acts as a button. Garden bed cells announce date and state. The risk line announces the stakes ("Yesterday open, 12 day streak at risk").
- All tap targets meet 44 pt.

## Voice

Microcopy rules, since words are part of the design:

- Cultivation vocabulary, used sparingly and only where it earns its place: tend, held, dormant, plant anew. Never gamification language, never fire, never "crushing it."
- States are named plainly: Met, Missed, Open, Dormant.
- Numerals always travel with their unit: "34 days," "9 weeks," never a bare count.
- Tracked uppercase is for wayfinding labels only; everything else is sentence case.
- The app states facts and stops. "All tended." is a complete celebration.

## Decision notes

1. **Garden bed cells are unnumbered.** The bed reads as texture first; exact dates are one tap away. Numbers would make it a spreadsheet.
2. **Light-only in v1.** Forcing light appearance is a deliberate product stance, recorded here so nobody "fixes" it.
3. **Deep text variants exist for accessibility,** not aesthetics. Base clay and ochre fail contrast as small text on paper; the deep pair is the same voice at a legible volume.
4. **The sprout becomes a custom SF Symbol.** One small asset buys a consistent icon system; leaf is the sanctioned fallback.
5. **The all-done and first-launch states are specified in prose, not comped.** They are single-idea screens; the guidance above plus the existing language is sufficient to build them.
