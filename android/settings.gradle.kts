pluginManagement {
    repositories {
        google()
        // Google-hosted Maven Central mirror reduces transient 429 responses from repo.maven.apache.org.
        maven { url = uri("https://maven-central.storage-download.googleapis.com/maven2/") }
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        // Keep the mirror ahead of Maven Central so CI can fall back to a separate CDN.
        maven { url = uri("https://maven-central.storage-download.googleapis.com/maven2/") }
        mavenCentral()
    }
}
rootProject.name = "StoreFlow"
include(":app")
