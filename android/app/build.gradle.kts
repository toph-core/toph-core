plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "uz.yurtal.maryaipos.mary_ai_pos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uchun zarur — java.time va boshqa yangi API lar
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "uz.yurtal.maryaipos.mary_ai_pos"
        // flutter_secure_storage 10.x's Android module declares minSdkVersion
        // 23 in its own build.gradle — Gradle's manifest merge fails if the
        // app's own minSdk is lower (was flutter's default of 21, kept for
        // flutter_local_notifications' 21+ requirement above that). API 23 =
        // Android 6.0 (2015); dropping 5.0/5.1 support is not expected to
        // matter for this app's real deployment target (§1 Q2: Windows
        // desktop primary, Android as a secondary waiter handheld — not
        // aimed at decade-old hardware).
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
