# 签名

Android 发布包与 Kotlin 版（`markbang/taildeck` v0.1.0）使用同一密钥签名，因此这个客户端是「升级」，不是第二个应用。

## Android 身份

| 字段 | 值 |
| --- | --- |
| `applicationId` | `top.bangwu.taildeck`（与 Kotlin 版一致） |
| `namespace` | `top.bangwu.taildeck_ui`（Kotlin 包名，与应用身份无关） |
| `minSdk` | 26（与 Kotlin 版一致） |
| 版本 | 取自 `pubspec.yaml`：`0.2.9+29` → `versionName=0.2.9`，`versionCode=29` |
| 密钥别名 | `taildeck` |
| 证书 SHA-256 | 以 `A7:6A:FE:7F` 开头，与已发布的 Kotlin v0.1.0 APK 相同 |

`flutter build apk --split-per-abi` 会在 versionCode 上加 `1000 × ABI`（armeabi-v7a 1026、arm64-v8a 2026、
x86_64 4026）；通用 APK 与 AAB 仍是 26。它们都高于 Kotlin 版的 25。

完整 SHA-256 写在 `.github/workflows/platform-release.yml` 的 `ANDROID_CERT_SHA256` 里，每个 APK 和 AAB
都会与它比对。

## 从 Kotlin 版升级

升级条件是「同一 `applicationId` + 同一签名证书 + 更高 `versionCode`」，三者都满足：Kotlin v0.1.0 是
`top.bangwu.taildeck`、`versionCode=25`、此证书；本客户端 `versionCode=26`。安装 Flutter APK 会覆盖 Kotlin
版并保留其数据（`/data/data/top.bangwu.taildeck`），包括 `services.json`、密钥与日志。

想退回 Kotlin 版，需要一个 `versionCode` 高于已安装版本（26）的 Kotlin 包；Android 不接受降级安装。

## 密钥库

`release.jks` 与口令都在仓库之外，权限 `600`：

- 密钥库：`/root/secure/release.jks`
- 口令与别名：`/root/secure/env.sh`（`storePassword`、`keyAlias`、`keyPassword`）
- Kotlin 版密钥库的备份说明在 `taildeck` Space 的 `.signing/` 下

密钥丢失就意味着现有安装无法再更新，Space 里的那份备份请保留。

## 本地发布构建

```bash
source /root/secure/env.sh
umask 077
printf 'storeFile=/root/secure/release.jks\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n' \
  "$storePassword" "$keyAlias" "$keyPassword" > android/key.properties

tool/build_native.sh android android-armv7 android-x86_64
tool/build_term.sh   android android-armv7 android-x86_64

flutter build apk --release --split-per-abi   # arm64-v8a、armeabi-v7a、x86_64
flutter build apk --release                   # 通用包
flutter build appbundle --release             # AAB
```

`android/key.properties` 已被 git 忽略。没有它时发布构建会直接报错停下；debug 构建仍用调试密钥。

检查产物：

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
aapt2 dump badging build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | head -1
```

## CI 使用的密钥

`.github/workflows/platform-release.yml` 的 Android 任务用四个仓库 secret 签名：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` |
| `ANDROID_KEY_ALIAS` | `taildeck` |
| `ANDROID_KEY_PASSWORD` | `keyPassword` |

任务把密钥库写到 `android/app/release.jks`（权限 `600`），用这些 secret 生成 `android/key.properties`
（`storeFile=release.jks` 相对 `android/app/` 解析），构建三个
拆分 APK、通用 APK 与 AAB，然后逐个比对签名与 `ANDROID_CERT_SHA256`，不一致即失败。密钥只在任务运行期间
存在，不会提交。

## 桌面端与 iOS

目前未签名：Windows 与 macOS 首次启动会告警，iOS 只给出未签名的 `Runner.app`。

- [ ] Windows：Authenticode 证书 + `platform-release.yml` 里的 `signtool`。
- [ ] macOS：Developer ID Application 证书，`codesign --deep --options runtime`，再做公证。
- [ ] iOS：Apple 开发者团队、描述文件，`flutter build ipa --export-options-plist`，TestFlight。
- [ ] Android：同一密钥上传 Play（Play App Signing 会另发新密钥）。

这些都不阻塞 Android，每一件都需要用户自己的证书。
