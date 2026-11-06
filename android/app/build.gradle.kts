import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. `android/key.properties` + the keystore are gitignored, so a
// fresh clone (or CI) falls back to the debug key instead of failing the build.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.dinecircle.dine_circle"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dinecircle.dine_circle"
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
        // Google Maps SDK key, passed at build time with
        // --dart-define=GOOGLE_MAPS_API_KEY=... (also accepted as a Gradle
        // property for plain Gradle runs). Empty default keeps debug builds
        // working; the map then renders in "no key" demo mode.
        val mapsKey = providers.gradleProperty("GOOGLE_MAPS_API_KEY")
            .orElse(
                providers.gradleProperty("dart-define")
                    .orElse("")
                    .map { Regex("GOOGLE_MAPS_API_KEY=([^;]+)").find(it)?.groupValues?.get(1) ?: "" },
            )
            .get()
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = mapsKey
    }

    signingConfigs {
        // Real release key, used whenever android/key.properties is present.
        // Losing this keystore means future builds cannot update the app in
        // place over an installed copy.
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Keyless builds (CI, fresh clone) still produce a testable APK.
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

dependencies {
    // flutter_stripe requires AppCompat-descendant host themes (see
    // res/values/styles.xml); declare it directly so the resources resolve
    // regardless of how the plugin's own dependency graph evolves.
    implementation("androidx.appcompat:appcompat:1.7.1")
}

flutter {
    source = "../.."
}
