# App Experience

Build Tend's complete SwiftUI experience around the Almanac design language so
the owner can understand and record habit state in seconds.

## Intent

Turn the Habit Engine into a calm, accessible field-journal interface where
logging is the cheapest action and every streak state remains truthful.

## Scope

- Establish the Almanac tokens, adaptive application shell, and Today/Habits
  navigation.
- Create, edit, activate, deactivate, and permanently delete habits through the
  roster and habit form.
- Present current progress, completion, streak, and at-risk state on Today.
- Support one-tap counts, quantity logging, quick-add, set-total, undo, and grace
  back-fill.
- Show each habit's current and best streaks, recent editable entries, and at
  least three months of bucket history.
- Carry Dynamic Type, VoiceOver, Reduce Motion, 44-point targets, haptics, and
  the Almanac visual grammar through every owned surface.

## Dependencies

Almanac App Shell follows the SwiftData Habit Model. Habit Management builds on
the shell, Habit Activity Lifecycle, and Streak Computation. Today Dashboard
builds on Habit Management; Fast Logging and Back-fill builds on Today
Dashboard; and Habit Detail and History builds on Habit Management.

## Definition of done

Every App Experience feature satisfies its acceptance contract, all specified
screens and states work end to end without a network or spinner, and the
interface matches the normative Almanac layout, state, accessibility, and motion
rules.
