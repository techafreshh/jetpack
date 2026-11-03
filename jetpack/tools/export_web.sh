#!/bin/bash
# Export the Web preset and zip it with a 50 MiB size gate.
# Usage: jetpack/tools/export_web.sh   (run from anywhere; paths resolve from this script)
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
OUT="$BUILD_DIR/web/index.html"
ZIP="$BUILD_DIR/web.zip"
MAX_BYTES=52428800

mkdir -p "$(dirname "$OUT")"
godot --headless --path "$PROJECT_DIR" --export-release "Web" "$OUT"

if command -v zip >/dev/null 2>&1; then
  rm -f "$ZIP"
  (cd "$BUILD_DIR" && zip -qr web.zip web)
else
  python3 - "$BUILD_DIR" <<'EOF'
import os
import sys
import zipfile
build_dir = sys.argv[1]
zip_path = os.path.join(build_dir, "web.zip")
if os.path.exists(zip_path):
    os.remove(zip_path)
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, _dirs, files in os.walk(os.path.join(build_dir, "web")):
        for name in sorted(files):
            path = os.path.join(root, name)
            z.write(path, os.path.relpath(path, build_dir))
EOF
fi

SIZE="$(wc -c <"$ZIP")"
if [ "$SIZE" -gt "$MAX_BYTES" ]; then
  echo "web export too large: $SIZE bytes > $MAX_BYTES bytes (50 MiB)" >&2
  exit 1
fi
echo "WEB_EXPORT_OK $SIZE bytes -> $ZIP"
