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
    {"t": 3.0, "release": "move_forward"},
    // Direct method calls bypass input — useful for mechanics not bound to keys.
    // Path is relative to ProbeBot's parent (the lair root). Args are positional.
    {"t": 2.0, "call": "BuildController.place_at_xy", "args": [-4, -4, 0]}
  ],
  "pass_criteria": {               // any non-empty subset
    "champion_alive": true,
    "raiders_killed_eq": 3,        // exact count
    "raiders_killed_gte": 1,       // minimum
    "max_duration_lte": 5.0,       // simulation must end within N seconds
    "rooms_placed_eq": 3,          // BuildController.placed_count() == N
    "workers_assigned_eq": 2,      // workers with assigned_room set
    "workers_at_rooms_eq": 2,      // workers in WORKING state (arrived at room)
    "gold_gte": 5,                  // Economy.gold >= N
    "gold_eq": 0,                   // Economy.gold == N
    "possessed_name_eq": "Champion2" // Game.possessed.name == X (or "" for none)
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
  "dodges_used": 0,
  "rooms_placed": 0,               // unique rooms placed via BuildController
  "workers_assigned": 0,           // workers with assigned_room set
  "workers_at_rooms": 0,           // workers in WORKING state
  "gold": 0,                       // Economy.gold at scenario end
  "possessed": ""                  // node name of Game.possessed, or "" for none
}
```

### Multi-champion scenarios

By default, scenarios trim the lair to a single named "Champion" (Champion2 is freed at start). Pass `"multi_champion": true` to keep all champions — required for Phase 3 cycle-possession tests.

## Built-in scenarios

| File | Purpose | Expected |
|---|---|---|
| `tutorial.json` | Smoke test: AI champion vs 1 weak raider | win in <25s |
| `baseline.json` | Regression: AI champion (buffed) vs 2 raiders | win in <30s |
| `overrun.json` | Loss path: 10 raiders vs default champion | champion dies |
| `bot_smoketest.json` | ProbeBot input driver test | timeout, no crash |
| `slice_difficulty.json` | Slice fairness: 1v3 at default stats expected to fail | champion dies (intended) |
| `build_smoketest.json` | Phase 2 build mode: enter, select 3 room types, place 3 rooms via direct call, reject duplicate, exit | `rooms_placed == 3` |
| `worker_assignment.json` | Phase 2 worker auto-assignment: place 2 rooms, workers self-assign and walk to them | `workers_at_rooms == 2` |
| `economy.json` | Phase 2 Treasury gold tick (1g/s/worker) | `gold >= 5` after ~10s |
| `build_cost.json` | Phase 2 build economy: place 2 Treasuries (80g of 100), 3rd rejected | `rooms_placed == 2`, `gold == 20` |
| `cycle_possession.json` | Phase 3 entry: 2 Tabs cycle Champion → Champion2 | `possessed == "Champion2"` |
| `cycle_possession_release.json` | 3 Tabs cycle through both champions, then release | `possessed == ""` |
| `cleave_skill.json` | Phase 3 skill: K = cleave (wider hitbox, 1.5× damage). One swing one-shots two adjacent raiders | both raiders dead from a single press |
| `save_load.json` | Phase 2 milestone: place rooms → save to JSON → clear → load → state restored | `rooms_placed == 2`, `gold == 40` post-load |
| `training_bonus.json` | Phase 2 strategic payoff: Training room with worker grants champion +10 damage | `champion_damage == 28` (base 18 + 10) |
| `charge_skill.json` | Phase 3 skill: L = charge dash with i-frames, hits enemies along path for 1.2× damage | `raiders_killed == 1`, champion HP unchanged |
| `champion_xp.json` | Phase 4 entry: champion gains XP per kill = raider.max_hp; threshold = 50 × level | `champion_level == 2`, `champion_xp == 25` |
| `save_progression.json` | Save format v2: persists champion level/XP through save→reset→load round-trip | `champion_level == 2` post-load |

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
