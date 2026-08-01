# Device Readiness

Finish the device-only integration and evidence needed to call the owner's
installed build Tend v1.0.0.

## Intent

Make reminders trustworthy in real use, then prove the complete application on
the physical iPhone it is built for.

## Scope

- Request notification permission in context, schedule local daily and pinned
  weekly reminders, suppress reminders for met buckets, and route taps to Today.
- Install the current build on the owner's iPhone and enter the five specified
  seed habits.
- Observe a full day of logging, a hard streak reset, a grace-period save, and
  scheduled and suppressed reminders against hand-computed expectations.
- Confirm the shipped build remains private, offline, responsive, and free of
  third-party runtime dependencies.

## Dependencies

Local Reminders builds on Habit Management and Today Dashboard. Owner Device
Release builds on Local Reminders, Fast Logging and Back-fill, and Habit Detail
and History.

## Definition of done

Every Device Readiness feature satisfies its acceptance contract and every
v1.0.0 release criterion has recorded evidence from the owner's physical iPhone
or the complete automated domain suite, as appropriate.
