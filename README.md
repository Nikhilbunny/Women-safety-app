# Women & Child Safety System (offline-first prototype)

Phone app (Flutter, Android + iOS) plus smartwatch apps (Wear OS and Apple Watch).
The core SOS flow works with **no internet**: GPS and SMS use the satellite and cellular
networks, the watch talks to the phone over Bluetooth, and all data is stored on the device.

## What is built

| Feature | Phone | Wear OS | Apple Watch |
|---|---|---|---|
| SOS button with 5 s cancel window | yes | - | - |
| Hold-to-send SOS (anti-accident) | - | 0.5 s long-press | 1.5 s long-press |
| GPS location in the alert (cached fix as fallback) | yes | - | - |
| SMS to all emergency contacts | automatic on Android; composer on iOS | via phone | via phone |
| Offline outbox: failed alerts retried every minute and on app resume | yes | - | - |
| Watch alert queued if phone is out of Bluetooth range | - | retries for ~1 min | OS-queued (`transferUserInfo`) |
| Phone confirms back to watch (sent / queued / no contacts) | - | yes | partial |
| Emergency contacts + your name (stored locally) | yes | - | - |
| Shake phone 3 times to send SOS | yes (app open) | - | - |
| Offline helpline directory with tap-to-call | yes | - | - |
| Alert history log | yes | - | - |
| Watch SOS works while the phone app is closed | Android: yes (native service) | - | iOS: no |

## Layout

```
phone/          Flutter sources (lib/, test/), Android Kotlin overlay, iOS Swift overlay
wear_os/        Standalone Android Studio project for the Wear OS app
apple_watch/    SwiftUI files for a watchOS target
tools/          patch_project.py (manifest, Gradle, Info.plist edits)
setup.sh        Generates a runnable Flutter project in build/safetyapp
```

## Get the APK without installing anything (GitHub builds it)

1. Make a free account at github.com and create a new repository (any name).
2. Unzip this project and drag **everything** inside the `safety_system` folder into the repo page
   (Add file, then Upload files). Make sure the `.github` folder goes up too. If it does not, use
   Add file, then Create new file, type `.github/workflows/build-apk.yml` as the name and paste
   the contents of that file.
3. Open the **Actions** tab, choose **Build Android apps**, click **Run workflow**.
4. After a few minutes open the finished run and download **safety-phone-apk** (and
   **safety-wear-apk** for the watch) from the Artifacts section. Unzip to get the `.apk`.
5. Copy the phone APK to your Android phone and open it. Allow "install unknown apps" when asked.
   Android may show a Play Protect warning because the app is not from the Play Store.
   Install the watch APK on a Wear OS watch with `adb install`.

If the build fails, open the failed step, copy the red error text, and send it to get a fix.

## Run it

Needs Flutter (3.22+), Android Studio, and for iOS/watchOS a Mac with Xcode.

On Windows PowerShell use `powershell -ExecutionPolicy Bypass -File .\setup.ps1` instead of `./setup.sh`.

```bash
./setup.sh
cd build/safetyapp
flutter test           # message formatting + phone number validation
flutter run            # use a real phone with a SIM; emulators cannot send SMS
```

**Wear OS:** open `wear_os/` in Android Studio and run on a Wear OS 3+ watch or emulator
paired with the phone. Its `applicationId` must stay identical to the phone app's
(`com.example.safetyapp`) or messages will not route.

**Apple Watch:** in Xcode open `build/safetyapp/ios/Runner.xcworkspace`, add a *watchOS App*
target, and drop in the three files from `apple_watch/`. Then in your iOS `AppDelegate`
call `PhoneWatchBridge.shared.start(messenger: <your FlutterBinaryMessenger>)` once the
Flutter engine is up (the exact line depends on your Flutter version's AppDelegate template).

## How the offline path works

```
Watch --Bluetooth--> Phone native service --SMS (cellular)--> contacts
                          |  GPS cached/live, no internet
                          '-- no signal? -> local outbox -> retry when signal returns
```

## Known limits (be honest with your users)

- **Not compiled or run in the environment this was written in** (no Flutter/Android/Xcode
  toolchain there). The Python patch step was tested; the Dart, Kotlin and Swift need a first
  build on your machine. Expect a few small fixes (versions, template differences).
- **iOS cannot send SMS silently.** The user must tap Send in Messages, so a watch-triggered
  alert on iPhone only works when the app is in the foreground; otherwise it waits in the
  queue. Android is the platform for fully automatic offline alerts.
- **Android retries from the outbox only when the app runs** (open, resumed, or minute timer).
  A WorkManager job would make retries truly background.
- Shake detection works while the app is open. OS battery limits apply in the background.
- SMS needs cell signal. With none, nothing can leave the device; the alert is queued.
- Contacts receive plain SMS; there is no delivery receipt from the recipient's phone.
- No siren, no audio/video evidence, no server. Alerts are not a substitute for calling
  emergency services; the helpline numbers default to India and live in `lib/helplines.dart`.

## Roadmap (suggested order)

1. WorkManager background retry + foreground service for shake/volume-button trigger
2. Safe-walk timer: auto-SOS if you do not check in by a deadline
3. Loud siren and fake-call screen (works offline)
4. Child mode: PIN-locked simple SOS screen, geofence alerts for parents
5. Optional backend (when online): live location sharing, push alerts, audit log
6. Watch heart-rate spike / fall detection as extra triggers
7. Privacy review: consent screens, data deletion, no analytics on location; check local law
   on location sharing for minors
8. Real-device test matrix: Android 10-15, low-end phones, no-SIM and airplane-mode cases
