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

// family-utility-app: force plugin compileSdk
subprojects {
    plugins.withId("com.android.library") {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            val names = setOf("setCompileSdk", "setCompileSdkVersion", "compileSdkVersion")
            val setter = androidExt.javaClass.methods.firstOrNull {
                it.name in names && it.parameterTypes.size == 1 &&
                    (it.parameterTypes[0] == Int::class.javaPrimitiveType || it.parameterTypes[0] == java.lang.Integer::class.java)
            }
            if (setter != null) {
                setter.invoke(androidExt, 36)
                println("family-utility-app: forced compileSdk 36 on " + project.path + " via " + setter.name)
            } else {
                println("family-utility-app: no compileSdk setter found on " + project.path)
            }
        }
    }
}
