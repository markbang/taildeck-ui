#!/usr/bin/env bash
# Builds the Go tsnet bridge (native/bridge/cmd/cshared) for the Flutter hosts.
#
#   tool/build_native.sh            # linux/amd64 + android/arm64
#   tool/build_native.sh linux
#   tool/build_native.sh android
#
# Outputs are git-ignored: linux/lib/ ships in the Linux bundle,
# android/app/src/main/jniLibs/ goes into the APK. A missing toolchain skips
# its target with a message instead of failing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GO="${GO:-$(command -v go || echo /usr/local/go/bin/go)}"
GOOS_TARGETS=("$@")
[ ${#GOOS_TARGETS[@]} -eq 0 ] && GOOS_TARGETS=(linux android)

LINUX_OUT="$ROOT/linux/lib/libtaildeck_bridge.so"
ANDROID_OUT="$ROOT/android/app/src/main/jniLibs/arm64-v8a/libtaildeck_bridge.so"

# Same tags as the Kotlin app's build script: the NDK toolchain needs them.
ANDROID_TAGS="badlinkname,tfogo_checklinkname0"
ANDROID_LDFLAGS="-s -w -checklinkname=0"

die() { echo "build_native: $*" >&2; exit 1; }

[ -x "$GO" ] || die "go not found (set GO=/path/to/go)"
echo "go: $("$GO" version)"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"

build_linux() {
  if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
    echo "linux: skipped, no C compiler (cgo needs gcc/clang)"
    return 0
  fi
  echo "linux/amd64: $LINUX_OUT"
  mkdir -p "$(dirname "$LINUX_OUT")"
  (cd native/bridge && CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
    "$GO" build -buildmode=c-shared -trimpath -o "$LINUX_OUT" ./cmd/cshared)
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
  local ndk bin cc
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
  echo "android/arm64 (NDK $(basename "$ndk")): $ANDROID_OUT"
  mkdir -p "$(dirname "$ANDROID_OUT")"
  (cd native/bridge && CGO_ENABLED=1 GOOS=android GOARCH=arm64 CC="$cc" \
    "$GO" build -buildmode=c-shared -trimpath \
    -tags "$ANDROID_TAGS" -ldflags "$ANDROID_LDFLAGS" \
    -o "$ANDROID_OUT" ./cmd/cshared)
}

for target in "${GOOS_TARGETS[@]}"; do
  case "$target" in
    linux) build_linux ;;
    android) build_android ;;
    *) die "unknown target '$target' (want linux or android)" ;;
  esac
done
