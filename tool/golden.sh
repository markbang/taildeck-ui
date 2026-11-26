#!/usr/bin/env bash
# The local UI loop: pump the app's animations frame by frame and compare them
# with the frames in test/golden/goldens/, in seconds instead of an emulator
# run. --update rewrites the goldens after an intended UI change; read the
# image diff before committing it.
# Usage: tool/golden.sh [--update] [extra flutter test args]
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
source tool/env.sh
flutter=${FLUTTER:-flutter}
args=()
for arg in "$@"; do
  case "$arg" in
    -u | --update) args+=(--update-goldens) ;;
    *) args+=("$arg") ;;
  esac
done
exec "$flutter" test test/golden ${args[@]+"${args[@]}"}
