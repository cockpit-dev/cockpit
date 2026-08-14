plugins {
    id("com.android.application") version "8.11.1"
}

android {
    namespace = "dev.cockpit.driver"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.cockpit.driver"
        minSdk = 24
        targetSdk = 36
        versionCode = 10
        versionName = "4.0.27"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
}

tasks.register<Sync>("publishDriver") {
    dependsOn("assembleDebug", "assembleDebugAndroidTest")
    into(layout.projectDirectory.dir("../../lib/src/system_control/resources/android"))
    from(layout.buildDirectory.file("outputs/apk/debug/cockpit-android-driver-debug.apk")) {
        rename { "cockpit-driver.apk" }
    }
    from(
        layout.buildDirectory.file(
            "outputs/apk/androidTest/debug/cockpit-android-driver-debug-androidTest.apk",
        ),
    ) {
        rename { "cockpit-driver-test.apk" }
    }
}
