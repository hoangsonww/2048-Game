pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

// The foojay resolver lets Gradle download the JDK it needs instead of failing
// when the machine's default JDK is the wrong version. Combined with
// gradle/gradle-daemon-jvm.properties this means `./gradlew` works on a clean
// machine regardless of which JDK happens to be on PATH.
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "Game 2048"
include(":app")
