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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Plugins ask for compileSdk 37; the new SDK installs it as "android-37.0", which this Android
// Gradle Plugin only finds by that exact name. Point every module at it.
subprojects {
    val fix: Project.() -> Unit = {
        if (name != "app") extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.compileSdkVersion("android-37.0")
    }
    if (state.executed) fix() else afterEvaluate { fix() }
}
