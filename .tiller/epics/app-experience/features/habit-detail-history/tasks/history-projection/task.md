# Project truthful habit detail history

## Approach

Add the TendCore read boundary that every Habit Detail presentation consumes.
Start with an isolated `HabitDetailComputationTests` suite and make the full
state matrix fail before adding implementation.

Create immutable public projection types for:

- the supported selected-month range;
- current and best streak plus risk;
- one daily or weekly bucket fact with key, period boundaries, semantic state,
  provisional progress, effective target and unit where meaningful, and stable
  identity;
- one editable recent entry fact with identifier, timestamp, amount, bucket
  key, effective unit, and period boundaries; and
- the complete atomic detail snapshot.

Use a semantic enum that keeps final met/missed, provisional open/grace,
inactive, pre-creation, and future distinct. Do not encode view colors,
localized strings, cell geometry, or SwiftData model references in TendCore.

Implement a main-actor `HabitDetailComputation` initialized from the owning
`ModelContext`. Its snapshot operation accepts a persisted `Habit`, injected
instant, injected time zone, and selected month. It must:

1. validate that the habit belongs to the context;
2. reconcile active buckets through the established domain boundary;
3. compute streaks through `HabitStreakComputation`;
4. fetch and uniquely index the habit's buckets, entries, and activity periods;
5. derive the earliest/latest month range and clamp an out-of-range selected
   month to the new range;
6. generate daily periods inside the selected month or weekly periods
   intersecting it with `CalendarBucketSchedule`;
7. evaluate persisted buckets through `BucketEvaluator`;
8. synthesize only proven inactive, pre-creation, or future periods; and
9. return all open/grace editable entries newest first.

Normalize month boundaries with the injected local calendar, not fixed seconds
or UTC. For daily pages, project only dates inside the selected calendar month;
the app adds leading/trailing out-of-month geometry. For weekly pages, include
every Monday-through-Sunday period whose half-open interval intersects the
selected month, even when the same boundary week appears on an adjacent page.

Classification order is authoritative persisted bucket, future period,
pre-creation period, proven inactive gap. If an elapsed period overlaps any
activity interval but has no bucket, return a typed integrity error. Treat open
activity intervals as ending after the injected instant for overlap checks, not
as infinite permission to invent future buckets.

Validate relationship ownership for every fetched bucket and entry, supported
cadence/raw enum values, positive current and snapshotted requirements, unique
period keys, valid finality, and checked integer progress. Preserve existing
typed domain errors where possible and use focused detail-computation errors
only for invariants unique to this projection.

An entry is editable only when its owning bucket evaluates to open or grace and
the existing `LogEntryOperations.delete` authorization would accept that bucket
at the same instant and time zone. Do not include final/exempt entries or
implement a second deletion policy. The projection does not mutate entries.

Do not change the SwiftData schema, persistence defaults, bucket reconciliation,
streak calculation, lifecycle operations, logging operations, or owner-visible
UI in this task.

## Surfaces

- Create focused sources under `Sources/TendCore/History/`, expected to include
  `HabitDetailSnapshot.swift` and `HabitDetailComputation.swift`; split further
  only when a type has an independent reason to exist.
- Create
  `Tests/TendCoreTests/History/HabitDetailComputationTests.swift`.
- Modify package or Xcode project metadata only if filesystem-synchronized
  source discovery does not include the new files automatically.
- Do not modify `App/Tend`, `App/TendTests`, `App/TendUITests`, Almanac tokens,
  Pencil comps, notification code, or Tiller nodes outside this task.

## Tests

Build fixtures through public habit-management, lifecycle, and logging
operations where the behavior under test begins at those boundaries. Use
direct model construction only for malformed persistence cases that supported
operations correctly make unrepresentable.

Cover:

- daily month pages with Monday-first local-calendar periods in 23-hour and
  25-hour DST transitions;
- weekly pages containing boundary weeks that intersect two month pages;
- current month plus two preceding months for a new habit;
- full-lifetime navigation for an older habit;
- selected-month clamping across month rollover;
- finalized met and missed buckets using frozen target/unit snapshots;
- open and grace buckets both below and at/above requirement;
- exemption and multi-period inactive gaps;
- creation mid-day and mid-week without mislabeling the creation bucket;
- future periods without invented persisted facts;
- truthful current, best, and at-risk streak projection;
- newest-first editable entries with stable tie-breaking;
- inactive habits and buckets with no editable entries;
- time-zone changes using the new local schedule;
- duplicate buckets, missing active buckets, foreign relationships, unsupported
  cadence/verdict values, partial finality, invalid amounts/targets, overflow,
  detached models, and save failures; and
- no write when reconciliation and best-streak persistence have nothing to
  change.

Use deterministic calendars, time zones, UUIDs, and instants. Assert semantic
facts and boundaries, not private helper names or query implementation.

Run:

- `Scripts/tiller-swift-test Tests/TendCoreTests/History/HabitDetailComputationTests.swift`
- `Scripts/tiller-swift-test`
- `swift build`

## Edge cases

- A bucket containing the creation instant is real history even when its start
  precedes `Habit.createdAt`.
- A weekly bucket may appear on two adjacent month pages but represents one
  stable period key and one persisted bucket.
- Future periods that overlap an open-ended activity interval remain future;
  they are not missing-bucket corruption.
- A deactivation during an unsettled bucket leaves its persisted exempt bucket
  authoritative over interval inference.
- An inactive gap has no fabricated target, unit, progress, or verdict.
- Final bucket progress remains unavailable where `BucketEvaluator` deliberately
  exposes only frozen verdict and requirement facts.
- Entry timestamps need not lie inside their destination bucket because
  back-fill logs at the logging instant; bucket ownership, not timestamp, is the
  editability source of truth.
- Calendar arithmetic never assumes all days contain 86,400 seconds.
