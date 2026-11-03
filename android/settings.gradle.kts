pluginManagement {
    includeBuild("build-logic")
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

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io") { content { includeGroupByRegex("com\\.github\\.pedroSG94.*") } }
    }
}

rootProject.name = "MetaStream"

include(":app")
include(":core:model")
include(":core:logging")
include(":core:storage")
include(":core:network")
include(":core:ui")
include(":feature:camera")
include(":feature:glasses")
include(":feature:platforms")
include(":feature:chat")
include(":feature:goal")
include(":feature:speech")
include(":feature:privacy")
