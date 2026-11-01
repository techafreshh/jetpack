# Vendored gamedev agent skills

Curated subset of [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills), vendored as plain files (Apache-2.0 — see `LICENSE` and `NOTICE` in this directory).

- **Upstream commit:** `19d93f97c9c1ea0f8b306e77aa81e0d3e352d3e9` (2026-10-28)
- **Godot skills target:** Godot 4.7

## Why these ten

Each maps to a phase of `.agents/PRDs/PRD.md`:

| Skill | PRD phase |
|---|---|
| `godot-gdscript` | All — typed GDScript conventions |
| `godot-2d-movement` | Phase 1 — CharacterBody2D rocket-boot controller |
| `physics-tuning` | Phase 1 — movement-feel iteration |
| `godot-export` | Phases 1 & 4 — web export, early smoke test |
| `godot-tilemap` | Phase 2 — arena construction |
| `game-ai` | Phase 3 — bot AI concepts |
| `ai-behavior-trees-utility-ai` | Phase 3 — BotPilot utility AI |
| `game-feel` | Phase 4 — juice pass |
| `itch-publish` | Phase 4 — deployment |
| `godot-gdscript-headless-testing` | All — headless test gates with real exit codes |

## Updating

Re-vendor rather than pull: clone the upstream repo, copy the folders over these, and update the commit hash above. Only add skills that map to PRD scope — engine/genre skills we don't use are intentionally excluded.
