import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Kunci APK release, tidak di-commit. Cara membuatnya ada di docs/deploy.md.
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) keyPropertiesFile.inputStream().use { load(it) }
}

android {
    namespace = "id.ac.its.aprevo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "id.ac.its.aprevo"
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
        if (keyPropertiesFile.exists()) {
            create("release") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

// Update hanya bisa dipasang kalau kuncinya sama, jadi APK untuk siswa tidak boleh
// terbuat dengan kunci lain.
tasks.matching { it.name == "packageRelease" }.configureEach {
    doFirst {
        if (!keyPropertiesFile.exists()) {
            throw GradleException(
                "android/key.properties belum ada. Lihat docs/deploy.md, langkah 6."
            )
        }
    }
}

// APK tanpa kunci Supabase terbuka, tetapi tidak bisa dipakai masuk atau daftar, jadi
// tidak boleh terbuat. Syaratnya sama dengan SupabaseConfig.isConfigured.
val dartDefines: Map<String, String> = (findProperty("dart-defines") as String? ?: "")
    .split(",")
    .filter { it.isNotEmpty() }
    .map { String(Base64.getDecoder().decode(it)) }
    .associate { it.substringBefore("=") to it.substringAfter("=") }

tasks.matching { it.name == "preReleaseBuild" || it.name == "compileFlutterBuildRelease" }
    .configureEach {
        doFirst {
            val url = dartDefines["SUPABASE_URL"].orEmpty()
            val anonKey = dartDefines["SUPABASE_ANON_KEY"].orEmpty()
            if (!url.startsWith("https://") || !anonKey.startsWith("eyJ")) {
                throw GradleException(
                    "SUPABASE_URL atau SUPABASE_ANON_KEY kosong atau belum benar. Build " +
                        "release harus memakai --dart-define-from-file=config/app_env.json. " +
                        "Lihat docs/deploy.md, langkah 7."
                )
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
