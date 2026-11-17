import java.util.Properties
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
val keys = Properties()
val keysFile = rootProject.file("key.properties")
if (keysFile.exists()) keysFile.inputStream().use { keys.load(it) }
android {
    namespace = "com.runspot.runquest"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.runspot.runquest"
        minSdk = 30
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    signingConfigs {
        if (keysFile.exists()) create("release") {
            keyAlias = keys["keyAlias"] as String
            keyPassword = keys["keyPassword"] as String
            storeFile = project(":app").file(keys["storeFile"] as String)
            storePassword = keys["storePassword"] as String
        }
    }
    buildTypes { release { if (keysFile.exists()) signingConfig = signingConfigs.getByName("release") } }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
dependencies { implementation("com.google.android.gms:play-services-wearable:20.0.1") }
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst { if (!keysFile.exists()) throw GradleException("워치 출시 서명 정보가 없습니다.") }
}
