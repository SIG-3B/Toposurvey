plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningEnvironment =
    listOf(
        "ANDROID_KEYSTORE_PATH",
        "ANDROID_KEYSTORE_PASSWORD",
        "ANDROID_KEY_ALIAS",
        "ANDROID_KEY_PASSWORD",
    ).associateWith { System.getenv(it).orEmpty() }
val releaseTaskRequested =
    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
val missingReleaseSigningValues =
    releaseSigningEnvironment.filterValues { it.isBlank() }.keys

if (releaseTaskRequested && missingReleaseSigningValues.isNotEmpty()) {
    throw GradleException(
        "Release builds require Android signing environment variables: " +
            missingReleaseSigningValues.joinToString(),
    )
}

val releaseKeystorePath = releaseSigningEnvironment.getValue("ANDROID_KEYSTORE_PATH")
if (releaseTaskRequested && !file(releaseKeystorePath).isFile) {
    throw GradleException("The configured Android release keystore does not exist.")
}

android {
    namespace = "com.toposurvey.toposurvey"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.toposurvey.toposurvey"
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

    signingConfigs {
        create("release") {
            storeFile =
                releaseKeystorePath
                    .takeIf { it.isNotBlank() }
                    ?.let { file(it) }
                    ?: file("release-upload.jks")
            storePassword = releaseSigningEnvironment.getValue("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = releaseSigningEnvironment.getValue("ANDROID_KEY_ALIAS")
            keyPassword = releaseSigningEnvironment.getValue("ANDROID_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
