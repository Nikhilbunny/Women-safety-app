#!/usr/bin/env python3
"""Patches a freshly generated `flutter create` project for the Safety App.

Usage: patch_project.py <flutter_project_dir>

Idempotent: running it twice does not duplicate anything.
"""
import plistlib
import re
import sys
from pathlib import Path

ANDROID_PERMISSIONS = [
    "android.permission.SEND_SMS",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.VIBRATE",
    "android.permission.INTERNET",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_LOCATION",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.CALL_PHONE",
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
]

SERVICE_XML = """
        <service
            android:name=".WearSosService"
            android:exported="true">
            <intent-filter>
                <action android:name="com.google.android.gms.wearable.MESSAGE_RECEIVED" />
                <data
                    android:scheme="wear"
                    android:host="*"
                    android:pathPrefix="/sos" />
            </intent-filter>
        </service>
"""

TRACKING_XML = """
        <service
            android:name=".TrackingService"
            android:exported="false"
            android:foregroundServiceType="location" />
"""

WEAR_DEP = 'implementation("com.google.android.gms:play-services-wearable:18.2.0")'


def patch_manifest(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    additions = []
    for perm in ANDROID_PERMISSIONS:
        if perm not in text:
            additions.append(f'    <uses-permission android:name="{perm}" />')
    if "android.hardware.camera" not in text:
        additions.append('    <uses-feature android:name="android.hardware.camera" android:required="false" />')
    if "android.hardware.telephony" not in text:
        additions.append('    <uses-feature android:name="android.hardware.telephony" android:required="false" />')
    if additions:
        text, n = re.subn(r"(\s*)<application", "\n" + "\n".join(additions) + r"\1<application", text, count=1)
        if n != 1:
            raise SystemExit("Could not find <application> in AndroidManifest.xml")

    if ".WearSosService" not in text:
        text, n = re.subn(r"</application>", SERVICE_XML + "    </application>", text, count=1)
        if n != 1:
            raise SystemExit("Could not find </application> in AndroidManifest.xml")

    if ".TrackingService" not in text:
        text, n = re.subn(r"</application>", TRACKING_XML + "    </application>", text, count=1)
        if n != 1:
            raise SystemExit("Could not find </application> in AndroidManifest.xml")

    path.write_text(text, encoding="utf-8")


def patch_gradle(app_dir: Path) -> None:
    for name in ("build.gradle.kts", "build.gradle"):
        f = app_dir / name
        if f.exists():
            text = f.read_text(encoding="utf-8")
            if "play-services-wearable" not in text:
                text = text.rstrip() + f"\n\ndependencies {{\n    {WEAR_DEP}\n}}\n"
                f.write_text(text, encoding="utf-8")
            return
    raise SystemExit("No android/app/build.gradle(.kts) found")


def patch_plist(path: Path) -> None:
    with path.open("rb") as fh:
        data = plistlib.load(fh)
    data["NSLocationWhenInUseUsageDescription"] = (
        "Your location is added to SOS alerts sent to your emergency contacts."
    )
    schemes = list(data.get("LSApplicationQueriesSchemes", []))
    for s in ("sms", "tel"):
        if s not in schemes:
            schemes.append(s)
    data["LSApplicationQueriesSchemes"] = schemes
    with path.open("wb") as fh:
        plistlib.dump(data, fh)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    root = Path(sys.argv[1])
    manifest = root / "android/app/src/main/AndroidManifest.xml"
    if manifest.exists():
        patch_manifest(manifest)
        patch_gradle(root / "android/app")
    plist = root / "ios/Runner/Info.plist"
    if plist.exists():
        patch_plist(plist)
    print("Patched", root)


if __name__ == "__main__":
    main()
