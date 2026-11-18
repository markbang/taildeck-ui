#!/usr/bin/env bash
# Fails when demo data survives into a release build: the web preview and
# debug builds carry it, release builds on a phone or desktop must not.
#
#   tool/check_demo_free.sh build/linux/x64/release/bundle/lib/libapp.so
#   tool/check_demo_free.sh build/app/outputs/flutter-apk/app-release.apk
#
# The demo set lives behind `demoData` (lib/src/demo), a `const` that is false
# outside web/debug, so the compiler drops it. This checks the snapshot itself.
set -euo pipefail

[ $# -gt 0 ] || { echo "usage: tool/check_demo_free.sh <libapp.so|apk>..." >&2; exit 2; }

# Strings only the demo dataset and the demo terminal session contain.
needles=(
  "Tune Grafana alerts"
  "Add release workflow"
  "Bump headscale"
  "4 agents · 2 working"
  "pi-k3s"
  "win-gaming"
  "macbook-air"
  "pixel-9"
  "100.77.3.101"
  "tail4a2c"
  "grafana:11.3.0"
  "code-server:latest"
  "Synology DSM"
  "Jellyfin"
  "keep the body readable under the bars"
  "Why the cold-start dial fails"
)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail=0
for target in "$@"; do
  [ -s "$target" ] || { echo "::error::no such build: $target"; exit 1; }
  libs=()
  case "$target" in
    *.apk)
      unzip -q -o "$target" 'lib/*/libapp.so' -d "$work" || true
      while IFS= read -r lib; do libs+=("$lib"); done < <(find "$work" -name libapp.so | sort)
      [ ${#libs[@]} -gt 0 ] || { echo "::error::$target holds no libapp.so"; exit 1; }
      ;;
    *) libs=("$target") ;;
  esac
  for lib in "${libs[@]}"; do
    for needle in "${needles[@]}"; do
      if grep -qaF -- "$needle" "$lib"; then
        echo "::error::demo data in $lib: \"$needle\""
        fail=1
      fi
    done
    echo "checked $(basename "$lib") ($(stat -c%s "$lib") bytes) for ${#needles[@]} demo strings"
  done
done

[ "$fail" -eq 0 ] || { echo "::error::demo data reached a release build (see lib/src/demo/demo.dart)"; exit 1; }
echo "ok: no demo data in the release snapshots"
