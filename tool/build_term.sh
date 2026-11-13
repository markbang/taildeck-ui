#!/usr/bin/env bash
# Builds the libghostty-vt C shim (native/term/term_ffi.c) as a shared library
# (a static lib on iOS) for the Flutter hosts, mirroring tool/build_native.sh.
#
#   tool/build_term.sh                     # linux/amd64 + android/arm64
#   tool/build_term.sh linux
#   tool/build_term.sh android         # arm64-v8a
#   tool/build_term.sh android-x86_64  # x86_64 (emulators)
#   tool/build_term.sh windows             # x86_64-windows-gnu via Zig
#   tool/build_term.sh macos               # universal dylib (needs Xcode)
#   tool/build_term.sh ios                 # arm64 static lib (needs Xcode)
#   tool/build_term.sh all                 # every target the host can build
#
# The static libghostty-vt.a comes from native/term/build-ghostty.sh (run here
# for the requested ABIs when missing). Outputs are git-ignored and ship with
# each Flutter bundle. A missing toolchain skips its target with a message.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GHOSTTY_OUT="${GHOSTTY_OUT:-$ROOT/native/term/build/ghostty}"
BUILD_DIR="$ROOT/native/term/build"
ZIG="${ZIG:-$(command -v zig || true)}"

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=(linux android)
elif [ "${TARGETS[0]}" = "all" ]; then
  TARGETS=(linux android android-x86_64 windows macos ios)
fi

LINUX_OUT="$ROOT/linux/lib/libtaildeck_term.so"
WINDOWS_OUT="$ROOT/windows/lib/taildeck_term.dll"
MACOS_DIR="$ROOT/macos/Frameworks"
IOS_DIR="$ROOT/ios/Frameworks"

die() { echo "build_term: $*" >&2; exit 1; }

ghostty_lib() {
  local abi=$1 lib="$GHOSTTY_OUT/lib/$1/libghostty-vt.a"
  if [ ! -f "$lib" ]; then
    echo "build_term: $abi libghostty-vt.a missing, running native/term/build-ghostty.sh $abi" >&2
    GHOSTTY_OUT="$GHOSTTY_OUT" native/term/build-ghostty.sh "$abi" >&2
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

build_android_abi() {
  local abi=$1 ccarch=$2 ndk bin cc lib out
  ndk="$(find_ndk)"
  if [ -z "$ndk" ]; then
    echo "android/$abi: skipped, no NDK (set ANDROID_NDK_HOME or install into \$ANDROID_SDK_ROOT/ndk)"
    return 0
  fi
  bin="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
  # API 24 matches the app's minSdk; fall back to 26 when the NDK lacks it.
  cc="$bin/${ccarch}-linux-android24-clang"
  [ -x "$cc" ] || cc="$bin/${ccarch}-linux-android26-clang"
  if [ ! -x "$cc" ]; then
    echo "android/$abi: skipped, $cc missing"
    return 0
  fi
  lib="$(ghostty_lib "$abi")"
  out="$ROOT/android/app/src/main/jniLibs/$abi/libtaildeck_term.so"
  echo "android/$abi (NDK $(basename "$ndk")): $out"
  mkdir -p "$(dirname "$out")"
  "$cc" "${CFLAGS[@]}" -I"$GHOSTTY_OUT/include" native/term/term_ffi.c "$lib" \
    -o "$out" -lm
}

build_android() { build_android_abi arm64-v8a aarch64; }
build_android_x86_64() { build_android_abi x86_64 x86_64; }

build_windows() {
  if [ -z "$ZIG" ]; then
    echo "windows/x86_64: skipped, no Zig (set ZIG=/path/to/zig)"
    return 0
  fi
  local lib out work
  lib="$(ghostty_lib windows-x86_64)"
  out="$WINDOWS_OUT"
  work="$BUILD_DIR/windows"
  echo "windows/x86_64 (zig cc): $out"
  mkdir -p "$(dirname "$out")" "$work"
  # Ghostty exports dllimport symbols when the headers see _WIN32 unless the
  # static build is announced, so the archive stays linkable.
  "$ZIG" cc -target x86_64-windows-gnu -shared -O2 -Wall -Wextra \
    -DGHOSTTY_STATIC -I"$GHOSTTY_OUT/include" -Inative/term \
    native/term/term_ffi.c "$lib" -o "$work/taildeck_term.dll"
  cp "$work/taildeck_term.dll" "$out"
}

xcode_present() {
  [ "$(uname -s)" = "Darwin" ] && xcrun --find clang >/dev/null 2>&1
}

build_macos() {
  if ! xcode_present; then
    echo "macos: skipped, needs macOS with Xcode (clang, lipo)"
    return 0
  fi
  local arch lib dylibs=() out
  out="$MACOS_DIR/libtaildeck_term.dylib"
  echo "macos/universal: $out"
  mkdir -p "$MACOS_DIR" "$BUILD_DIR"
  for arch in arm64 amd64; do
    case "$arch" in
      arm64) lib="$(ghostty_lib macos-arm64)"; target=aarch64-macos ;;
      amd64) lib="$(ghostty_lib macos-x86_64)"; target=x86_64-macos ;;
    esac
    "$ZIG" cc -target "$target" -dynamiclib -O2 -Wall -Wextra \
      -DGHOSTTY_STATIC -I"$GHOSTTY_OUT/include" -Inative/term \
      native/term/term_ffi.c "$lib" \
      -Wl,-install_name,@rpath/libtaildeck_term.dylib \
      -o "$BUILD_DIR/libtaildeck_term-$arch.dylib"
    dylibs+=("$BUILD_DIR/libtaildeck_term-$arch.dylib")
  done
  lipo -create "${dylibs[@]}" -output "$out"
}

build_ios() {
  if ! xcode_present; then
    echo "ios: skipped, needs macOS with Xcode"
    return 0
  fi
  local lib out work
  lib="$(ghostty_lib ios-arm64)"
  out="$IOS_DIR/libtaildeck_term.a"
  work="$BUILD_DIR/ios"
  echo "ios/arm64 (static): $out"
  mkdir -p "$IOS_DIR" "$work"
  "$ZIG" cc -target aarch64-ios -c -O2 -Wall -Wextra \
    -DGHOSTTY_STATIC -I"$GHOSTTY_OUT/include" -Inative/term \
    native/term/term_ffi.c -o "$work/term_ffi.o"
  libtool -static -o "$out" "$work/term_ffi.o" "$lib"
  # Optional include from ios/Flutter/{Debug,Release}.xcconfig: -force_load
  # keeps the archive in the Runner binary even though no Swift code calls it.
  cat > "$ROOT/ios/Flutter/NativeTerm.xcconfig" <<EOF
// Generated by tool/build_term.sh ios; git-ignored.
OTHER_LDFLAGS = \$(inherited) -force_load "\$(SRCROOT)/Frameworks/libtaildeck_term.a"
EOF
}

for target in "${TARGETS[@]}"; do
  case "$target" in
    linux) build_linux ;;
    android) build_android ;;
    android-x86_64) build_android_x86_64 ;;
    windows) build_windows ;;
    macos) build_macos ;;
    ios) build_ios ;;
    *) die "unknown target '$target' (want all, linux, android, android-x86_64, windows, macos or ios)" ;;
  esac
done
