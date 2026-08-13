# Goals design intake

The landed design adds Goals as a quantitative tracking capability beside
habits. The Goals and Today v2 screens in
`~/dev/tend-design/comps/tend.pen` provide the supporting visual reference.

## Why

Tend currently tracks recurring habits but not finite arcs toward a numeric
target. The design defines two distinct goal kinds, honest pace and closure
semantics, and deliberate boundaries that keep goal history separate from
habit verdicts.

## What changes

- Add the Goals epic.
- Add goal records and progress for accumulate and measure goals.
- Add manual lifecycle, computed standing, editing, and deletion rules.
- Add the top-level Goals experience, including forms, progress visuals,
  detail, history, and close actions.
- Surface only behind, near-deadline, or past-due open goals on Today.

## What to watch

After approval, record these implementation dependencies:

```bash
tiller link feature goals/goal-lifecycle --depends-on goals/goal-records
tiller link feature goals/goal-experience --depends-on goals/goal-lifecycle
tiller link feature goals/today-goal-surfacing --depends-on goals/goal-lifecycle
```

The four-tab shell shown in the Goals and Today v2 comps must preserve the
existing Today and Habits behavior. Notifications, habit linking, maintenance
goals, non-integer quantities, and trend charts remain outside v1.
