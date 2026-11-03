# Jetpack Arena — Brainstorm (parked, post-MVP)

Source: PRD §§13–15 (Future Considerations, Risks & Mitigations, Appendix).
Every idea below is **out of MVP scope**. The MVP contract is the PRD
checkbox list; this file exists so good ideas are parked, not scheduled
(see PRD §14 risk 4, scope creep). No dates, no owners, no commitments.

## Prioritized top 5

1. **Team Deathmatch vs bots** — same arenas and Pilot/Command seam, two
   squads instead of FFA. Validates the sim beyond free-for-all before any
   netcode spend. *(PRD §13 v1.0 content)*
2. **Signature differentiator: destructible cover OR grapple-dash** —
   validate via playtest data before committing to either. Differentiation
   vs SKYSCRAP is deliberately deferred to post-MVP validation. *(PRD §13)*
3. **Online multiplayer FFA netcode (8 players)** — dedicated
   authoritative server (Godot headless Linux) or listen-servers; the
   Command/Pilot seam makes bot↔human input swappable, so start with FFA.
   *(PRD §13; PRD §8 architecture note)*
4. **Mobile/touch ring-based controls (SKYSCRAP pattern)** — only if
   portal data shows demand. Touch is the largest control-system risk
   after gamepad, so it stays parked until metrics justify it. *(PRD §13)*
5. **Portal ladder: itch.io metrics → CrazyGames / Poki pitch** — capture
   load-time and engagement metrics on itch first, then pitch the
   CrazyGames dev portal (ad rev-share) and Poki; Bolt Pit benchmark is
   ~$15k ad revenue at 1–15M plays. *(PRD §13, §14 risk 5)*

## Parked ideas 6–15 (unordered)

6. **Two more maps** — new spawn layouts and pickup routes on the same
   greybox pipeline (8 spawns, pickup layout, distinct identity per map).
   *(PRD §13 v1.0 content)*
7. **Two to three more weapons (SMG, railgun)** — new WeaponResource
   tunables through the existing equip/ammo seam, no soldier changes.
   *(PRD §13 v1.0 content)*
8. **Gamepad-focused polish** — rumble, refined stick response curves,
   expanded pad affordances beyond the MVP parity bindings. *(PRD §13)*
9. **Private rooms and parties** — player-hosted matches with invite
   codes, building on the online suite. *(PRD §15 reference study)*
10. **Spectate mode** — watch live matches; doubles as the bot-quality
    spectate test from the AI risk mitigation. *(PRD §14 risk 2, §15)*
11. **Wi-Fi LAN beta** — local-network matches as a low-infrastructure
    stepping stone to full online play. *(PRD §15 reference study)*
12. **Daily challenges** — rotating goals (e.g. win with a weapon quota)
    for retention without new systems. *(PRD §13 meta & retention)*
13. **XP/levels and cosmetic unlocks** — SKYSCRAP-verified retention
    hooks, cosmetics only, never power. *(PRD §13 meta & retention)*
14. **Load-time / engagement metrics dashboard** — instrument the web
    build so map, weapon, and differentiator decisions run on playtest
    data instead of opinion. *(PRD §13 portal strategy, §14 risk 5)*
15. **Devlog and community playtesting cadence** — r/gamedev posts and
    the itch feed as the discoverability engine; first-3-playtester
    rituals extended to every release. *(PRD §14 risk 5, Phase 4)*

*Status: parked. Revisit only after MVP ships and portal metrics exist.*
