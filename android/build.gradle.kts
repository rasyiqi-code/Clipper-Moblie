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

subprojects {
    fun applyCompileSdk() {
        val androidExt = project.extensions.findByName("android") ?: return
        when (androidExt) {
            is com.android.build.api.dsl.ApplicationExtension -> androidExt.compileSdk = 36
            is com.android.build.api.dsl.LibraryExtension -> androidExt.compileSdk = 36
            is com.android.build.api.dsl.TestExtension -> androidExt.compileSdk = 36
            is com.android.build.gradle.BaseExtension -> androidExt.compileSdkVersion(36)
            else -> {}
        }
    }

    if (project.state.executed) {
        applyCompileSdk()
    } else {
        project.afterEvaluate {
            applyCompileSdk()
        }
    }

    tasks.withType<JavaCompile> {
        options.compilerArgs.add("-Xlint:-options")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
