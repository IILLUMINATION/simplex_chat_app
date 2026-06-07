import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties for release signing.
// Create android/key.properties (NOT committed) with:
//   storeFile=/absolute/path/to/keystore.jks
//   storePassword=...
//   keyAlias=...
//   keyPassword=...
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.tanglex.chat"
    // Bumped from 35 to 36 — required by camera_android_camerax,
    // flutter_plugin_android_lifecycle, image_picker_android,
    // shared_preferences_android, video_player_android (transitive
    // androidx.activity:1.12.x, androidx.core:1.18.x).
    compileSdk = 36

    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.tanglex.chat"
        minSdk = 24
        // targetSdk also bumped to 36 to match compileSdk and stay aligned
        // with Play Console requirements for new apps in 2026.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use release signing if key.properties exists, otherwise fall back to debug
            // (CI will fail loudly if key.properties is missing in real release builds).
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
            // Native code must NOT be stripped/obfuscated — FFI symbols required.
        }
        debug {
            isMinifyEnabled = false
        }
    }

    // Split APKs by ABI to reduce size (Play AAB will handle this automatically,
    // but useful for sideload distribution).
    splits {
        abi {
            isEnable = false
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

flutter {
    source = "../.."
}
