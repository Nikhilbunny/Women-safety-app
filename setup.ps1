# Windows PowerShell version of setup.sh
# Run from the safety_system folder:
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
$ErrorActionPreference = "Stop"

$Here = $PSScriptRoot
$App = Join-Path $Here "build\safetyapp"

function Fail($msg) { Write-Host $msg -ForegroundColor Red; exit 1 }

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Fail "Flutter is not installed or not on PATH. Install it from https://docs.flutter.dev/get-started/install then reopen PowerShell."
}
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $py) { Fail "Python 3 is required for the patch step. Install it from https://www.python.org/downloads/ and tick 'Add to PATH'." }

New-Item -ItemType Directory -Force (Join-Path $Here "build") | Out-Null

if (-not (Test-Path $App)) {
    flutter create --org com.example --project-name safetyapp --platforms android,ios $App
    if ($LASTEXITCODE -ne 0) { Fail "flutter create failed" }
}

# Dart sources, dependencies and tests
Remove-Item -Recurse -Force (Join-Path $App "lib"), (Join-Path $App "test") -ErrorAction SilentlyContinue
Copy-Item -Recurse (Join-Path $Here "phone\lib") (Join-Path $App "lib")
Copy-Item -Recurse (Join-Path $Here "phone\test") (Join-Path $App "test")
Copy-Item -Force (Join-Path $Here "phone\pubspec.yaml") (Join-Path $App "pubspec.yaml")

# Android native layer (package com.example.safetyapp)
$KT = Join-Path $App "android\app\src\main\kotlin\com\example\safetyapp"
New-Item -ItemType Directory -Force $KT | Out-Null
Copy-Item -Force (Join-Path $Here "phone\android_overlay\*.kt") $KT

# iOS bridge (only matters if you build for iPhone on a Mac)
$ios = Join-Path $App "ios\Runner"
if (Test-Path $ios) {
    Copy-Item -Force (Join-Path $Here "phone\ios_overlay\PhoneWatchBridge.swift") $ios
}

# Manifest permissions, wear service, Gradle dependency, Info.plist keys
& $py.Source (Join-Path $Here "tools\patch_project.py") $App
if ($LASTEXITCODE -ne 0) { Fail "Patch step failed" }

Push-Location $App
flutter pub get
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "flutter pub get failed" }
Pop-Location

Write-Host ""
Write-Host "Done. Next:" -ForegroundColor Green
Write-Host "  cd build\safetyapp"
Write-Host "  flutter test"
Write-Host "  flutter run"
