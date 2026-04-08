import org.gradle.api.GradleException
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

fun signingValue(propertyName: String, envName: String): String? {
    val fromProperties = keystoreProperties.getProperty(propertyName)?.trim()
    if (!fromProperties.isNullOrEmpty()) {
        return fromProperties
    }
    val fromEnv = System.getenv(envName)?.trim()
    return if (fromEnv.isNullOrEmpty()) null else fromEnv
}

val releaseStoreFilePath = signingValue("storeFile", "ANDROID_STORE_FILE")
val releaseStorePassword = signingValue("storePassword", "ANDROID_STORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseStoreFile =
    releaseStoreFilePath?.let { configuredPath ->
        val moduleRelative = file(configuredPath)
        if (moduleRelative.exists()) {
            moduleRelative
        } else {
            rootProject.file(configuredPath)
        }
    }
val hasReleaseSigning =
    releaseStoreFile != null &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

android {
    namespace = "com.uniyi.uni_yi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.uniyi.uni_yi"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseSigning -> signingConfigs.getByName("release")
                System.getenv("CI") == "true" ->
                    throw GradleException(
                        "Missing release signing config. Provide android/key.properties or ANDROID_* signing env vars.",
                    )
                else -> signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
