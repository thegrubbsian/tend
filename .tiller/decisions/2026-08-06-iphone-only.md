# Tend v1 Is Native iPhone-Only

## Decision

Tend ships native iPhone-only in v1. Native iPad support is removed from the product, project configuration, live code, tests, and pending acceptance work; it is not deferred by waiver. Supporting iPad later requires a new product decision, adaptive design pass, implementation scope, and device-specific evidence.

## Rationale

Tend is a personal app intended for the owner's iPhone, where nearly all expected use will occur. Removing native iPad support now keeps the release contract, adaptive UI, simulator matrix, and accessibility evidence proportional to that audience while leaving a future intentional iPad feature possible.

## Concrete moves

- Amend `.tiller/design/01-overview.md` and `.tiller/design/04-platform-and-constraints.md` so the durable product inputs state native iPhone-only support.
- Re-scope `app-experience/fast-logging` (F-z8e13q) to an iPhone-only feature contract.
- Supersede `app-experience/fast-logging/fast-logging-acceptance` (T-p7kknm) with `app-experience/fast-logging/iphone-only-acceptance` (T-aocwl9).
- Make `device-readiness/owner-device-release` (F-3vz7ho) the forward owner of the iPhone-only release contract and any future device-support decision.
- Leave every done epic, feature, and task untouched. Also leave `app-experience/today-dashboard/today-dashboard-acceptance` (T-m66b11) untouched in review: its iPad evidence truthfully records what that reviewed commit verified.
