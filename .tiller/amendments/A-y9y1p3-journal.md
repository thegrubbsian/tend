# Journal design intake

The landed design adds Journal as a daily prose surface with no measurement,
streak, or verdict. The Journal and Today v2 screens in
`~/dev/tend-design/comps/tend.pen` provide the supporting visual reference.

## Why

Tend has no place for an unmeasured daily record. The design preserves the
two-day creation and deletion window while keeping prose editable forever, a
deliberate distinction between whether an entry existed and what it says.

## What changes

- Add the Journal epic.
- Add one journal entry per local calendar day, with automatic timestamps and
  the documented creation, deletion, and editing rules.
- Add the top-level Journal experience, including composition, reverse
  chronology, the month grid, and live habit results in the entry view.
- Add the invitation card on Today that disappears after the day's entry
  exists.
- Record the unresolved choice between automatic save and one explicit save
  action as a blocking question.

## What to watch

After approval, record these implementation dependencies:

```bash
tiller link feature journal/journal-experience --depends-on journal/journal-entry-records
tiller link feature journal/today-journal-invitation --depends-on journal/journal-entry-records
```

The blocking save question must be answered before Journal Experience moves
forward. The four-tab shell shown in the Journal and Today v2 comps must
converge with the Goals shell change. Habit coupling, streaks, native
reminders, attachments, prompts, search, and export remain outside v1.
