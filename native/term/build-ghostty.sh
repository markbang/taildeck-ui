#!/usr/bin/env bash
# Builds libghostty-vt for the Flutter hosts (same pinned rev for all).
# GHOSTTY_OUT selects the output dir (default native/term/build/ghostty),
# GHOSTTY_SRC the checkout (reused when present).
# Needs Zig 0.17; the Android targets also need the NDK only for later linking.
set -euo pipefail
GHOSTTY_REV=83b57ac
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${GHOSTTY_OUT:-$ROOT/term/build/ghostty}"
SRC="${GHOSTTY_SRC:-${TMPDIR:-/tmp}/ghostty-src}"
if [ ! -d "$SRC/.git" ]; then
  git clone https://github.com/ghostty-org/ghostty "$SRC"
fi
# Fetch only when the pinned commit is absent: a fetch on every run stalls
# on a slow GitHub connection even though the checkout is already right.
if ! git -C "$SRC" cat-file -e "$GHOSTTY_REV^{commit}" 2>/dev/null; then
  git -C "$SRC" fetch --depth 1 origin "$GHOSTTY_REV" 2>/dev/null || true
fi
git -C "$SRC" checkout -q "$GHOSTTY_REV"
rm -rf "$OUT" && mkdir -p "$OUT/lib"
# abi:zig-target; the host entry is x86_64 glibc for the desktop bundle.
TARGETS=("arm64-v8a:aarch64-linux-android" "x86_64:x86_64-linux-android")
if [ "$(uname -s)-$(uname -m)" = "Linux-x86_64" ]; then
  TARGETS+=("linux-x86_64:x86_64-linux-gnu")
fi
find_ndk() {
  if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "$ANDROID_NDK_HOME" ]; then
    echo "$ANDROID_NDK_HOME"; return
  fi
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/opt/android-sdk}}"
  if [ -d "$sdk/ndk" ]; then
    ls -1d "$sdk"/ndk/*/ 2>/dev/null | sed 's:/$::' | sort -V | tail -1
  fi
}
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  ndk="$(find_ndk)"
  [ -n "$ndk" ] && export ANDROID_NDK_HOME="$ndk"
fi

for pair in "${TARGETS[@]}"; do
  abi=${pair%%:*}; target=${pair#*:}
  case "$target" in
    *-android)
      if [ -z "${ANDROID_NDK_HOME:-}" ]; then
        echo "ghostty: $abi skipped, no NDK (set ANDROID_NDK_HOME)"
        continue
      fi
      ;;
  esac
  echo "ghostty: $abi ($target)"
  (cd "$SRC" && zig build -Demit-lib-vt=true -Dtarget="$target" -Doptimize=ReleaseFast --prefix "$SRC/zig-out-$target")
  mkdir -p "$OUT/lib/$abi"
  cp "$SRC/zig-out-$target/lib/libghostty-vt.a" "$OUT/lib/$abi/"
done
cp -r "$SRC/include" "$OUT/include"
