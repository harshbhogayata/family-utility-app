#!/usr/bin/env python3
"""Make the generated Android project build with the plugin set this app uses.

Idempotent: safe to run on every CI build and after `flutter create`.
- Root build.gradle(.kts): force every plugin module to compileSdk 36, because
  some plugins (file_picker) still declare 34 while others require 36.
- app/build.gradle(.kts): compileSdk 36, minSdk 26, targetSdk 35.
- AndroidManifest.xml: permissions the finished features already need.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "android"
if not ROOT.exists():
    print("no android/ directory; run flutter create first"); sys.exit(1)

MARK = "// family-utility-app: force plugin compileSdk"
KTS_BLOCK = f"""
{MARK}
subprojects {{
    plugins.withId("com.android.library") {{
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {{
            val setter = androidExt.javaClass.methods.firstOrNull {{
                it.name == "setCompileSdkVersion" && it.parameterTypes.size == 1 && it.parameterTypes[0] == Int::class.javaPrimitiveType
            }}
            setter?.invoke(androidExt, 36)
        }}
    }}
}}
"""
GROOVY_BLOCK = f"""
{MARK}
subprojects {{
    afterEvaluate {{
        if (project.hasProperty('android')) {{
            project.android.compileSdkVersion 36
        }}
    }}
}}
"""

def patch_root():
    for name, block in (("build.gradle.kts", KTS_BLOCK), ("build.gradle", GROOVY_BLOCK)):
        p = ROOT / name
        if p.exists():
            t = p.read_text()
            if MARK in t:
                t = t[: t.index(MARK)].rstrip() + "\n"   # drop an older version of the block
            p.write_text(t.rstrip() + "\n" + block)
            print(f"patched {name}")
            return
    print("root build.gradle not found")

def patch_app():
    for name in ("app/build.gradle.kts", "app/build.gradle"):
        p = ROOT / name
        if not p.exists():
            continue
        t = p.read_text()
        kts = name.endswith(".kts")
        t = re.sub(r"compileSdk\s*=\s*flutter\.compileSdkVersion", "compileSdk = 36", t)
        t = re.sub(r"compileSdkVersion\s+flutter\.compileSdkVersion", "compileSdkVersion 36", t)
        t = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 26", t)
        t = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 26", t)
        t = re.sub(r"targetSdk\s*=\s*flutter\.targetSdkVersion", "targetSdk = 35", t)
        t = re.sub(r"targetSdkVersion\s+flutter\.targetSdkVersion", "targetSdkVersion 35", t)
        if "isCoreLibraryDesugaringEnabled" not in t and kts:
            t = t.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
            if "coreLibraryDesugaring(" not in t:
                t = t.rstrip() + '\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        p.write_text(t)
        print(f"patched {name}")
        return
    print("app build.gradle not found")

PERMS = [
    "android.permission.INTERNET",
    "android.permission.CAMERA",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
    "android.permission.READ_MEDIA_IMAGES",
    "android.permission.READ_MEDIA_VIDEO",
    "android.permission.USE_BIOMETRIC",
    "android.permission.ACCESS_WIFI_STATE",
    "android.permission.CHANGE_WIFI_STATE",
    "android.permission.ACCESS_NETWORK_STATE",
]

def patch_manifest():
    p = ROOT / "app/src/main/AndroidManifest.xml"
    if not p.exists():
        print("manifest not found"); return
    t = p.read_text()
    added = []
    for perm in PERMS:
        if perm not in t:
            t = t.replace("<application", f'    <uses-permission android:name="{perm}" />\n    <application', 1)
            added.append(perm)
    if "android.hardware.camera" not in t:
        t = t.replace("<application", '    <uses-feature android:name="android.hardware.camera" android:required="false" />\n    <application', 1)
    p.write_text(t)
    print(f"manifest: added {len(added)} permissions")

patch_root(); patch_app(); patch_manifest()
