#!/usr/bin/env bash
# Builds libghostty-vt for the Flutter hosts (same pinned rev for all).
# GHOSTTY_OUT selects the output dir (default native/term/build/ghostty),
# GHOSTTY_SRC the checkout (reused when present).
# Needs Zig 0.17; the Android targets also need the NDK only for later linking.
#
#   native/term/build-ghostty.sh                  # android + host linux
#   native/term/build-ghostty.sh windows-x86_64
#   native/term/build-ghostty.sh macos-arm64 ios-arm64
#
# Every non-Android ABI is cross-compiled by Zig, so any host can produce them.
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

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) HOST_ABI=linux-x86_64 ;;
  *) HOST_ABI="" ;;
esac

TARGET_ABIS=("$@")
if [ ${#TARGET_ABIS[@]} -eq 0 ]; then
  # Historical default: both Android ABIs plus the host linux one.
  TARGET_ABIS=(arm64-v8a x86_64)
  [ -n "$HOST_ABI" ] && TARGET_ABIS+=("$HOST_ABI")
fi

abi_target() {
  case "$1" in
    arm64-v8a) echo aarch64-linux-android ;;
    x86_64) echo x86_64-linux-android ;;
    linux-x86_64) echo x86_64-linux-gnu ;;
    windows-x86_64) echo x86_64-windows-gnu ;;
    macos-arm64) echo aarch64-macos ;;
    macos-x86_64) echo x86_64-macos ;;
    ios-arm64) echo aarch64-ios ;;
    *) echo "ghostty: unknown abi '$1'" >&2; return 1 ;;
  esac
}

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

for abi in "${TARGET_ABIS[@]}"; do
  target="$(abi_target "$abi")" || exit 1
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
  # Zig names the archive `.lib` for windows targets and `.a` everywhere else.
  if [ -f "$SRC/zig-out-$target/lib/libghostty-vt.a" ]; then
    cp "$SRC/zig-out-$target/lib/libghostty-vt.a" "$OUT/lib/$abi/"
  else
    cp "$SRC/zig-out-$target/lib/ghostty-vt-static.lib" "$OUT/lib/$abi/libghostty-vt.a"
  fi
done
mkdir -p "$OUT/include"
cp -r "$SRC/include/." "$OUT/include/"
