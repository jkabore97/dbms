import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload keystore, when the build has one. CI writes key.properties and
// the .jks from repository secrets (see .github/workflows/build.yml); a
// developer's machine may carry its own. Both files are gitignored — the
// keystore is the one thing that, once leaked, can never be rotated on a
// published app, so it never enters the repository or a chat.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasUploadKey = keystorePropertiesFile.exists()
if (hasUploadKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    // The app's identity on a phone and in the store. Reverse-domain, and
    // never com.example: the store refuses that, and an id cannot change
    // after the first install without becoming a different app.
    namespace = "bf.kaj.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "bf.kaj.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // With the upload key: a build the store and every phone will
            // accept as the same app next time. Without it: the debug key,
            // so `flutter build apk --release` still works on a machine
            // that has no business holding the real one — installable for
            // testing, never publishable.
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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
