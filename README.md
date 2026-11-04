# Jetpack Arena

[![CI](https://github.com/techafreshh/jetpack/actions/workflows/ci.yml/badge.svg)](https://github.com/techafreshh/jetpack/actions/workflows/ci.yml)

2D side-view jetpack arena shooter built with Godot 4.7, web-first: instant aerial deathmatch against 7 bots, no lobby, no account.

**Why it exists:** open a browser tab and be flying and shooting within seconds — every time. One human pilot versus seven bots in a free-for-all arena, first to the score target (or best score when the clock expires) wins.

## Quickstart

Prerequisites: [Godot 4.7 stable](https://github.com/godotengine/godot/releases/tag/4.7-stable) on `PATH` (`godot --version` should print `4.7.stable`). For the web build you also need the 4.7 export templates installed (CI installs `web_release.zip` from the same release page).

```bash
git clone https://github.com/techafreshh/jetpack.git
cd jetpack
godot --headless --path jetpack --import   # verify the project imports clean
godot --path jetpack                       # boots boot.tscn ("JETPACK BOOT OK") -> main menu
```

Press **Play** in the main menu to start a match (`scenes/match.tscn`). **Setup** opens the match setup screen (difficulty, score target, time limit), **HowTo** shows the controls.

### Play the web build locally

```bash
bash jetpack/tools/export_web.sh           # exports Web preset -> jetpack/build/web/index.html, zips to jetpack/build/web.zip (fails if > 50 MiB)
cd jetpack && python3 tools/serve.py &     # serves build/web on http://127.0.0.1:8000/
curl --fail http://127.0.0.1:8000/health              # expect: OK JETPACK
curl --fail http://127.0.0.1:8000/index.html -o /dev/null
```

Then open http://127.0.0.1:8000/ in a browser and play a match. Stop the server with `Ctrl-C` / `kill %1` when done.

> [!NOTE]
> `tools/serve.py` is a static file server for smoke-testing the export — it is NOT a game server. There is no networked multiplayer; all opponents are local bots.

## Usage

### Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move | `A` / `D` or arrow keys | Left stick / D-pad |
| Fly (hold to climb) | `Space` or `W` (hold; release to fall) | `A` |
| Crouch | `S` or `Down` | `B` |
| Aim | Mouse | Right stick |
| Fire | Left mouse button | `RT` or `RB` |
| Grenade | `G` | `LB` |
| Reload | `R` | — |
| Weapons | `1`–`8` | — |

Source of truth for this table is the in-game HowTo screen (`jetpack/scenes/ui/howto.tscn`). Keybinds for move/crouch/fly/grenade/reload are remappable in Settings and persist to `user://settings.cfg`.

### Match rules

A match runs `countdown` → `live` → `results` (`jetpack/scripts/match/match_manager.gd`):

- Countdown is 3 s, then the match goes live.
- First pilot to the score target (default 25 kills) wins immediately.
- If the clock (default 5:00) expires, the leader wins.
- If the clock expires tied, sudden death latches: the clock extends by 30 s and the next kill wins at once.

Defaults live in `jetpack/resources/config/match.cfg` (`target_score=25`, `time_limit_s=300`, `sudden_death_s=30`, `bot_count=7`). The setup screen can override difficulty, target, and time limit for one match (persisted to `user://match_setup.cfg`).

### Weapons and grenades

Three data-driven weapons (`jetpack/resources/weapons/*.tres`, equipped via `scripts/weapons/weapon_resource.gd`). You spawn with the Ranger AR; the rest come from arena pickups.

| Weapon | Damage | Fire rate | Mag + reserve | Notes |
|---|---|---|---|---|
| Ranger AR | 12 | 10/s | 30 + 90 | Hitscan, range 1200 |
| Scatter | 5 × 8 pellets | 1.1/s | 6 + 24 | Projectile spread, range 500 |
| Longbow | 50 | 0.8/s | 5 + 15 | 2.5× zoom, range 2000 |

Grenades (`G`): 2.5 s fuse, up to 2 carried, 180 px blast radius for up to 60 damage (`jetpack/resources/config/grenade.cfg`). Health, ammo, grenade, and weapon pickups respawn on timers (`jetpack/resources/config/pickups.cfg`).

## Configuration

Only what the code actually reads:

- `PORT` — env var for the smoke-test server (`jetpack/tools/serve.py`, default `8000`). Flags: `python3 tools/serve.py [--port PORT] [--dir DIR]` (run from `jetpack/`; default dir is `build/web`).
- `BUTLER_API_KEY` — CI-side secret for `butler push` to itch.io (see `jetpack/docs/ITCH_DEPLOY.md`). No secrets live in the repo.
- `user://settings.cfg` — written by the Settings autoload (`jetpack/scripts/settings.gd`): `[audio]` `master_volume`/`music_volume`/`sfx_volume` (0.0–1.0), `[input]` remappable actions (`move_left`, `move_right`, `crouch`, `fly`, `throw_grenade`, `reload`), `[accessibility]` `colorblind_mode`/`reduced_flashing`/`aim_assist` plus `screen_shake`. Corrupt values fall back to compiled defaults.
- `user://match_setup.cfg` — setup-screen overrides (`difficulty`, `target_score`, `time_limit_s`) applied by `MatchManager` after the shipped config loads.
- Tunables under `jetpack/resources/config/` — `match.cfg`, `movement.cfg`, `bots.cfg` (per-difficulty `easy`/`standard`/`sharp` reaction and aim error), `grenade.cfg`, `pickups.cfg`, `spawns.cfg`, `fx.cfg`. Every loader falls back to compiled defaults if a file is missing or corrupt.

## Development

### Layout

```text
jetpack/
  scenes/            # boot.tscn (entry), main_menu.tscn, match.tscn, arena/, ui/ (setup, howto, hud, pause, standings, settings)
  scripts/
    pilots/          # Pilot base (Pilot.Command seam in pilot.gd:get_command), human_pilot.gd, bot_pilot.gd
    match/           # match_manager.gd (countdown/live/results), scoreboard.gd, spawner.gd
    weapons/         # weapon.gd, weapon_resource.gd (data-driven stats), grenade.gd
    ui/              # main_menu.gd, match_setup.gd (MatchSetup -> user://match_setup.cfg), howto.gd, hud.gd, ...
    settings.gd      # Settings autoload (user://settings.cfg)
    audio.gd         # Audio autoload   run_state.gd  # RunState autoload (last-match memory)
  resources/weapons/ # ranger_ar.tres, scatter.tres, longbow.tres
  resources/config/  # match/movement/bots/grenade/pickups/spawns/fx tunables
  assets/            # art + audio (see assets/art/ATTRIBUTION.md, assets/audio/LICENSE.md — CC0 synth SFX)
  tools/             # export_web.sh, serve.py, probe_server.py, make_sfx.py
  tests/             # headless SceneTree proofs (test_*.gd)
  docs/              # ITCH_DEPLOY.md (butler upload walkthrough)
```

Autoloads (in `project.godot`): `Settings`, `Audio`, `RunState`. Viewport is 1280×720 (`canvas_items` stretch); physics tick is 60 Hz.

### Tests

```bash
godot --headless --path jetpack --script res://tests/test_<name>.gd   # one headless proof, e.g. test_settings.gd, test_tips.gd
cd jetpack && python3 -m unittest tools.test_serve tools.test_probe_server -v
```

CI (`.github/workflows/ci.yml`) runs headless import, a UID-sidecar check, per-file GDScript checks, the web export with the `<= 52428800`-byte size gate, the Python suites, and a serve smoke test (`/health` must answer `OK JETPACK`).

### Deploy

See `jetpack/docs/ITCH_DEPLOY.md` for the itch.io flow: export with `jetpack/tools/export_web.sh`, smoke-test via `serve.py`, then `butler push ./build/web <user>/<game>:html --userversion <next>` (single-threaded build, 1280×720 embed, no COOP/COEP headers needed). Planning context lives in `.agents/PRDs/PRD.md`.

## Limitations

Not in the build (per PRD § Out of Scope, deferred): online multiplayer, mobile/touch controls, career meta (XP/levels/challenges), soldier customization, extra maps and weapons beyond the three, portal SDK/monetization/analytics, accounts and cloud saves, localization.
