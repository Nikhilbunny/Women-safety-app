#!/usr/bin/env bash
# Builds the runnable Flutter project in ./build/safetyapp from the sources in ./phone
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/build/safetyapp"

command -v flutter >/dev/null 2>&1 || { echo "Flutter is not installed. See https://docs.flutter.dev/get-started/install"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required for the patch step"; exit 1; }

mkdir -p "$HERE/build"
if [ ! -d "$APP" ]; then
  flutter create --org com.example --project-name safetyapp --platforms android,ios "$APP"
fi

# Dart sources, dependencies and tests
rm -rf "$APP/lib" "$APP/test"
cp -r "$HERE/phone/lib" "$APP/lib"
cp -r "$HERE/phone/test" "$APP/test"
cp "$HERE/phone/pubspec.yaml" "$APP/pubspec.yaml"

# Android native layer (package com.example.safetyapp)
KT="$APP/android/app/src/main/kotlin/com/example/safetyapp"
mkdir -p "$KT"
cp "$HERE"/phone/android_overlay/*.kt "$KT/"

# iOS bridge (needs one manual line in AppDelegate, see README)
if [ -d "$APP/ios/Runner" ]; then
  cp "$HERE/phone/ios_overlay/PhoneWatchBridge.swift" "$APP/ios/Runner/"
fi

# Manifest permissions, wear service, Gradle dependency, Info.plist keys
python3 "$HERE/tools/patch_project.py" "$APP"

(cd "$APP" && flutter pub get)
echo
echo "Done. Next:"
echo "  cd build/safetyapp && flutter test && flutter run"
