#!/usr/bin/env bash
# Builds the Go tsnet bridge (native/bridge/cmd/cshared) for the Flutter hosts.
#
#   tool/build_native.sh            # linux/amd64 + android/arm64
#   tool/build_native.sh linux
#   tool/build_native.sh android         # arm64-v8a
#   tool/build_native.sh android-armv7   # armeabi-v7a (32-bit phones)
#   tool/build_native.sh android-x86_64  # x86_64 (emulators)
#   tool/build_native.sh windows    # x86_64-windows-gnu via mingw-w64
#   tool/build_native.sh macos      # universal dylib (needs Xcode)
#   tool/build_native.sh ios        # arm64 static lib (needs Xcode)
#   tool/build_native.sh all        # every target the host can build
#
# Outputs are git-ignored: linux/lib/ ships in the Linux bundle,
# android/app/src/main/jniLibs/ goes into the APK, windows/lib/ next to the
# runner exe, macos/Frameworks/ into the .app and ios/Frameworks/ into the
# iOS Runner. A missing toolchain skips its target with a message instead of
# failing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GO="${GO:-$(command -v go || echo /usr/local/go/bin/go)}"
TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=(linux android)
elif [ "${TARGETS[0]}" = "all" ]; then
  TARGETS=(linux android android-armv7 android-x86_64 windows macos ios)
fi

LINUX_OUT="$ROOT/linux/lib/libtaildeck_bridge.so"
WINDOWS_OUT="$ROOT/windows/lib/taildeck_bridge.dll"
MACOS_DIR="$ROOT/macos/Frameworks"
IOS_DIR="$ROOT/ios/Frameworks"
IOS_MIN="13.0"
MACOS_MIN="11.0"

# Same tags as the Kotlin app's build script: the NDK toolchain needs them.
ANDROID_TAGS="badlinkname,tfogo_checklinkname0"
ANDROID_LDFLAGS="-s -w -checklinkname=0"

die() { echo "build_native: $*" >&2; exit 1; }

[ -x "$GO" ] || die "go not found (set GO=/path/to/go)"
echo "go: $("$GO" version)"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
BUILD_DIR="$ROOT/native/bridge/build"

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

build_android_abi() {
  local abi=$1 goarch=$2 triple=$3 goarm=${4:-} ndk bin cc out
  ndk="$(find_ndk)"
  if [ -z "$ndk" ]; then
    echo "android/$abi: skipped, no NDK (set ANDROID_NDK_HOME or install into \$ANDROID_SDK_ROOT/ndk)"
    return 0
  fi
  bin="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
  # API 26 matches the app's minSdk.
  cc="$bin/${triple}26-clang"
  if [ ! -x "$cc" ]; then
    echo "android/$abi: skipped, $cc missing"
    return 0
  fi
  out="$ROOT/android/app/src/main/jniLibs/$abi/libtaildeck_bridge.so"
  echo "android/$abi (NDK $(basename "$ndk")): $out"
  mkdir -p "$(dirname "$out")"
  (cd native/bridge && CGO_ENABLED=1 GOOS=android GOARCH="$goarch" GOARM="$goarm" CC="$cc" \
    "$GO" build -buildmode=c-shared -trimpath \
    -tags "$ANDROID_TAGS" -ldflags "$ANDROID_LDFLAGS" \
    -o "$out" ./cmd/cshared)
}

build_android() { build_android_abi arm64-v8a arm64 aarch64-linux-android; }
build_android_armv7() { build_android_abi armeabi-v7a arm armv7a-linux-androideabi 7; }
build_android_x86_64() { build_android_abi x86_64 amd64 x86_64-linux-android; }

build_windows() {
  local cc
  cc="${CC_WINDOWS:-$(command -v x86_64-w64-mingw32-gcc || true)}"
  if [ -z "$cc" ]; then
    echo "windows/x86_64: skipped, no mingw-w64 (install mingw-w64 or set CC_WINDOWS)"
    return 0
  fi
  echo "windows/x86_64 ($cc): $WINDOWS_OUT"
  mkdir -p "$(dirname "$WINDOWS_OUT")"
  (cd native/bridge && CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC="$cc" \
    "$GO" build -buildmode=c-shared -trimpath -o "$WINDOWS_OUT" ./cmd/cshared)
}

xcode_present() {
  [ "$(uname -s)" = "Darwin" ] && xcrun --find clang >/dev/null 2>&1
}

sign_macos_dylib() {
  local lib=$1
  if ! command -v codesign >/dev/null 2>&1; then
    echo "macos: codesign missing, $lib stays unsigned"
    return 0
  fi
  # The Runner copies these into Taildeck.app and codesign rejects unsigned
  # nested code, so ad-hoc sign each dylib where it lands.
  codesign --force --sign - "$lib"
  codesign -dv "$lib" 2>&1 | sed -n 's/^Signature=/macos: /p'
}

build_macos() {
  if ! xcode_present; then
    echo "macos: skipped, needs macOS with Xcode (clang, lipo)"
    return 0
  fi
  local cc sdkroot arch carg cflags out dylibs=()
  cc="$(xcrun --find clang)"
  sdkroot="$(xcrun --show-sdk-path)"
  [ -d "$sdkroot" ] || die "macos: xcrun --show-sdk-path returned no SDK ($sdkroot)"
  # cgo does not pick the SDK up on its own: without -isysroot clang cannot
  # find the standard headers.
  export SDKROOT="$sdkroot"
  out="$MACOS_DIR/libtaildeck_bridge.dylib"
  echo "macos/universal ($cc): $out"
  echo "macos: SDKROOT=$sdkroot min=$MACOS_MIN"
  mkdir -p "$MACOS_DIR" "$BUILD_DIR"
  for arch in arm64 amd64; do
    carg=arm64
    if [ "$arch" = amd64 ]; then carg=x86_64; fi
    cflags="-isysroot $sdkroot -arch $carg -mmacosx-version-min=$MACOS_MIN"
    echo "macos/$arch: CGO_CFLAGS=\"$cflags\" CGO_LDFLAGS=\"$cflags\""
    (cd native/bridge && CGO_ENABLED=1 GOOS=darwin GOARCH="$arch" CC="$cc" \
      CGO_CFLAGS="$cflags" CGO_LDFLAGS="$cflags" \
      "$GO" build -buildmode=c-shared -trimpath \
      -o "$BUILD_DIR/libtaildeck_bridge-$arch.dylib" ./cmd/cshared)
    dylibs+=("$BUILD_DIR/libtaildeck_bridge-$arch.dylib")
  done
  lipo -create "${dylibs[@]}" -output "$out"
  lipo -info "$out"
  sign_macos_dylib "$out"
}

write_ios_link_config() {
  # Included by ios/Flutter/{Debug,Release}.xcconfig: -force_load keeps both
  # archives in the Runner binary even though no Swift code calls them.
  cat > "$ROOT/ios/Flutter/NativeBridge.xcconfig" <<EOF
// Generated by tool/build_native.sh ios; the committed default lists both
// archives from tool/build_native.sh and tool/build_term.sh.
LIBRARY_SEARCH_PATHS = \$(inherited) "\$(SRCROOT)/Frameworks"
OTHER_LDFLAGS = \$(inherited) -force_load "\$(SRCROOT)/Frameworks/libtaildeck_bridge.a" -force_load "\$(SRCROOT)/Frameworks/libtaildeck_term.a"
EOF
}

build_ios() {
  if ! xcode_present; then
    echo "ios: skipped, needs macOS with Xcode"
    return 0
  fi
  local sdk cc cflags out
  sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
  cc="$(xcrun --sdk iphoneos --find clang)"
  cflags="-isysroot $sdk -arch arm64 -mios-version-min=$IOS_MIN"
  out="$IOS_DIR/libtaildeck_bridge.a"
  echo "ios/arm64 ($cc): $out"
  echo "ios: SDKROOT=$sdk CGO_CFLAGS=\"$cflags\" CGO_LDFLAGS=\"$cflags\""
  mkdir -p "$IOS_DIR"
  (cd native/bridge && CGO_ENABLED=1 GOOS=ios GOARCH=arm64 CC="$cc" \
    CGO_CFLAGS="$cflags" \
    CGO_LDFLAGS="$cflags" \
    "$GO" build -buildmode=c-archive -trimpath -o "$out" ./cmd/cshared)
  write_ios_link_config
}

for target in "${TARGETS[@]}"; do
  case "$target" in
    linux) build_linux ;;
    android) build_android ;;
    android-armv7) build_android_armv7 ;;
    android-x86_64) build_android_x86_64 ;;
    windows) build_windows ;;
    macos) build_macos ;;
    ios) build_ios ;;
    *) die "unknown target '$target' (want all, linux, android, android-armv7, android-x86_64, windows, macos or ios)" ;;
  esac
done
