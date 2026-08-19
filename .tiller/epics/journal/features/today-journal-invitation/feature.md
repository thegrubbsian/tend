# Today Journal Invitation

## Summary

Add one quiet Journal invitation to Today while today's entry does not exist.
It gives the owner a direct path into today's Journal editor, then leaves the
daily surface as soon as that entry is created. The card is an invitation, not
another commitment: it never gains progress, standing, streak, risk, reminder,
missed, or celebration semantics.

This feature consumes the durable Journal records and Journal routing/editor
established by its dependencies. It does not create a second editor, save path,
entry model, or navigation system inside Today.

## Behavior

### Daily projection

Project the current `LocalDate` from one explicit refresh context and query
Journal entry existence through the shared Journal read API.

- Exactly one invitation is present when today's entry is absent.
- The invitation is absent when today's entry exists, regardless of body
  length.
- Yesterday and older missing entries never create Today cards.
- Creating today's entry removes the invitation without relaunch.
- Deleting today's entry during its legal window restores the invitation
  without relaunch.
- Local-day rollover, scene activation, owner time-zone changes, Journal query
  changes, and retry re-evaluate the same state through the established Today
  refresh path.
- A query failure produces one truthful unavailable Journal row with Retry. It
  does not hide valid Habit or Goal rows and does not pretend an invitation is
  eligible.

Journal state does not participate in `All tended`, Habit fractions, Goal
standing, logging schedules, or the earliest Goal transition.

### Today composition

Place a `JOURNAL` section after all Habit and Goal sections and before the
floating tab pill's clearance. When eligible, it contains one raised Almanac
card with a short invitation to write about today and one card-wide action.
The card contains no inline editor, checkbox, progress track, badge, urgency
color, streak numeral, or dismissal control.

The section is omitted with no empty heading once today's entry exists. When
Today otherwise shows first-launch, inactive-only, all-tended, or no-eligible
Goal states, the Journal section composes after that existing body without
changing its wording or meaning.

### Routing

Activating the card selects the existing Journal destination and opens the
editor for today's exact `LocalDate`. Repeated activation is idempotent. The
destination owns editing, save behavior, focus, cancellation, and persistence
errors; Today owns only the invitation and route request.

VoiceOver exposes one action whose label names writing today's Journal entry and
whose hint names the Journal destination. Decorative geometry is hidden.
Dynamic Type may increase card height without truncating the invitation or
covering it with the floating tab pill.

## Notes

The invitation follows entry existence, not whether the body looks meaningful.
This preserves the Journal doctrine that existence fossilizes separately from
content.

No native reminder, notification, prompt rotation, nag count, snooze, or habit
auto-log belongs here. Yesterday remains reachable from the Journal compose
experience, not from a second Today invitation.
