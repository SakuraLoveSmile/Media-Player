import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.mediaplayer.media_player"
    // flutter_local_notifications 23 compiles against API 37 and refuses to be
    // consumed by an app built against an older platform (AAR metadata check),
    // so this is pinned above Flutter's default of 36. targetSdk stays on
    // Flutter's value: only the compile-time API surface moves.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 23 uses java.time behind a compatibility
        // wrapper, so its AAR refuses to be consumed without desugaring even
        // when no notification is ever scheduled.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Stable release signing lets a new APK overlay-install an older build, which
    // is required for the in-app updater. CI decodes the fixed keystore into
    // android/app/keystore.jks and writes android/app/key.properties; local
    // builds without it fall back to the debug key (no update continuity).
    val keystoreProperties =
        if (file("key.properties").exists()) {
            Properties().apply {
                file("key.properties").inputStream().use { load(it) }
            }
        } else {
            null
        }

    signingConfigs {
        create("release") {
            if (keystoreProperties != null) {
                storeFile = file(keystoreProperties.getProperty("storeFile")!!)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.mediaplayer.media_player"
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

    buildTypes {
        release {
            // Use the fixed release key when key.properties exists (CI/local
            // release builds); otherwise keep the debug key so `flutter run
            // --release` still works on a fresh checkout.
            signingConfig = if (keystoreProperties != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
