#!/usr/bin/env bash
# Builds the libghostty-vt C shim (native/term/term_ffi.c) as a shared library
# for the Flutter hosts, mirroring tool/build_native.sh.
#
#   tool/build_term.sh             # linux/amd64 + android/arm64
#   tool/build_term.sh linux
#   tool/build_term.sh android
#
# The static libghostty-vt.a comes from native/term/build-ghostty.sh (run here
# when missing). Outputs are git-ignored: linux/lib/ ships in the Linux bundle,
# android/app/src/main/jniLibs/ goes into the APK. A missing toolchain skips
# its target with a message instead of failing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GHOSTTY_OUT="${GHOSTTY_OUT:-$ROOT/native/term/build/ghostty}"

TARGETS=("$@")
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=(linux android)

LINUX_OUT="$ROOT/linux/lib/libtaildeck_term.so"
ANDROID_OUT="$ROOT/android/app/src/main/jniLibs/arm64-v8a/libtaildeck_term.so"

die() { echo "build_term: $*" >&2; exit 1; }

ghostty_lib() {
  local abi=$1 lib="$GHOSTTY_OUT/lib/$1/libghostty-vt.a"
  if [ ! -f "$lib" ]; then
    echo "build_term: $abi libghostty-vt.a missing, running native/term/build-ghostty.sh" >&2
    GHOSTTY_OUT="$GHOSTTY_OUT" native/term/build-ghostty.sh >&2
  fi
  [ -f "$lib" ] || die "libghostty-vt.a for $abi not found at $lib"
  echo "$lib"
}

CFLAGS=(-shared -fPIC -O2 -Wall -Wextra -s -Wl,--gc-sections -Inative/term)

build_linux() {
  if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
    echo "linux: skipped, no C compiler"
    return 0
  fi
  local cc lib
  cc="$(command -v cc || command -v gcc)"
  lib="$(ghostty_lib linux-x86_64)"
  echo "linux/amd64: $LINUX_OUT"
  mkdir -p "$(dirname "$LINUX_OUT")"
  "$cc" "${CFLAGS[@]}" -I"$GHOSTTY_OUT/include" native/term/term_ffi.c "$lib" \
    -o "$LINUX_OUT" -lm -lpthread
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

build_android() {
  local ndk bin cc lib
  ndk="$(find_ndk)"
  if [ -z "$ndk" ]; then
    echo "android/arm64: skipped, no NDK (set ANDROID_NDK_HOME or install into \$ANDROID_SDK_ROOT/ndk)"
    return 0
  fi
  bin="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
  # API 24 matches the app's minSdk; fall back to 26 when the NDK lacks it.
  cc="$bin/aarch64-linux-android24-clang"
  [ -x "$cc" ] || cc="$bin/aarch64-linux-android26-clang"
  if [ ! -x "$cc" ]; then
    echo "android/arm64: skipped, $cc missing"
    return 0
  fi
  lib="$(ghostty_lib arm64-v8a)"
  echo "android/arm64 (NDK $(basename "$ndk")): $ANDROID_OUT"
  mkdir -p "$(dirname "$ANDROID_OUT")"
  "$cc" "${CFLAGS[@]}" -I"$GHOSTTY_OUT/include" native/term/term_ffi.c "$lib" \
    -o "$ANDROID_OUT" -lm
}

for target in "${TARGETS[@]}"; do
  case "$target" in
    linux) build_linux ;;
    android) build_android ;;
    *) die "unknown target '$target' (want linux or android)" ;;
  esac
done
