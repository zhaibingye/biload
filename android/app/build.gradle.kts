plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.biload.biload"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.biload.biload"
        manifestPlaceholders["biloadLabel"] = "biload"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseStore = System.getenv("BILOAD_KEYSTORE_PATH")
    signingConfigs {
        if (!releaseStore.isNullOrBlank()) {
            create("biloadRelease") {
                storeFile = file(releaseStore)
                storePassword = System.getenv("BILOAD_STORE_PASSWORD")
                keyAlias = System.getenv("BILOAD_KEY_ALIAS")
                keyPassword = System.getenv("BILOAD_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        getByName("debug") {
            // Native verification must never replace the user's signed-in app.
            applicationIdSuffix = ".dev"
            manifestPlaceholders["biloadLabel"] = "biload 开发版"
        }
        release {
            // CI can inspect unsigned packages. Public APKs must be built with
            // the persistent private key; never substitute a fresh debug key.
            signingConfig = if (releaseStore.isNullOrBlank()) null
                else signingConfigs.getByName("biloadRelease")
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
