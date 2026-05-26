plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21"
}

android {
    namespace = "com.example.maintenance_app"
    compileSdk = 36  // ✅ CHANGED: Use explicit version instead of flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
        // ✅ ADDED: Compose compiler options
        freeCompilerArgs += listOf(
            "-opt-in=androidx.compose.material3.ExperimentalMaterial3Api",
            "-opt-in=androidx.compose.foundation.ExperimentalFoundationApi"
        )
    }

    defaultConfig {
        applicationId = "com.example.maintenance_app"
        minSdk = 24
        targetSdk = 35
        ndkVersion = "27.0.12077973"
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        vectorDrawables {
            useSupportLibrary = true
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // ✅ ADDED: Proguard configuration
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
            isDebuggable = true
        }
    }

    // ✅ ADDED: Preserve compression of filament files (required for SceneView)
    androidResources {
        noCompress += listOf("filamat", "ktx", "glb", "gltf")
    }

    // ✅ ADDED: Packaging options to avoid conflicts
    packaging {
        resources {
            excludes += listOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "/META-INF/DEPENDENCIES",
                "/META-INF/LICENSE",
                "/META-INF/LICENSE.txt",
                "/META-INF/license.txt",
                "/META-INF/NOTICE",
                "/META-INF/NOTICE.txt",
                "/META-INF/notice.txt",
                "/META-INF/ASL2.0"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ ADDED: Compose BOM for version alignment
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)

    // ✅ UPDATED: Compose dependencies (using BOM)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.compose.material:material")
    implementation("androidx.compose.material3:material3")  // ✅ ADDED
    implementation("androidx.navigation:navigation-compose:2.9.0")

    // ✅ UPDATED: Debug implementations
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    // SceneView ArSceneView
    implementation("io.github.sceneview:arsceneview:2.3.0")

    // ARCore
    implementation("com.google.ar:core:1.49.0")

    // ✅ UPDATED: AndroidX with lifecycle support
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.fragment:fragment-ktx:1.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.0")  // ✅ ADDED
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.0")  // ✅ ADDED

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.1")

    // Material Design
    implementation("com.google.android.material:material:1.12.0")

    // ✅ ADDED: Optional logging for debugging
    implementation("com.jakewharton.timber:timber:5.0.1")

    // LOUIS TREELS
    // TensorFlow Lite base engine
    implementation("org.tensorflow:tensorflow-lite:2.14.0")
    implementation("org.tensorflow:tensorflow-lite-support:0.4.4")
    implementation("org.tensorflow:tensorflow-lite-gpu:2.14.0")

}