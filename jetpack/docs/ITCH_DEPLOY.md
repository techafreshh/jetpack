# Deploying Jetpack Arena to itch.io

Step-by-step upload of the single-threaded Web build (`build/web.zip`) to an
itch.io page. No secrets or store credentials live in this repo; every upload
goes through the **butler** CLI.

## Prerequisites

- A fresh export: run `jetpack/tools/export_web.sh` from anywhere. It exports
  the `Web` preset to `build/web/index.html`, zips `build/web` to
  `build/web.zip`, and fails loudly if the zip exceeds 50 MiB
  (`<= 52428800` bytes gate).
- [butler](https://itchio.itch.io/butler) installed and on `PATH`. Verify with
  `butler version`, then authorize once with `butler login` (opens a browser).
  For CI, use a `BUTLER_API_KEY` secret instead of an interactive login.
- A local smoke test of the exact files you will ship (see below).

## 1. Smoke-test the export locally

```bash
cd jetpack
python3 tools/serve.py &          # serves build/web on http://127.0.0.1:8000/
curl --fail http://127.0.0.1:8000/health       # expect: OK JETPACK
curl --fail http://127.0.0.1:8000/index.html -o /dev/null
```

Then open http://127.0.0.1:8000/ in a browser and play one quick match:
first input (move/shoot) should respond in well under 10 seconds on a normal
connection. When done, stop the server (`Ctrl-C` / `kill %1`).

## 2. Create the itch.io project page

1. Go to `itch.io/game/new` (the page must exist before `butler push`).
2. Set **Kind of project** to **HTML** (required for browser-playable games).
3. Keep visibility at **Draft** (or Restricted for testers) until the page is
   finished.
4. Fill in title, short description, controls, and the viewport/embed size:
   **1280x720**. The game canvas is 1280x720 (`window/size/viewport_width`
   and `viewport_height` in `project.godot`); set the itch embed dimensions to
   **1280x720** so the game fills the frame with no scaling surprises.

## 3. Push the build with butler

Push the exported folder (butler diffs against the previous build and uploads
only what changed). `<user>/<game>` is the lowercase page address, and `html`
is the channel for the browser build:

```bash
cd jetpack
butler push ./build/web <user>/<game>:html --userversion 0.1.0
```

Replace `<user>/<game>` with your page address (e.g. `leafy/jetpack-arena`)
and bump `--userversion` on every release so players and the update API see a
version string you control. Preview without uploading via
`butler push-preview ./build/web <user>/<game>:html`, and inspect channels
with `butler status <user>/<game>`.

No SharedArrayBuffer toggle is needed: this build is single-threaded
(`variant/thread_support=false`), so it runs on the plain itch CDN with no
COOP/COEP isolation headers.

## 4. Finish the Edit game page, then Save

1. Tag the channel **playable in browser** (channel names alone never flip
   this switch, and neither does the `html` channel name flip the page Kind).
2. Confirm the page Kind is still **HTML**; otherwise the game shows as a
   download instead of launching in the browser.
3. Tick only platform tags you have actually run the build on.
4. Answer the AI generation disclosure section if any shipped content was
   made with generative AI, and classify adult content under
   *Metadata → Classification* if applicable.

## 5. Browser checklist (before every public push)

- **Firefox**: loads from a fresh profile, audio plays after first click,
  no console errors.
- **Chrome**: loads with cache disabled once, 1280x720 embed fills the
  frame, keyboard + mouse input responsive.
- **Safari**: loads over HTTPS, no blocked-mixed-content warnings, touchbar
  laptops still get keyboard events; note WebGL shader-compile hitches on
  first load are normal.

## 6. Size budget (<= 50 MiB)

`build/web.zip` must stay under 50 MiB (enforced by `export_web.sh`). If a
push approaches the limit:

- Prefer WebP textures over PNG for large sprites/backgrounds.
- Keep audio as short compressed clips (current SFX are 22050 Hz 16-bit mono
  WAVs under 0.5 s each); recompress longer tracks instead of shipping
  raw WAV.
- Trim unused assets and keep the preset's `export_filter` at
  `all_resources` only while the project is small; switch to filtered
  includes if test fixtures start bloating the `.pck`.

## 7. Updating later

Push to the **same** channel again (`butler push ./build/web
<user>/<game>:html --userversion <next>`); players on the itch app get a
differential patch automatically. Keep Draft visibility until a release is
verified live, and never rename the channel — a typo creates a second,
separate download slot.
