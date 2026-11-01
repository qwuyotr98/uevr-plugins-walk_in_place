# UEVR Walk-in-Place

**English** | [简体中文](README.zh-CN.md)

A small **UEVR** Lua plugin that turns **stepping in place** into **forward movement**,
using only the headset pose. Made for VR players with limited play space who walk in
place to reduce motion sickness.

- No mocap, no controllers, no extra software;
- Single file — drop it in, delete it to uninstall.

---

## How it works

```
HMD pose (height + pitch)
   → remove slow drift (standing up / squatting / playspace movement)
   → band-pass + smoothing
   → peak detection: one peak = one step
   → step rate → stick magnitude (faster stepping = faster walking)
   → write to the left thumbstick
```

Nodding is rejected (pitch rate above a threshold), and standing still produces no steps.

---

## Install

**Option A (recommended)** — double-click `install.cmd`.
It copies the plugin into every `%APPDATA%\UnrealVRMod\*\scripts\` folder.

**Option B (manual)** — copy `walkinplace.lua` into

```
%APPDATA%\UnrealVRMod\<game>\scripts\
```

`<game>` is the profile name shown in UEVR (e.g. `HTGame`).

Then start the game and press **Reload Script** in the UEVR menu.

> If `%APPDATA%\UnrealVRMod` does not exist, UEVR has never injected a game on this
> machine. Inject once, quit, then install.

---

## Usage

1. In game: UEVR menu → **Walk in Place**;
2. Press **Calibrate**:
   - stand still for 4 s (`stand still 4s...`);
   - when it says `NOW STEP for 8s...`, step in place for 8 s;
   - it finishes with `done (noise X mm, step Y mm)`;
3. Step in place — you walk.

Live readout:

```
signal +12.4 mm  (recent amp 38.0 mm)
cadence 1.15/s   steps 27   stick 0.78   WALK
nod 6 deg/s   prom 15.2 mm
```

---

## Settings

| Slider | Default | Meaning |
|---|---|---|
| **Min rise (mm)** | 5 | Minimum vertical rise for one step. **Lower = more sensitive** |
| **Sensitivity x** | 0.30 | Adaptive threshold factor. **Lower = more sensitive** |
| **Min cadence (/s)** | 0.30 | Below this step rate, no movement |
| **Stop delay (s)** | 0.55 | How long to keep the stick after the last step |
| **Stick max** | 0.90 | Maximum walking speed |
| **Full speed at (/s)** | 2.20 | Step rate at which the stick is maxed |
| **Nod reject (deg/s)** | 60 | Pitch-rate gate to ignore head nodding |
| **Log to file** | off | Write debug lines to the log |

### Tuning cheatsheet

| Symptom | Fix |
|---|---|
| Stepping not detected | `Min rise` → 3, or `Sensitivity x` → 0.20 |
| Walks while standing still | `Min rise` → 8–10, `Sensitivity x` → 0.45 |
| Stutters between steps | `Stop delay` → 0.9 |
| Nodding triggers walking | `Nod reject` → 30 |
| Too slow | `Stick max` → 1.0 |

---

## Known limitation

The plugin injects the stick through UEVR's `on_xinput_get_state` callback.
If the game never loads `xinput1_3.dll`, that callback never fires — the panel works,
`WALK` lights up, but the character does not move.

Check the UEVR log (`%APPDATA%\UnrealVRMod\<game>\log.txt`) for:

```
[XInputHook] Failed to find xinput1_3.dll after 10 seconds
```

If that line is present, this plugin cannot work with that game.

---

## Troubleshooting

```powershell
Select-String -Path "$env:APPDATA\UnrealVRMod\<game>\log.txt" -Pattern 'walkinplace' | Select-Object -Last 10
```

Expected:

```
[walkinplace] loading v4, state file = ...
[walkinplace] registered on_pre_engine_tick
[walkinplace] registered on_xinput_get_state
[walkinplace] registered on_draw_ui
[walkinplace] loaded v4 (hmd=0)
```

- `Exception in on_draw_ui` → the UI code threw; read that line in full;
- nothing at all → the file is not in `scripts`, or the script was never reloaded.

---

## Uninstall

Delete `scripts\uevr_walkinplace.lua`. Nothing else is left behind.

---

## Notes

Personal use, interoperability only. No vendor code or assets are included.
MIT licensed — use, modify and share freely.
Software updates may break compatibility; adjust the script as needed.
