# Exercise Tracker

An iOS workout tracker for building plans, recording weights and notes per set, and reviewing workout history.

## Creating plans

Choose **Create New Plan** on Home, then choose one of these paths:

- **Create Manually** — choose the number of training days and add exercises in the app.
- **Import Plan File** — select a UTF-8 `.txt` or `.json` file containing JSON in the format below.

## Import-file format

The importer uses `program_metadata.name` as the plan name and imports each schedule entry whose `type` is `lifting` and has exercises. Recovery and sport-only entries are left out of the lifting rotation. Exercise order, set count, names, rep ranges, and duration ranges are preserved.

```json
{
  "program_metadata": {
    "name": "4-Day Upper/Lower Split",
    "goal": "Build lean muscle",
    "split_type": "Upper / Lower + Sport",
    "days_per_week": 4
  },
  "schedule": {
    "monday": {
      "session_name": "Upper A",
      "type": "lifting",
      "exercises": [
        {
          "order": 1,
          "exercise": "Machine Chest Press",
          "sets": 3,
          "rep_range": [8, 12],
          "is_unilateral": false
        }
      ]
    },
    "wednesday": {
      "session_name": "Rest",
      "type": "recovery"
    },
    "friday": {
      "session_name": "Lower A + Abs",
      "type": "lifting",
      "exercises": [
        {
          "order": 1,
          "exercise": "Plank",
          "sets": 2,
          "duration_seconds_range": [30, 60],
          "metric_type": "time"
        }
      ]
    }
  }
}
```

`rep_range` is shown in the app as a target such as `8–12 reps`. `duration_seconds_range` is shown as a target such as `30–60 sec`. Extra fields, including the global execution rules and unilateral flags in your example, are accepted and safely ignored by the current tracking UI.
