import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "id.rasyiqi.clipper"
    compileSdk = 36
    // whisper_ggml compiles whisper.cpp with the NDK; pin the version it
    // requires so Android builds resolve the correct toolchain.
    ndkVersion = "29.0.13113456"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    defaultConfig {
        applicationId = "id.rasyiqi.clipper"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        jniLibs {
            // ffmpeg_kit_flutter_new (full-gpl, has libass for burned
            // subtitles) and whisper_ggml's ffmpeg_kit_flutter_new_min both
            // package the ffmpeg-kit native libs under the same JNI paths.
            // Keep the first copy merged (the app's direct dependency, the
            // full-gpl build) so subtitles keep working.
            pickFirsts += setOf(
                "**/libffmpegkit.so",
                "**/libffmpegkit_abidetect.so",
                "**/libavcodec.so",
                "**/libavdevice.so",
                "**/libavfilter.so",
                "**/libavformat.so",
                "**/libavutil.so",
                "**/libswresample.so",
                "**/libswscale.so",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
    }
}

flutter {
    source = "../.."
}
