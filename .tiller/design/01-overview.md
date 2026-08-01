# 01. Overview

## What Tend is

Tend is a habit tracker for one person. It runs on an iPhone, keeps all data on the device, and holds its user to their own commitments with plain arithmetic: you either met the requirement in the bucket or you didn't, and the streak tells the truth about it.

The name is the thesis. Habits are grown and cultivated, not gamified. Tend should feel like checking on a garden: a small daily act of attention, honest feedback about what's thriving and what's withering, and no theatrics.

## Who it's for

A single user who owns the device. There are no accounts, no profiles, no sharing, and no server. The app never needs to distinguish between people because there is only ever one.

This shapes several decisions downstream. Enforcement mechanisms that protect users from themselves (anti-cheat measures, tamper-proof logs, verification of claimed quantities) are deliberately absent. The user is on the honor system with themselves, and the product treats that as a feature. Building surveillance into a tool whose only user is its owner would be theater.

## Product principles

**Honesty over enforcement.** The user reports what they did. If a habit tracks 8000 steps, the user enters steps; the app does not read a pedometer, and it never will. Device sensors and health data integrations are permanently out of scope, not deferred. Manual entry is the design.

**Hard streaks.** A streak that survives a miss isn't a streak. When a bucket goes unmet, the streak resets to zero. No freeze tokens, no partial credit, no forgiveness mechanics. The one concession to real life is the grace period: a bucket stays open for one day after it closes, because forgetting to log something isn't the same as not doing it.

**One mechanism.** Every habit, from "meditate" to "drink 64 oz of water" to "post on LinkedIn once a week," is the same structure: a requirement evaluated per bucket. There are no habit types. Variation comes from the requirement and cadence values, not from branching models.

**Calm surface.** Tend is glanced at a few times a day for a few seconds. Every screen should answer its question immediately: what's left today, how am I doing, what happened this month.

## Out of scope

Permanently excluded:

- Health data integration of any kind (HealthKit, sensors, pedometers)
- Accounts, authentication, or any server-side component
- Social features, sharing, or comparison
- App Store distribution, monetization, or onboarding for strangers




Excluded from v1.0.0, possible later:

- Home screen and lock screen widgets
- Actionable notifications (logging from the notification itself)
- Apple Watch app
- Charts and trend visualizations beyond the history grid
- Data export
- Device-to-device sync
- Layouts designed specifically for iPad




## Release criteria for v1.0.0

v1.0.0 is done when all of the following are true:

1. Tend is installed and running on the owner's physical iPhone.
2. These 5 seed habits are entered and tracking:




| Habit | Cadence | Requirement | Reminder |
|---|---|---|---|
| Meditation | Daily | 10 min | 6:30 AM |
| Exercise | Daily | 8000 steps | 5:00 PM |
| Piano | Daily | 30 min | 7:30 PM |
| Garden | Daily | 1 times | 8:00 AM |
| LinkedIn | Weekly, pinned Wednesday | 1 times | 9:00 AM |

3. At least one full real day has been logged across all active habits.
4. Streak values shown in the app match a hand computation from the same log entries, including at least one verified hard reset and one verified grace-period save.
5. Reminders have been observed firing at their scheduled times and suppressing when the bucket's requirement was already met.
6. The full domain rule set in [02-domain-model.md](02-domain-model.md) is covered by passing automated tests.