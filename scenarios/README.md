# Scenarios — agent-driven test harness

Headless, deterministic scenarios for the orcs-lair simulation. Any agent (CI, QA bot, autopilot) can run these without a display, read the JSON results, and grade pass/fail.

## Run a scenario

```sh
godot --headless ++ \
  --scenario=res://scenarios/baseline.json \
  --output=/tmp/result.json
```

Notes:
- `++` is Godot's separator for user-space args. Args after `++` are read by `OS.get_cmdline_user_args()`.
- `--scenario=` accepts a `res://` path or a bare filename (looked up under `scenarios/`).
- `--output=` writes the JSON results to that path. Omit to print to stdout.
- Process exits 0 on pass, 1 on fail, 2 on scenario-load error.

## Scenario JSON shape

```jsonc
{
  "name": "...",
  "description": "human-readable purpose",
  "seed": 42,                      // RNG seed; same seed → same result
  "max_duration_s": 30,            // hard timeout
  "auto_possess": false,            // start in possession mode (optional)
  "champion": {                    // overrides for the champion in lair.tscn
    "max_hp": 60, "damage": 14, "move_speed": 5.0,
    "position": [x, y, z]          // optional starting position
  },
  "raiders": [                     // replaces the lair's raiders
    {"position": [x, y, z], "max_hp": 25, "damage": 8, "move_speed": 3.8},
    ...
  ],
  "inputs": [                      // ProbeBot script (optional)
    {"t": 0.5, "press": "possess_toggle", "note": "log line"},
    {"t": 0.6, "release": "possess_toggle"},
    {"t": 1.0, "press": "move_forward"},
    {"t": 3.0, "release": "move_forward"}
  ],
  "pass_criteria": {               // any non-empty subset
    "champion_alive": true,
    "raiders_killed_eq": 3,        // exact count
    "raiders_killed_gte": 1,       // minimum
    "max_duration_lte": 5.0        // simulation must end within N seconds
  }
}
```

`inputs` actions must be names registered in `project.godot`'s InputMap (e.g. `move_forward`, `move_back`, `move_left`, `move_right`, `attack`, `dodge`, `possess_toggle`).

## Result JSON shape

```jsonc
{
  "scenario": "baseline",
  "end_reason": "all_raiders_dead | champion_dead | timeout",
  "duration_s": 1.10,
  "victory": true,
  "pass": true,
  "pass_reasons": [],              // populated on fail with which criterion missed
  "champion": {
    "alive": true,
    "hp_remaining": 112.0,
    "hits_taken": 1
  },
  "raiders": {
    "initial": 2,
    "killed": 2,
    "hits_received": 4
  },
  "dodges_used": 0
}
```

## Built-in scenarios

| File | Purpose | Expected |
|---|---|---|
| `tutorial.json` | Smoke test: AI champion vs 1 weak raider | win in <25s |
| `baseline.json` | Regression: AI champion (buffed) vs 2 raiders | win in <30s |
| `overrun.json` | Loss path: 10 raiders vs default champion | champion dies |
| `bot_smoketest.json` | ProbeBot input driver test | timeout, no crash |
| `slice_difficulty.json` | Slice fairness: 1v3 at default stats expected to fail | champion dies (intended) |

## Determinism

Same scenario JSON + same seed → byte-identical results JSON. CI verifies this implicitly (every PR re-runs all scenarios; flakes fail the build). To verify locally, run the same scenario 2-3 times and `diff` the result files.

## Adding a scenario

1. Drop a new `<name>.json` in this directory.
2. Add `<name>` to the loop in `.github/workflows/ci.yml`.
3. Run locally:
   ```sh
   godot --headless ++ --scenario=res://scenarios/<name>.json --output=/tmp/r.json
   echo "exit=$?"
   cat /tmp/r.json
   ```

## Limitations

- The AI champion has no kiting/dodging; multi-raider fights at slice stats overwhelm it.
- ProbeBot drives `Input.action_press/release` but cannot synthesise mouse motion. Sequences are evaluated each `_physics_process` tick (60 Hz default).
- Scenarios run inside the existing `lair.tscn` — they cannot test other levels until those exist.
