import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties (storeFile, storePassword,
// keyAlias, keyPassword), which is never committed. Without it a release
// build FAILS (see the task graph check below), unless it is asked for
// explicitly with -PallowDebugSignedRelease=true (flutter build ... -P
// allowDebugSignedRelease=true): then it is signed with the debug key, which
// cannot update the released app. CI builds that way and re-signs the
// APK in its `sign` job (.github/workflows/android.yml).
val allowDebugSignedRelease =
    providers.gradleProperty("allowDebugSignedRelease").orNull == "true"
val keyProperties =
    Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }

android {
    namespace = "io.github.swz0103.expensetracker"
    // Written out rather than taken from Flutter's defaults, so a Flutter
    // upgrade cannot move them unseen (Flutter 3.47.5 gives 36, 24, 36).
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Tests on a phone or the emulator (src/androidTest), run by emulator.yml.
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        applicationId = "io.github.swz0103.expensetracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two builds of the same app (the package name is the same for now):
    //   sideload  what is published on GitHub Releases: it updates itself
    //             (src/sideload: UpdateHandler.kt, UpdateWorker.kt, the
    //             REQUEST_INSTALL_PACKAGES permission, the FileProvider path
    //             of the downloaded APK).
    //   play      for Google Play, which does not allow an app to update
    //             itself by other means: none of that is in it (src/play
    //             has no-op stand-ins). Not published yet.
    // Dart reads the flavor as `appFlavor` (lib/src/core/platform/
    // distribution.dart).
    flavorDimensions += "distribution"
    productFlavors {
        create("sideload") { dimension = "distribution" }
        create("play") { dimension = "distribution" }
    }

    signingConfigs {
        if (!keyProperties.isEmpty()) {
            create("release") {
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Phones in use are 64-bit ARM: a release carries only that
            // architecture (as CI's --target-platform android-arm64 builds
            // it). Set here rather than in defaultConfig, so debug and
            // profile builds still run on the x86_64 emulator
            // (emulator.yml).
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
            // R8 keeps what is found by name at run time (WorkManager's
            // database and workers).
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Without the key only an explicit opt-in gets this far (the
            // check below the android block): then the debug key signs it.
            signingConfig =
                if (keyProperties.isEmpty()) {
                    signingConfigs.getByName("debug")
                } else {
                    signingConfigs.getByName("release")
                }
        }
    }
}

// A release APK or bundle without the release key is refused, so nobody
// ships (or is handed) one that the released app cannot be updated from.
gradle.taskGraph.whenReady {
    val packagesRelease =
        allTasks.any {
            it.project == project &&
                Regex("^(assemble|package|bundle)[A-Za-z]*Release$").matches(it.name)
        }
    if (packagesRelease && keyProperties.isEmpty && !allowDebugSignedRelease) {
        throw GradleException(
            "No release key: android/key.properties is missing, so this release " +
                "build would be signed with the debug key and could not update " +
                "the released app. Create android/key.properties (storeFile, " +
                "storePassword, keyAlias, keyPassword), or, to build a " +
                "debug-signed release on purpose (CI does, then re-signs it), " +
                "pass -PallowDebugSignedRelease=true.",
        )
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

dependencies {
    // BiometricPrompt for the Keystore key in MainActivity.kt.
    implementation("androidx.biometric:biometric:1.1.0")
    // Google sign-in for backups on Drive (drive.file), in MainActivity.kt.
    implementation("com.google.android.gms:play-services-auth:22.0.0")
    // X25519 and HKDF for sealing items into the ledger's inbox
    // (InboxWriter.kt), on every Android version the app runs on.
    implementation("com.google.crypto.tink:tink-android:1.15.0")
    // Reading paper e-invoices' QR codes with Google's scanner (ScanHandler.kt).
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    // Fetching that scanner on first use when the app was not installed
    // from Play (ModuleInstall in ScanHandler.kt).
    implementation("com.google.android.gms:play-services-base:18.5.0")
    // Backups delivered while the app is closed (BackupWorker.kt).
    implementation("androidx.work:work-runtime:2.9.1")
    testImplementation("junit:junit:4.13.2")
    // On the emulator: the Keystore, notifications and their alarms, photos,
    // the background backup (src/androidTest).
    // The versions integration_test brings (runner 1.3.0, rules 1.2.0, the
    // emulator workflow adds it): the debug build pins them for the tests.
    androidTestImplementation("androidx.test.ext:junit:1.1.2")
    androidTestImplementation("androidx.test:runner:1.3.0")
    androidTestImplementation("androidx.test:rules:1.2.0")
    // Runs the background backup job in the test, without waiting hours.
    androidTestImplementation("androidx.work:work-testing:2.9.1")
}
