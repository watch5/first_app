import java.util.Properties
import java.io.FileInputStream

// 1. 設定ファイルの読み込み
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // あなたのパッケージ名に合わせて自動設定されているはずです
    namespace = "com.mark.dualy" 
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // ここもあなたのパッケージ名に合わせてください
        applicationId = "com.mark.dualy"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }



}

// 3. Flutterの設定 (ここがズレていた可能性があります)
flutter {
    source = "../.."
}