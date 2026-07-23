import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties()
if (releaseSigningFile.exists()) {
    releaseSigningFile.inputStream().use(releaseSigningProperties::load)
}
val releaseRequested =
    gradle.startParameter.taskNames.any { task ->
        task.contains("release", ignoreCase = true)
    }
val requiredSigningProperties =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingSigningProperties =
    requiredSigningProperties.filter { releaseSigningProperties.getProperty(it).isNullOrBlank() }
if (releaseRequested && (!releaseSigningFile.exists() || missingSigningProperties.isNotEmpty())) {
    throw GradleException(
        "릴리스 서명 설정이 없습니다. 저장소 루트에서 " +
            "powershell -ExecutionPolicy Bypass -File tool/create_local_keystore.ps1 를 실행하세요.",
    )
}

android {
    namespace = "com.songs.geulbom"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.songs.geulbom"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    val localReleaseSigning =
        if (releaseSigningFile.exists() && missingSigningProperties.isEmpty()) {
            signingConfigs.create("localRelease") {
                storeFile = rootProject.file(releaseSigningProperties.getProperty("storeFile"))
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        } else {
            null
        }

    buildTypes {
        release {
            signingConfig = localReleaseSigning
        }
    }
}

dependencies {
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
