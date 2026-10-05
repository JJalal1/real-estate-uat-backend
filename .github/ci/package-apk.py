"""Package actual APK bytes with independently checked, non-secret build identity."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def command(args):
    return subprocess.check_output(args, text=True).strip()


def package_revision(path):
    properties = Path(path).read_text(encoding="utf-8")
    match = re.search(r"^Pkg.Revision\s*=\s*(.+)$", properties, re.M)
    if not match:
        raise ValueError("Missing SDK package revision: " + str(path))
    return match.group(1).strip()


def main():
    sha = command(["git", "rev-parse", "HEAD"])
    assert sha == os.environ["CANDIDATE_SHA"]
    assert os.environ["UAT_APP_ENVIRONMENT"] == "uat"
    assert os.environ["UAT_API_BASE_URL"] == "https://real-estate-uat-api-frankfurt.onrender.com/api"
    subprocess.run(["git", "diff", "--exit-code"], check=True)
    flutter = json.loads(command(["flutter", "--version", "--machine"]))
    assert flutter["frameworkVersion"] == "3.27.3"
    sdk = Path(os.environ["ANDROID_HOME"])
    build_tools = package_revision(sdk / "build-tools/34.0.0/source.properties")
    ndk = package_revision(sdk / "ndk/28.1.13356709/source.properties")
    assert build_tools == "34.0.0" and ndk == "28.1.13356709"
    assert (sdk / "platforms/android-35/android.jar").is_file()
    gradle = re.search(r"^Gradle ([0-9.]+)$", Path("gradle-version.txt").read_text(), re.M)
    assert gradle and gradle.group(1) == "8.7"
    app_gradle = Path("mobile_app/android/app/build.gradle").read_text()
    app_id = re.search(r'applicationId\s*=\s*"([^"]+)"', app_gradle).group(1)
    apk = Path("mobile_app/build/app/outputs/flutter-apk/app-release.apk")
    assert apk.is_file() and apk.stat().st_size > 0
    badging = command([str(sdk / "build-tools/34.0.0/aapt"), "dump", "badging", str(apk)])
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)'", badging, re.M)
    assert package and package.group(1) == app_id
    assert package.group(2) == os.environ["GITHUB_RUN_NUMBER"]
    dist = Path("dist")
    dist.mkdir(exist_ok=True)
    output = dist / f"real-estate-uat-{os.environ['GITHUB_RUN_NUMBER']}.apk"
    shutil.copyfile(apk, output)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    (dist / "SHA256.txt").write_text(f"{digest}  {output.name}\n")
    java = subprocess.run(["java", "-version"], check=True, capture_output=True, text=True)
    info = {
        "environment": "uat",
        "api_base_url": os.environ["UAT_API_BASE_URL"],
        "github_run_id": os.environ["GITHUB_RUN_ID"],
        "github_run_number": os.environ["GITHUB_RUN_NUMBER"],
        "github_run_attempt": os.environ["GITHUB_RUN_ATTEMPT"],
        "github_sha": sha,
        "source_ref": os.environ["SOURCE_REF"],
        "android_application_id": app_id,
        "android_version_code": package.group(2),
        "flutter_version": flutter["frameworkVersion"],
        "dart_version": flutter["dartSdkVersion"],
        "apk_file_size_bytes": str(output.stat().st_size),
        "apk_sha256": digest,
        "gradle_version": gradle.group(1),
        "android_gradle_plugin_version": "8.6.1",
        "android_compile_sdk": "35",
        "android_build_tools_version": build_tools,
        "android_ndk_version": ndk,
        "android_command_line_tools_version": command(["sdkmanager", "--version"]),
        "java_version": (java.stderr or java.stdout).splitlines()[0],
        "github_context_sha": os.environ["GITHUB_SHA"],
        "signing_limitation": "UAT release uses existing debug signing; production signing deferred",
        "qualification": "Gate 1 pre-deploy candidate only; Gate 2 not implemented",
    }
    (dist / "BUILD_INFO.txt").write_text("".join(f"{key}={value}\n" for key, value in info.items()))
    print((dist / "BUILD_INFO.txt").read_text(), end="")
    print((dist / "SHA256.txt").read_text(), end="")


if __name__ == "__main__":
    main()
