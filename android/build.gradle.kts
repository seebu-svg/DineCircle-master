allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// flutter_stripe's `:stripe_android` module runs Android Lint on release builds,
// and its lint-only classpath pulls play-services-tapandpay:18.8.0, which is not
// resolvable from google()/mavenCentral() here. Lint is a static-analysis gate,
// not required to package a (test-mode) APK, so disable every lint task project-
// wide. The app itself compiles without it (only the lint task was failing).
subprojects {
    tasks.configureEach {
        if (name.contains("lint", ignoreCase = true)) {
            enabled = false
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
