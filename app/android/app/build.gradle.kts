import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release key (keys/release.jks, never committed), named in android/key.properties. A
// release build without a readable key FAILS; it never falls back to debug keys, because an APK
// signed with them can never update over the real one. Others who build from source can make an
// unsigned release with -Pfightmilk.unsigned=true and sign it themselves. Debug builds are as
// before. (-Pfightmilk.keyprops=<file> names another key.properties, for the build check.)
val keyPropsFile = (project.findProperty("fightmilk.keyprops") as String?)?.let { file(it) } ?: rootProject.file("key.properties")
val keyProps = Properties().apply {
    if (keyPropsFile.isFile) FileInputStream(keyPropsFile).use { load(it) }
}
val unsignedRelease = (project.findProperty("fightmilk.unsigned") as String?) == "true"
val releaseKeyProblem: String? = run {
    if (!keyPropsFile.isFile) return@run "release key missing: ${keyPropsFile.path} does not exist"
    for (k in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        if ((keyProps[k] as String?).isNullOrEmpty()) return@run "release key missing: $k is not set in ${keyPropsFile.path}"
    }
    val store = file(keyProps["storeFile"] as String)
    if (!store.isFile || !store.canRead()) return@run "release key missing: ${store.path}"
    null
}

android {
    // No Google dependency-metadata block in the APK (only Google could read it; F-Droid/IzzyOnDroid flag it).
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
    namespace = "org.balderding.workout"
    // SDK platform 37 is installed as "android-37.0" (see ../build.gradle.kts)
    (this as com.android.build.gradle.BaseExtension).compileSdkVersion("android-37.0")
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "org.balderding.workout"
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
        // On-phone AI engine: llama.cpp + our bridge (src/main/cpp). Always built optimised.
        externalNativeBuild {
            cmake {
                val llama = System.getenv("LLAMA_DIR") ?: ""
                arguments += listOf("-DLLAMA_DIR=$llama", "-DCMAKE_BUILD_TYPE=Release")
                cppFlags += listOf("-O3")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        create("release") {
            // F420: APK Signature Scheme v3 as well as v2 (same key, no rotation: installed copies
            // update as before; v3 lets the key be rotated later)
            enableV2Signing = true
            enableV3Signing = true
            if (releaseKeyProblem == null) {
                storeFile = file(keyProps["storeFile"] as String)
                storePassword = keyProps["storePassword"] as String
                keyAlias = keyProps["keyAlias"] as String
                keyPassword = keyProps["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Own release key only; never debug keys (see releaseKeyProblem above).
            signingConfig = if (releaseKeyProblem == null && !unsignedRelease) signingConfigs.getByName("release") else null
        }
    }
}

// Refuse, loudly, before anything is built: a release without the release key.
gradle.taskGraph.whenReady {
    val release = allTasks.any { it.project == project && it.name.contains("Release") && (it.name.startsWith("assemble") || it.name.startsWith("bundle") || it.name.startsWith("package")) }
    if (release && !unsignedRelease && releaseKeyProblem != null) {
        throw GradleException("$releaseKeyProblem, refusing to sign a release with debug keys. (To build an unsigned release for your own signing, add -Pfightmilk.unsigned=true.)")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-ktx:1.19.0") // FileProvider for app updates
}
