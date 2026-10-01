plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val syntheticValidation = providers.gradleProperty("v2SyntheticValidation").orNull == "true"
val releaseSigningEnabled =
    providers.gradleProperty("v2EnableReleaseSigning").orNull == "true"

fun requiredReleaseEnvironment(name: String): String =
    providers.environmentVariable(name).orNull?.takeIf { it.isNotBlank() }
        ?: error("$name is required when v2EnableReleaseSigning=true")

val releaseApplicationId =
    if (releaseSigningEnabled) requiredReleaseEnvironment("V2_RELEASE_APPLICATION_ID") else null

android {
    namespace = "dev.expensetracker.preview"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = releaseApplicationId ?: "dev.expensetracker.preview"
        manifestPlaceholders["v2AppLabel"] =
            if (releaseSigningEnabled) "記帳 V2" else "記帳 V2 試用版"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningEnabled) {
            create("v2Release") {
                storeFile = file(requiredReleaseEnvironment("V2_RELEASE_STORE_FILE"))
                storePassword = requiredReleaseEnvironment("V2_RELEASE_STORE_PASSWORD")
                keyAlias = requiredReleaseEnvironment("V2_RELEASE_KEY_ALIAS")
                keyPassword = requiredReleaseEnvironment("V2_RELEASE_KEY_PASSWORD")
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
        getByName("debug") {
            if (syntheticValidation) {
                applicationIdSuffix = ".synthetic"
                manifestPlaceholders["v2AppLabel"] = "記帳 V2 合成測試"
            }
        }
        getByName("release") {
            if (releaseSigningEnabled) {
                signingConfig = signingConfigs.getByName("v2Release")
            }
        }
    }

}

// Release stays absent unless CI or the key owner explicitly opts in and
// provides every long-term signing value. Debug builds never inherit it.
androidComponents {
    beforeVariants(selector().withBuildType("release")) {
        it.enable = releaseSigningEnabled
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
