import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties (storeFile, storePassword,
// keyAlias, keyPassword), which is never committed; without it a release
// build is signed with the debug key.
val keyProperties =
    Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }

android {
    namespace = "io.github.swz0103.expensetracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.swz0103.expensetracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
            signingConfig =
                if (keyProperties.isEmpty()) {
                    signingConfigs.getByName("debug")
                } else {
                    signingConfigs.getByName("release")
                }
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

dependencies {
    // BiometricPrompt for the Keystore key in MainActivity.kt.
    implementation("androidx.biometric:biometric:1.1.0")
    // Google sign-in for backups on Drive (drive.file), in MainActivity.kt.
    implementation("com.google.android.gms:play-services-auth:22.0.0")
    // X25519 and HKDF for sealing items into the ledger's inbox
    // (InboxWriter.kt), on every Android version the app runs on.
    implementation("com.google.crypto.tink:tink-android:1.15.0")
    // Reading paper e-invoices' QR codes with Google's scanner (ScanPart.kt).
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    // Backups delivered while the app is closed (BackupWorker.kt).
    implementation("androidx.work:work-runtime:2.9.1")
    testImplementation("junit:junit:4.13.2")
}
