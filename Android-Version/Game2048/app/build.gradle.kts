plugins {
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.jetbrainsKotlinAndroid)
    jacoco
}

android {
    namespace = "com.sonnguyenhoang.game2048"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.sonnguyenhoang.game2048"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }
    }

    buildTypes {
        debug {
            enableUnitTestCoverage = true
        }
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
    buildFeatures {
        compose = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.1"
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation("androidx.compose.material3:material3:1.2.1")
    implementation("androidx.compose.animation:animation:1.0.5")
    implementation("androidx.compose.material:material-icons-extended")
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test.junit4)
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)
}

// MARK: - Coverage
//
// The rules engine and its storage are plain Kotlin and run on the JVM, so they
// carry a hard coverage gate. `MainActivity` is Compose and can only be
// exercised on a device, which `make test-android-device` does; holding the
// whole module to a JVM-only threshold would either fail on every machine
// without an emulator or push the number down to something meaningless.

jacoco {
    toolVersion = "0.8.12"
}

/** Classes that are real logic rather than UI or generated scaffolding. */
val domainClasses = listOf(
    "com/sonnguyenhoang/game2048/GameViewModel*.class",
    "com/sonnguyenhoang/game2048/GameStorage*.class",
    "com/sonnguyenhoang/game2048/SavedGame*.class",
    "com/sonnguyenhoang/game2048/SharedPreferencesGameStorage*.class"
)

// Scoped to the one directory AGP writes unit-test coverage into. A wider tree
// over the whole build directory sweeps in other tasks' outputs, which Gradle
// rejects as an undeclared dependency as soon as this runs alongside a build.
val unitTestExecution = fileTree(layout.buildDirectory.dir("outputs/unit_test_code_coverage")) {
    include("**/*.exec")
}

tasks.register<JacocoReport>("jacocoTestReport") {
    group = "verification"
    description = "Coverage for the Kotlin rules engine and storage."
    dependsOn("testDebugUnitTest")

    reports {
        xml.required.set(true)
        html.required.set(true)
    }

    sourceDirectories.setFrom(files("src/main/java"))
    classDirectories.setFrom(
        fileTree(layout.buildDirectory.dir("tmp/kotlin-classes/debug")) { include(domainClasses) }
    )
    executionData.setFrom(unitTestExecution)
}

tasks.register<JacocoCoverageVerification>("jacocoCoverageVerification") {
    group = "verification"
    description = "Fails when the rules engine or storage drops below 90% line coverage."
    dependsOn("jacocoTestReport")

    classDirectories.setFrom(
        fileTree(layout.buildDirectory.dir("tmp/kotlin-classes/debug")) { include(domainClasses) }
    )
    sourceDirectories.setFrom(files("src/main/java"))
    executionData.setFrom(unitTestExecution)

    violationRules {
        rule {
            limit {
                counter = "LINE"
                value = "COVEREDRATIO"
                minimum = "0.90".toBigDecimal()
            }
        }
        rule {
            limit {
                counter = "BRANCH"
                value = "COVEREDRATIO"
                minimum = "0.85".toBigDecimal()
            }
        }
    }
}
