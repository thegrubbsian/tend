# Habit Engine

Build the deterministic, on-device domain foundation that keeps Tend's history,
bucket verdicts, and streaks honest independently of the interface and wall
clock.

## Intent

Give every product surface one tested source of truth for habits, calendar
buckets, log entries, activity gaps, and streak state.

## Scope

- Define a durable, CloudKit-compatible SwiftData shape for habits, buckets,
  requirement snapshots, and log entries.
- Evaluate daily and weekly buckets from the device's local calendar, including
  grace and finality, DST transitions, and requirement changes.
- Enforce append/delete logging, final-bucket immutability, and activation and
  deactivation semantics.
- Compute current streaks, best streaks, and at-risk state deterministically at
  arbitrary points in time.
- Cover every domain rule, worked example, and decision note with device-free
  automated tests.

## Dependencies

Calendar Bucket Evaluation builds on the SwiftData Habit Model; Log Entry
Operations builds on bucket evaluation; Habit Activity Lifecycle builds on log
operations; and Streak Computation builds on activity lifecycle.

## Definition of done

Every Habit Engine feature satisfies its acceptance contract, the complete
domain rule set passes without a device or UI, and persisted history remains
correct across relaunches and local-calendar boundary changes.
