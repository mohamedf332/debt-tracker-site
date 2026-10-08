plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Declared with `apply false` so it is on this project's classpath; it is
    // applied below only when google-services.json exists (otherwise the
    // google-services task fails the build with "file not found").
    id("com.google.gms.google-services") apply false
}

android {
    namespace = "com.example.debt_tracker"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.debt_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    
    // Workaround for media_store_plus 0.1.3 transitive dependency issue
    configurations.all {
        resolutionStrategy.force("androidx.exifinterface:exifinterface:1.4.1")
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

// google-services.json is generated per-project from Firebase / Google Cloud
// Console. Apply the plugin only when the file is present so the build keeps
// working before the config is dropped in.
//
// NOTE: google_sign_in reads the generated `default_web_client_id` string to
// build GoogleSignInOptions. Without this file, Google Sign-In will fail.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn(
        "google-services.json not found in android/app/ - " +
        "Google Sign-In will not work until you add it."
    )
}
