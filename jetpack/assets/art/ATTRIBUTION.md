# Art attribution — Jetpack Arena MVP map (`scenes/arena/main.tscn`)

Tiles styled after the Kenney platformer / top-down tile packs
(https://kenney.nl/assets, CC0 — no attribution required, credited here
anyway). No Kenney binaries are vendored: the MVP ships flat-vector
`Polygon2D` tiles drawn in `main.tscn` so headless import stays clean and
the web export stays far under the 50 MB budget.

Dusk-teal identity palette (own look, not a SKYSCRAP clone):

- Floor teal-dark `#21595F` — `Color(0.13, 0.35, 0.38)`
- Platform sand `#D99E4D` — `Color(0.85, 0.62, 0.30)`
- Tower / bunker ember `#8C4033` — `Color(0.55, 0.25, 0.20)`
- Cap cream `#EBD1A3` — `Color(0.92, 0.82, 0.64)`
- Wall / ceiling deep dusk `#1A3842` — `Color(0.10, 0.22, 0.26)`
- Backdrop sky `#17293D`, hills `#24474D` / `#295254`

Collision geometry is cloned 1:1 from the proven
`scenes/arena/greybox.tscn` skeleton, so only the `Visual` colors plus the
non-colliding `Backdrop` decor differ.
