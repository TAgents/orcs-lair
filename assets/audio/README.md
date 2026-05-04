# Audio assets

Drop CC0 `.wav` (or `.ogg`) files into this directory. The Audio autoload
(`scripts/audio.gd`) loads them by filename and plays them on the matching
gameplay event. Missing files fall back to the procedural synth tones from
PR #73, so the game ships with audible feedback even with no assets here.

## Expected files

| Filename       | Plays when                                     | Procedural fallback         |
|----------------|------------------------------------------------|-----------------------------|
| `swing.wav`    | champion melee swing (J / K / N) connects      | downward sine sweep         |
| `hit.wav`      | any orc / raider takes damage                  | noise burst                 |
| `loot.wav`     | item picked up (`Inventory.item_added`)        | rising chirp                |
| `level_up.wav` | research branch unlocked                       | C5/E5/G5 arpeggio           |
| `day_chime.wav`| `Clock.day_changed`                            | 440 Hz bell                 |
| `raid_alarm.wav`| `Lair.raid_started`                           | 220 Hz saw + 8 Hz tremolo   |
| `treasure.wav` | treasure chest looted (`looted` signal)        | rising two-octave chord     |

## Recommended sources

All packs below are CC0 (no attribution required, free to redistribute):

- **Kenney — [Impact Sounds](https://kenney.nl/assets/impact-sounds)** — covers `swing`, `hit`, `treasure`
- **Kenney — [Interface Sounds](https://kenney.nl/assets/interface-sounds)** — covers `loot`, `level_up`, `day_chime`
- **Kenney — [UI Audio](https://kenney.nl/assets/ui-audio)** — alt for menu / chime feedback
- **Kenney — [Sci-fi Sounds](https://kenney.nl/assets/sci-fi-sounds)** — covers `raid_alarm`

Pick any sample from the relevant pack, rename it to the filename above, drop
it here. Godot will import on next editor open and the loader will pick it up
automatically — no code changes needed.

## Verifying

After adding a file, run interactively:

```
/Applications/Godot.app/Contents/MacOS/Godot --path orcs-lair
```

Trigger the event (e.g. take damage to test `hit.wav`) and confirm the new
sample plays instead of the synth tone. Headless scenarios skip audio
entirely (`DisplayServer.get_name() == "headless"` short-circuit), so CI
remains deterministic.
