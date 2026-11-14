import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material, written by CI (or a local release build) outside git;
// see docs/SIGNING.md.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties =
    Properties().apply {
        if (keystorePropertiesFile.exists()) {
            FileInputStream(keystorePropertiesFile).use { load(it) }
        }
    }
// storeFile resolves from this module's directory, not from android/.
val releaseStoreFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
val releaseSigningHelp =
    "Release builds need android/key.properties with storeFile, storePassword, keyAlias and keyPassword " +
        "(see docs/SIGNING.md). storeFile resolves from $projectDir, so release.jks means $projectDir/release.jks. " +
        "Debug builds keep working without it."

android {
    namespace = "top.bangwu.taildeck_ui"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications needs core library desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Same identity as the Kotlin app: the Flutter client upgrades over it.
        applicationId = "top.bangwu.taildeck"
        // Matches the Kotlin app's minSdk so the same devices are supported.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                // v2/v3 only: v1 (JAR) is not needed at minSdk 26.
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            // AGP 9 shrinks and obfuscates release builds unless told otherwise;
            // the JNI bridge is resolved by name, so keep R8 off (see proguard-rules.pro).
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Without this Gradle would silently debug-sign the release APK; fail instead.
gradle.taskGraph.whenReady {
    val releaseTaskRequested =
        allTasks.any {
            it.project == project && it.name.matches(Regex("(assemble|bundle|package|sign).*Release.*"))
        }
    if (releaseTaskRequested) {
        if (!keystorePropertiesFile.exists()) throw GradleException(releaseSigningHelp)
        val store = releaseStoreFile
        if (store == null || !store.isFile) {
            throw GradleException("Keystore $store does not exist. $releaseSigningHelp")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
