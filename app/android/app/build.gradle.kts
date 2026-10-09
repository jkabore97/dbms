import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The phone's ring with the app closed (115): Firebase Cloud Messaging reads
// the project's google-services.json (Firebase console → the Android app
// bf.kaj.app), written here by CI from the GOOGLE_SERVICES_JSON secret and
// gitignored. Without the file the plugin is not applied, the build succeeds
// as before, and the app simply offers no Android push.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
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
            // No R8 shrinking. The first release build ever made of this app
            // failed in minifyReleaseWithR8 — the camera and text-reading
            // plugins need keep rules the project never had, because every
            // build before was a debug one. A larger APK that installs beats
            // a smaller one that does not build; the keep rules are a
            // follow-up with a device to test them on.
            // R8: strip the code and resources nobody calls. Half of what
            // the fat APK weighed was library code the app never reaches;
            // the rules in proguard-rules.pro keep what reflection needs.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Native libraries compressed in the APK: the file a shop downloads from
    // the release page over a market connection is about a third smaller.
    // (They are unpacked once at install; the Play Store delivers per phone.)
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

// Text recognition from Google Play services instead of the bundled model:
// the bundled one put 12 MB of native code and models in every APK. The
// unbundled library has the same API (com.google.mlkit.vision.text), and the
// manifest's DEPENDENCIES meta-data has Play services fetch the model at
// install, so the first photo still reads at once.
configurations.all {
    exclude(group = "com.google.mlkit", module = "text-recognition")
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
    // The AppCompat theme the fingerprint dialog needs (styles.xml).
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.1")
}
