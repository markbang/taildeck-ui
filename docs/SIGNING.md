# Signing

Android releases are signed with the same key as the Kotlin app (`markbang/taildeck` v0.1.0), so this client
installs over it as an upgrade instead of a second app.

## Android identity

| Field | Value |
| --- | --- |
| `applicationId` | `top.bangwu.taildeck` (unchanged from the Kotlin app) |
| `namespace` | `top.bangwu.taildeck_ui` (Kotlin package, unrelated to app identity) |
| `minSdk` | 26 (same as the Kotlin app) |
| version | from `pubspec.yaml`: `0.2.7+27` → `versionName=0.2.7`, `versionCode=27` |
| key alias | `taildeck` |
| certificate SHA-256 | starts with `A7:6A:FE:7F`; identical to the published Kotlin v0.1.0 APK |

`flutter build apk --split-per-abi` adds `1000 × ABI` to the version code (armeabi-v7a 1026, arm64-v8a 2026,
x86_64 4026); the universal APK and the AAB keep 26. Every one of them is above the Kotlin app's 25.

The full SHA-256 lives in `ANDROID_CERT_SHA256` in `.github/workflows/platform-release.yml`, where every built
APK and AAB is checked against it.

## Upgrading from the Kotlin app

An upgrade needs the same `applicationId`, the same signing certificate and a higher `versionCode`. All three
hold: Kotlin v0.1.0 is `top.bangwu.taildeck`, `versionCode=25` on this certificate, and this build is
`versionCode=26`. Installing the Flutter APK replaces the Kotlin app and keeps its data
(`/data/data/top.bangwu.taildeck`), including `services.json`, identities and logs.

To go back, install a Kotlin build whose version code is above the installed one; Android refuses downgrades.

## Keystore

`release.jks` and its passwords live outside the repository, mode `600`:

- keystore: `/root/secure/release.jks`
- passwords and alias: `/root/secure/env.sh` (`storePassword`, `keyAlias`, `keyPassword`)
- the Kotlin keystore backup notes are in the `taildeck` Space under `.signing/`

Losing the key means no further updates for existing installs, so keep the Space copy as the backup.

## Local release build

```bash
source /root/secure/env.sh
umask 077
printf 'storeFile=/root/secure/release.jks\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n' \
  "$storePassword" "$keyAlias" "$keyPassword" > android/key.properties

tool/build_native.sh android android-armv7 android-x86_64
tool/build_term.sh   android android-armv7 android-x86_64

flutter build apk --release --split-per-abi   # arm64-v8a, armeabi-v7a, x86_64
flutter build apk --release                   # universal
flutter build appbundle --release             # AAB
```

`android/key.properties` is git-ignored. Without it a release build stops with a message; debug builds keep the
debug key.

Check a build:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
aapt2 dump badging build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | head -1
```

## CI secrets

`.github/workflows/platform-release.yml` signs the Android job from four repository secrets:

| Secret | What it holds |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` |
| `ANDROID_KEY_ALIAS` | `taildeck` |
| `ANDROID_KEY_PASSWORD` | `keyPassword` |

The job writes the keystore to `android/app/release.jks` (mode `600`) and `android/key.properties` from those secrets
(`storeFile=release.jks` resolves from `android/app/`, where the app module lives),
builds the three split APKs, the universal APK and the AAB, then fails if any signature does not match
`ANDROID_CERT_SHA256`. The key exists only for the length of the job; nothing is committed.

## Desktop and iOS

Unsigned for now, which is why Windows and macOS warn on first launch and iOS ships a bare `Runner.app`:

- [ ] Windows: an Authenticode certificate and `signtool` in `platform-release.yml`.
- [ ] macOS: a Developer ID Application certificate, `codesign --deep --options runtime`, then notarization.
- [ ] iOS: an Apple Developer team, a provisioning profile, `flutter build ipa --export-options-plist`, TestFlight.
- [ ] Android: uploading the AAB to Play with the same keystore (Play App Signing issues its own key).

None of these block Android; each needs the user's own certificates.
