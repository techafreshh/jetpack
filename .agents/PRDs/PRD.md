# PRD: Jetpack Arena (working title)

**Status:** Draft v1 · 2026-11-01
**Owner:** techafresh
**Engine:** Godot 4.7 stable (pinned)
**Platforms:** Web (itch.io) first; desktop later

---

## 1. Executive Summary

**Jetpack Arena** (working title) is a 2D side-view arena shooter where every combatant flies on rocket boots. Inspired by [SKYSCRAP](https://play.skyscrap.fun/) — a polished "v0.1.0 in development" web shooter studied during discovery — it distills that game's proven core loop (jetpack movement + weapon pickups + short bot/online deathmatches) into a solo-dev-buildable, web-first title.

The player fights 7 AI bots in fast 3–5 minute matches (first to 25 kills, or leader when the clock runs out), grabbing weapons from crates and health from pads across a scrolling multi-screen arena. Movement is the product: rocket-boot flight with fuel management, momentum, and cover-to-cover aerial play must feel great within 60 seconds of first play.

**Core value proposition:** "Always a match" — instant, zero-signup aerial deathmatch fun in the browser. Believable bots mean no waiting on lobbies; short sessions and <10s load times fit how people actually play web games.

**MVP goal:** One map, three weapons, grenades, pickups, 7 bots with three difficulty tiers, complete match flow (HUD, kill feed, standings, pause, hold-to-confirm quit), and a <50MB single-threaded web export deployed to a hidden itch.io page for playtesting — the full "fun check" loop, shipped.

Differentiation vs. SKYSCRAP is deferred to post-MVP validation (signature mechanic candidates: destructible cover or grapple-dash), but the architecture is deliberately online-multiplayer-ready so bots can later be swapped for networked opponents without a rewrite.

---

## 2. Mission

> **Make aerial-combat joy instantly reachable: open a browser tab, and you're flying and shooting within ten seconds — every time, no lobby, no account.**

### Core principles

1. **Movement first.** If flying doesn't feel great, nothing else matters. Tuning time is engine time.
2. **Always a match.** Bots are a feature, not a fallback. No player ever waits.
3. **Respect the session.** Web players give you 3–5 minutes. Every design decision fits that window.
4. **Cheap content.** Weapons and maps are data, not code. Adding a gun should never require touching a state machine.
5. **Ship, then polish.** A playable build on itch.io in weeks, refined through real playtests — not months of private development.

---

## 3. Target Users

### Primary persona: "Browser Bopper" — casual web gamer (18–34)
- Plays on portals (CrazyGames, Poki, itch.io) during breaks; 3–15 minute sessions.
- Low tolerance for load times, signups, and tutorials; high tolerance for difficulty once hooked.
- Discovers games via portal front pages and shares — never searches for games by name.
- **Needs:** instant play, readable controls in seconds, a reason to replay within the same sitting.

### Secondary persona: "Indie Follower" — itch.io browser-game enthusiast (16–40)
- Follows indie devlogs (Reddit r/gamedev, itch.io feeds, YouTube devlogs); tries early builds and leaves feedback.
- Comfortable with keyboard+mouse; some use gamepads.
- **Needs:** a devlog-worthy hook, visible iteration, and the feeling their feedback matters.

### Tertiary persona: "The Developer" (you)
- Solo dev learning Godot while shipping something real; values architecture that won't be painted into a corner.

### Pain points addressed
| Pain point | How the product answers it |
|---|---|
| Multiplayer web games with dead lobbies | 7 believable bots; online is additive, never required |
| Long downloads/loads for browser games | <50MB single-threaded export, <10s to first input |
| Tutorials that block play | Contextual tips during the first match (SKYSCRAP pattern) |
| Web shooters that feel floaty or mushy | Movement tuning as the #1 engineering priority |

---

## 4. MVP Scope

### In Scope

**Core Functionality**
- [ ] Player controller: ground run, crouch, rocket-boot thrust with fuel tank (fast ground refuel), air control, gravity/momentum tuning
- [ ] Combat: hitscan and projectile weapons, grenades with arc + fuse, damage, knockback, death + respawn (3s, spawn-point selection away from enemies)
- [ ] Three data-driven weapons (`.tres` resources): Ranger-style AR (hitscan, 30/90), scatter shotgun (projectile spread), Longbow-style scoped rifle (high damage, zoom)
- [ ] Grenade slot (2 carried, restocked by pads)
- [ ] Pickups: weapon crates (ground + floating pads), health packs, grenade/ammunition pads
- [ ] 7 AI bots, 3 difficulty tiers (Easy / Standard / Sharp) sharing the exact same command interface as the human player
- [ ] One arena map: multi-screen scrolling, tower, bunkers, floating platforms, 8 spawn points, pickup pads (theme: own identity, not a SKYSCRAP map clone)
- [ ] Match flow: countdown → first to 25 kills or leader at 5:00 → results screen → instant rematch
- [ ] HUD: HP bar, ammo/reserve, grenade count, match timer, live standings, kill feed, crosshair, contextual tips (first match only)
- [ ] Pause menu: resume, restart (hold-to-confirm), quit (hold-to-confirm), settings
- [ ] Main menu: play (bot match), match setup (difficulty, score target, time), how-to-play, settings

**Technical**
- [ ] Pilot abstraction: `Pilot` interface producing per-tick commands; `HumanPilot` (input map) and `BotPilot` (AI) implement it — the netcode seam
- [ ] Weapon/map data-driven design; zero hard-coded weapon stats
- [ ] Settings persistence (volume, keybinds, accessibility) via `user://` (IndexedDB on web)
- [ ] Accessibility toggles: colour-blind palette (blue/orange), reduced flashing, aim assist (target-snap magnetism) toggle
- [ ] Fixed-timestep simulation where feasible for future determinism

**Deployment**
- [ ] Godot single-threaded web export preset, size budget ≤ 50MB
- [ ] Local HTTP smoke test; itch.io upload instructions + zip artifact; hidden playtest page
- [ ] Input support: keyboard+mouse and gamepad parity

### Out of Scope (deferred)
- [ ] Online multiplayer (FFA/TDM netcode, rooms, parties, spectate) — architecture only
- [ ] Mobile/touch UI (ring controls, phone-as-controller)
- [ ] Career meta: XP/levels, daily challenges, progression rewards
- [ ] Soldier customization (skins, loadouts)
- [ ] Additional maps (target: 3 at v1.0) and weapon variety beyond the three
- [ ] Portal SDK integration (CrazyGames/Poki), monetization, analytics
- [ ] Accounts, cloud saves, server infrastructure
- [ ] Localization

---

## 5. User Stories

1. **As a browser player, I want to be flying and shooting within 10 seconds of opening the page, so that I don't bounce before the fun starts.**
   *Example:* Click itch.io embed → menu loads → click Play → countdown ends → firing an AR at a jetpacking bot, all in under 10s on a mid-range laptop.

2. **As a player, I want rocket-boot flight with fuel that refuels on the ground, so that flying is a skill with rhythm rather than a permanent hover.**
   *Example:* Boost to a floating pad, fuel drains, land to refill fast — an enemy is camping the pad, so I hop back down and re-engage from cover.

3. **As a solo player, I want believable bot opponents that use cover, lead shots, and retreat to reload, so that the match feels like a real fight, not target practice.**
   *Example:* A Sharp-tier bot breaks off an engagement when its mag runs dry, repositions behind a bunker, and peeks with the sniper.

4. **As a player, I want a 5-minute match with a clear goal (first to 25), so that I can finish a complete session in one sitting.**
   *Example:* Timer at 4:48 shows "You 3 / 25 · 4th of 8"; a results screen with standings appears at 25 kills or 0:00, offering instant rematch.

5. **As a player, I want to grab different weapons from crates, so that combat stays varied within one match.**
   *Example:* Spawn with the AR, crack a crate for the shotgun for close-quarters tower fights, or take the Longbow for long sightlines — ammo and switching via Q/1-3.

6. **As a player, I want grenades and pickups to be readable and fair, so that deaths feel earned, not cheap.**
   *Example:* Grenades have an arc preview and audible fuse; health packs glow and respawn on a visible timer.

7. **As a colour-blind or flash-sensitive player, I want palette and effect options, so that the game is comfortable to play.**
   *Example:* Settings → Colour-blind (blue/orange) makes enemy/ally tracers distinct; "Reduced flashing" softens muzzle/explosion strobes.

8. **As an itch.io playtester, I want to leave feedback on a hidden page, so that the developer can iterate before public release.**
   *Example:* Comments on the hidden itch page feed a tuning list (movement feel, bot difficulty, TTK).

### Technical user stories
9. **As the developer, I want bots and the human player to share one command interface, so that future netcode can replace bot input with network input without touching combat code.**
   *Example:* `BotPilot.get_command(delta)` and `HumanPilot.get_command(delta)` both return `Command {move_x, fly, crouch, aim, fire, grenade, switch_to, reload}` consumed identically by the soldier scene.

10. **As the developer, I want weapons defined as data resources, so that adding a fourth weapon is a new `.tres` file, not new code.**
    *Example:* `resources/weapons/scatter.tres` (damage 5×8 pellets, ROF 1.1/s, spread 12°, mag 6/24) drops into any crate via export var.

---

## 6. Core Architecture & Patterns

### High-level approach
Godot 4.x, GDScript throughout (solo-dev velocity over C#); 2D `CharacterBody2D` actors; **command-based simulation** with a `Pilot` seam so the sim never reads raw input. Fixed physics tick (60 Hz); presentation (cameras, shake, particles) decoupled from simulation.

### Directory structure
```
jetpack/
├── project.godot            # input map, autoloads, web export preset
├── docs/                    # brainstorm notes, tuning logs
├── assets/
│   ├── art/                 # Kenney/itch CC0 packs (sprites, tiles)
│   └── audio/               # CC0 SFX + music
├── scenes/
│   ├── main_menu.tscn
│   ├── match.tscn           # arena + spawner + match manager
│   ├── arena/               # tilemap layers, spawn/pickup markers
│   ├── soldier.tscn         # shared by human + bots
│   ├── projectile.tscn      # grenades, pellet sim
│   ├── pickup.tscn          # crate / health / ammo variants
│   └── ui/                  # hud.tscn, standings, pause, results
├── scripts/
│   ├── pilots/              # pilot.gd (base), human_pilot.gd, bot_pilot.gd
│   ├── match/               # match_manager.gd, spawner.gd, scoreboard.gd
│   └── fx/                  # camera_shake.gd, hit_flash.gd
└── resources/weapons/       # ranger_ar.tres, scatter.tres, longbow.tres
```

### Key patterns
- **Pilot/Command seam (netcode-ready):** soldiers consume `Command` structs; input device (human, bot, later: network peer) is interchangeable. Server-authoritative online play later = run the same sim per peer with one authority.
- **Data-driven weapons:** `WeaponResource` (damage, ROF, spread, mag/reserve, projectile type, zoom) — no weapon logic branches on weapon identity.
- **Utility AI for bots:** score candidate actions (engage, seek cover, grab pickup, retreat/reload, reposition) each tick; difficulty scales reaction delay + aim error, not new code paths.
- **Autoload singletons:** `Settings` (persisted config), `Audio` (bus volume), `RunState` (match results between scenes). Nothing gameplay-critical in autoloads.
- **Hold-to-confirm UI component:** shared Button subclass with fill-ring (SKYSCRAP-verified pattern) for restart/quit.

---

## 7. Tools/Features (feature specifications)

### 7.1 Movement system
- Ground run: accel/decel tuned to ~2 body-widths of stop-slide; crouch halves height, blocks standing through gaps.
- Rocket boots: hold Fly for thrust; fuel drains ~2.5s full burn, refuels ~4× faster grounded (verified SKYSCRAP tip); thrust curve rewards bursts, not hovers.
- Air control: partial horizontal accel; momentum preserved for rocket-jump-style play.

### 7.2 Combat
- Hitscan AR: 30/90, 10 rps, mild spread bloom; tracer + impact FX mandatory.
- Shotgun (scatter): 8 pellets, kill window at close range, heavy self-knockback potential (movement tech).
- Longbow: slow ROF, 2-shot kill, right-mouse scope (zoom + reduced spread).
- Grenades: 2 max, arc preview, 2.5s fuse, radial damage + knockback (self-damage on, enables jumps).
- TTK baseline: AR ~0.5s of sustained hits at 100 HP; tune via playtests.

### 7.3 Bot AI (BotPilot)
- Perception: line-of-sight raycasts + threat memory (last-seen position, 3s decay).
- Actions: engage (strafe + fly-weave), seek cover when HP <40% or mag empty, contest crates/pads on timer, retreat, spawn-camp avoidance.
- Difficulty tiers: reaction delay (250/140/70ms), aim error (±8°/±4°/±1.5°), tactic mix weights.

### 7.4 Match manager
- Modes (MVP: FFA bots only): countdown → live → results; win at 25 kills or best score at 5:00; ties → sudden death 30s.
- Kill feed (last 4 events), live standings, per-life HUD death overlay with respawn countdown.

### 7.5 Settings & accessibility
- Volume (master/music/sfx), keybind remap, colour-blind palette, reduced flashing, aim assist toggle, screen-shake intensity slider.
- Persisted to `user://settings.cfg`; web persistence via IndexedDB.

---

## 8. Technology Stack

| Layer | Choice | Rationale |
|---|---|---|
| Engine | Godot 4.7 stable (pinned) | Free, strong 2D, first-class web export; version matches the vendored gamedev agent skills and the build snapshot |
| Language | GDScript | Fastest iteration; perf adequate at 8 actors |
| Art | Kenney CC0 packs + free itch packs | Cohesive look, zero art-skill dependency, swappable |
| Audio | Kenney audio / Sonniss GDC packs (CC0) | Free, licensed for commercial use |
| Storage | `user://settings.cfg` (ConfigFile) | Maps to IndexedDB on web; no backend |
| Export | Godot Web (single-threaded, GDScript) | No SharedArrayBuffer/COOP-COEP headers needed → itch.io-safe |
| Version control | git (repo initialized at scaffold) | Standard |
| Distribution | itch.io (hidden page → public) | Free, embeds web builds, comments for feedback |
| Later | CrazyGames SDK / Poki pitch, Godot HL multiplayer + dedicated server | Post-MVP (see §13) |

**Explicitly not** (MVP): C#/GDExtension, backend services, analytics SDKs, ad SDKs.

---

## 9. Security & Configuration

- **Auth:** none — no accounts, no server, nothing to authenticate in MVP.
- **Data:** only local settings; no PII collected; no third-party scripts in MVP build.
- **Config management:** all tunables (movement, weapons, bots, match rules) live in resources/config, not code constants; settings UI writes `user://settings.cfg`.
- **Security scope — in:** safe save/load (schema validation on load), no executable user content.
- **Security scope — out:** anti-cheat (irrelevant vs bots), network security, payments.
- **Deployment considerations:** single-threaded web export; test on Firefox + Chrome + Safari (web export quirks are real); keep build ≤50MB (WebP textures, compressed audio); itch.io iframe sizing 1280×720 min.

---

## 10. API Specification

No external APIs in MVP. The internal contracts that matter (and pre-figure netcode):

```gdscript
# scripts/pilots/pilot.gd
class_name Pilot
## One pilot produces one Command per simulation tick.
## Human (input map), Bot (AI), and future NetworkPilot all implement this.
func get_command(delta: float) -> Command: return Command.EMPTY

class Command:
    var move_x: float    # -1..1
    var fly: bool
    var crouch: bool
    var aim_point: Vector2
    var fire: bool       # held
    var grenade: bool    # edge-triggered
    var switch_to: int   # -1 none, else weapon slot
    var reload: bool
```

```gdscript
# resources/weapons/*.tres — WeaponResource
@export var display_name: String        # "Ranger AR"
@export var damage: float               # 12.0
@export var fire_rate: float            # shots/sec
@export var spread_deg: float
@export var mag_size: int / reserve: int
@export var projectile: enum {HITSCAN, PELLET}
@export var zoom: float                 # 1.0 = none (Longbow 2.5)
```

Match results (future portal/leaderboard API hook): `{kills, deaths, score, duration, difficulty}` emitted by MatchManager at match end.

---

## 11. Success Criteria

### MVP success definition
A stranger can open the itch.io page and complete ≥2 full matches voluntarily.

### Functional requirements
- [ ] Full match completes: countdown → combat → results → rematch, with 1 human + 7 bots
- [ ] Bots score kills in every playtest (target: Easy-tier bot averages ≥1 kill/30s vs other bots)
- [ ] All three weapons + grenades function; pickups respawn; no soft-locks
- [ ] Win condition (25 kills) and timer (5:00) both end matches correctly
- [ ] Settings persist across page reloads (web build)

### Quality indicators
- [ ] Web build ≤ 50MB; first interactive input < 10s on 20 Mbps connection
- [ ] 60 fps in-browser on mid-range laptop (Intel i5 + integrated graphics)
- [ ] Zero script errors in headless import/export and during a full match
- [ ] The "60-second fun check": a first-time player is flying and firing within 60s without reading docs

### User experience goals
- Movement tuning signed off by the developer's own "does this feel great?" bar before bots are built
- Deaths always attributable (clear tracers, readable grenades) — no "what killed me?" moments
- Playtesters report matches as "tight" (3–5 min), never "sloggy"

---

## 12. Implementation Phases

### Phase 1 — Foundation & Movement (~1–2 weeks)
**Goal:** Prove the core: flying and shooting feel great.
**Deliverables:**
- [ ] **Ship a CI workflow** (`.github/workflows/ci.yml`) that runs the Godot headless import + script parse/validation checks on every PR — the CI gate engages from the lap after this merges
- [ ] Godot project scaffold, input map, git init, folder structure
- [ ] Player controller: run/crouch/rocket-boot thrust/fuel/air control
- [ ] Grey-box test arena (tilemap, platforms, tower)
- [ ] Hitscan prototype weapon + target dummies
- [ ] Web export smoke test (early — de-risk deployment now)
**Validation:** Dev self-test: 10 minutes of flying/shooting with no boredom; export runs in browser.

### Phase 2 — Combat & Content (~1–2 weeks)
**Goal:** A complete arsenal and a real map.
**Deliverables:**
- [ ] WeaponResource system + AR/shotgun/Longbow
- [ ] Grenades, crates, health/ammo pads with respawn timers
- [ ] Damage/HP/death/respawn pipeline, spawn-point selection
- [ ] Final MVP map art-passed with 8 spawns + pickup layout
**Validation:** All weapons kill dummies; pickups cycle; TTK within target range.

### Phase 3 — Bots & Match Flow (~2 weeks)
**Goal:** The game plays itself convincingly; matches start and end.
**Deliverables:**
- [ ] Pilot interface refactor (human behind same command interface)
- [ ] BotPilot utility AI + 3 difficulty tiers
- [ ] MatchManager, scoreboard, kill feed, HUD, countdown, results, rematch
- [ ] Pause menu with hold-to-confirm; settings menu
**Validation:** spectating a bots-only match looks intentional; full match vs 7 Easy bots winnable but not trivial.

### Phase 4 — Polish & Ship (~1–2 weeks)
**Goal:** The publishable artifact.
**Deliverables:**
- [ ] Juice pass: screenshake, hit-stop, jetpack trails, muzzle flash, hit flash, CC0 audio pass
- [ ] Accessibility toggles + settings persistence on web
- [ ] Main menu, how-to-play, contextual first-match tips
- [ ] Size/perf budget pass; headless export clean
- [ ] itch.io deploy artifact produced (web export zip) + step-by-step upload instructions written — creating the hidden itch page and running butler are operator steps, out of factory scope (see Operator checklist)
**Validation:** Success criteria §11 all checked; first 3 external playtesters complete ≥2 matches.

*Total estimate: 5–8 weeks part-time solo.*

---

## 13. Future Considerations

- **v1.0 content:** 2 more maps, 2–3 more weapons (SMG, railgun), TDM vs bots, gamepad-focused polish.
- **Signature differentiator:** destructible cover OR grapple-dash — validate via playtest data before committing.
- **Online multiplayer:** dedicated authoritative server (Godot headless Linux) or listen-servers; Command/Pilot seam makes bot↔human input swappable; start with FFA, 8 players.
- **Meta & retention:** daily challenges, XP/levels, cosmetic unlocks (SKYSCRAP-verified hooks).
- **Portal strategy:** itch.io public release → capture load-time/engagement metrics → pitch CrazyGames dev portal (ad rev-share) and Poki; benchmark: ~$15k ad revenue at 1–15M plays (Bolt Pit case study).
- **Mobile/touch:** ring-based touch controls (SKYSCRAP pattern) if portal data shows demand.

---

## 14. Risks & Mitigations

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| 1 | **Movement feel never hits "great"** — the whole product rides on it | Fatal | Phase 1 is movement-only with a hard go/no-go self-test; steal tuning reference points (SKYSCRAP fuel/refuel ratios, thrust curve); iterate daily, keep a tuning log |
| 2 | **Bots feel dumb** → "always a match" promise collapses | High | Utility AI with observable intents (retreat, cover, contest); spectate-test bots-only matches; difficulty = aim error + reaction delay, never cheat-aim |
| 3 | **Web export size/perf blows budget** | Medium | Export smoke test in Phase 1 (not Phase 4); asset budget per category (textures WebP ≤15MB, audio ≤15MB); profile in Firefox/Chrome/Safari early |
| 4 | **Solo-dev scope creep** (online/meta/customization pulling forward) | High | PRD checkboxes are the contract; out-of-scope list reviewed before any new idea starts; brainstorm doc parks ideas instead of scheduling them |
| 5 | **No discoverability** — good game, zero players | Medium | Ship playtest page in Phase 4 regardless of polish; devlog the build (r/gamedev, itch feed); metrics from itch inform portal pitch quality |

---

## 15. Appendix

### Related documents
- Brainstorm ideation (15 ideas, prioritized top 5): `docs/BRAINSTORM.md` *(generated from discovery session — to be written alongside Phase 1)*
- Reference game study: [SKYSCRAP](https://play.skyscrap.fun/) — maps, match rules, hold-to-confirm UI, accessibility toggles, bot difficulty ladder, online suite (FFA/TDM, Wi-Fi LAN beta, private rooms, parties, spectate)

### Operator checklist (NOT sliceable into issues — requires human with VPS/external-account access)
1. **Build snapshot bake** (before the first lap): run `foreman bake jetpack` VPS-side so the `jetpack-base` snapshot contains Godot 4.7 + web export templates. Re-bake on engine upgrades.
2. **itch.io account + butler** (Phase 4): create the itch.io project page (hidden), install `butler`, run the upload — the factory delivers the export artifact + deploy instructions; the upload itself is operator-owned.
3. **Engine upgrades**: version bumps re-require the snapshot re-bake (operator) before laps touching export/run.

### Key external references
- [Godot 4.3+ web export (single-threaded, no SharedArrayBuffer)](https://godotengine.org/article/progress-report-web-export-in-4-3)
- [The hidden web game market (Game Developer)](https://www.gamedeveloper.com/business/the-huge-hidden-web-game-market-no-one-talks-about-and-how-to-get-in-)
- [Best places to publish a web game in 2026](https://app.cinevva.com/guides/publish-web-game)
- [CrazyGames Developer Portal](https://developer.crazygames.com)

### Assumptions on record
1. Working title "Jetpack Arena" is a placeholder; naming pass happens before public release.
2. Solo part-time development; timeline estimates assume ~10–15 h/week.
3. Godot 4.x latest stable remains web-export-viable through development (verify at each engine upgrade).
4. Free CC0 assets suffice for MVP; original art/commissions are a post-validation decision.
