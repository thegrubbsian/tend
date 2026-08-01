# Tend: Product Specification

Tend is a personal habit tracker for iOS. This folder is the complete product specification, written to hand off to an engineering team. It describes what the product does and why, in enough detail to build from, without prescribing how the work should be organized or executed.

## Reading order

| Doc | Contents |
|---|---|
| [01-overview.md](01-overview.md) | What Tend is, who it's for, product principles, what's out of scope, and the v1.0.0 release criteria |
| [02-domain-model.md](02-domain-model.md) | The core concepts and their exact semantics: habits, cadence, buckets, logging, streaks, and the rules that bind them |
| [03-user-experience.md](03-user-experience.md) | Screens, flows, notifications, and interaction requirements |
| [04-platform-and-constraints.md](04-platform-and-constraints.md) | Technology selections, data requirements, quality requirements, and privacy posture |
| [05-visual-design.md](05-visual-design.md) | The Almanac design language: color, type, components, motion, and the comp file that anchors them |

Start with the overview. The domain model is the heart of the spec; most acceptance criteria trace back to it. The experience doc describes required capabilities and information; the visual design doc and its comp file carry layout, styling, and component decisions.

## Glossary

Terms used consistently across all documents:

- **Habit**: a recurring commitment the user tracks, defined by a cadence and a requirement.
- **Cadence**: how often a habit recurs. Daily or weekly.
- **Requirement**: the target amount and unit that satisfy a habit for one bucket (for example, 30 min, 8000 steps, 1 times).
- **Bucket**: one evaluation period for a habit. A calendar day for daily habits, a calendar week for weekly habits.
- **Log entry**: a single recorded contribution toward a bucket's requirement.
- **Grace period**: the one-day window after a bucket closes during which entries can still be added to it.
- **Final**: a bucket whose grace period has ended. Final buckets are immutable and their verdict is settled.
- **Streak**: the count of consecutive satisfied buckets, measured in the habit's bucket unit (days or weeks).
- **Inactive**: a habit state where tracking is suspended. Inactive periods are invisible to streak math.



## Status

This is a living specification. It gets refined in place as build work exposes gaps or forces decisions. Where the spec and shipped behavior disagree, the resolution is deliberate: either the spec was wrong and gets fixed, or the build drifted and gets corrected.