# Irrigation Monitor

A Flutter mobile app for monitoring two irrigation fields, controlling a shared
pump and field valves, reviewing seven-day soil-moisture history and activity,
and comparing water use before and after automation. The mobile UI follows the
supplied dashboard, field map, history, settings, alerts, and water-report
mockups.

## Run on phones and computers

Install the current stable Flutter SDK. From this project folder, generate the
platform runners once:

```powershell
flutter create --platforms=android,ios,web,windows,macos,linux .
flutter pub get
```

Run the web version in a browser. The same web build works on phones, tablets,
and computers and is the easiest way to share the demo:

```powershell
flutter run -d chrome
flutter build web --release
```

Publish the contents of `build/web` to a web host to access it from other
devices. For a home or class demonstration on the same Wi-Fi, run
`flutter run --release -d web-server --web-hostname 0.0.0.0` and open the
displayed address from another device. Use a secure hosted site for real-world
use.

For native Android development, install Android Studio and its Android SDK,
connect a phone with USB debugging enabled (or start an emulator), then run:

```powershell
flutter devices
flutter run -d <android-device-id>
flutter build apk --release
```

The release APK is at
`build/app/outputs/flutter-apk/app-release.apk`; copy it to an Android phone
and install it. Android may ask you to allow installing apps from that source.

### Download an Android APK without installing Flutter locally

The GitHub Actions workflow can build the APK for you:

1. Push this project to a GitHub repository.
2. Open the repository's **Actions** tab and run **Flutter build** (or push a
   commit to `main`/`master` to trigger it).
3. When the **build-android** job finishes successfully, open that workflow
   run and download the `irrigation-android-apk` artifact.
4. Extract `app-release.apk`, send it to your Android phone, and install it.
   Android may ask you to allow installs from the app used to open the APK.

The artifact is retained for 14 days. This is a personal/demo build, not a
Play Store release. The app currently starts in demo mode, so installing it
does not connect it to a real sensor or pump.

For iPhone/iPad, use a Mac with Xcode installed and signed into the Apple
developer account used to install the app:

```sh
flutter devices
flutter run -d <ios-device-id>
flutter build ios --release
```

Use Xcode to sign and distribute the iOS build (for example, through
TestFlight). iOS apps cannot be compiled or signed on Windows.

On Windows, build a standalone Windows desktop app with Visual Studio's
**Desktop development with C++** workload installed:

```powershell
flutter run -d windows
flutter build windows --release
```

Build macOS apps on macOS and Linux apps on Linux, each with that platform's
Flutter desktop prerequisites installed. Run the automated tests with
`flutter test`.

The app starts in demo mode so the dashboard, automatic irrigation, controls,
history, alerts, and water report work without a Firebase project or hardware.
Demo readings are local to each running app and are not shared between devices.
Configure Firebase and connect the ESP32 as described below to share live
readings and pump commands across phones and computers.

## Connect Firebase

1. Create a Firebase project and enable Cloud Firestore.
2. Add Android and iOS apps to the project and configure their native Firebase
   files (`google-services.json` and `GoogleService-Info.plist`). Enable the
   Google Services Gradle plugin for the Android app, and add the plist to the
   iOS Runner target.
3. Register a Web app in the Firebase project and copy its API key, App ID,
   sender ID, and project ID from the Firebase configuration.
4. Replace the placeholder values in `firebase_options.dart` or run
   `flutterfire configure` to generate a project-specific Firebase config.
5. In `lib/main.dart`, set `demoMode` to `false`.
6. Run the web app with the Firebase Web config values (if you are not using
   `flutterfire configure`):

   ```powershell
   flutter run -d chrome `
     --dart-define=FIREBASE_API_KEY=<web-api-key> `
     --dart-define=FIREBASE_APP_ID=<web-app-id> `
     --dart-define=FIREBASE_MESSAGING_SENDER_ID=<sender-id> `
     --dart-define=FIREBASE_PROJECT_ID=<project-id>
   ```

   For a hosted live web build, pass the same `--dart-define` options to
   `flutter build web --release`. Native Android/iOS builds use their platform
   Firebase configuration files. Use the web version in a browser for shared
   live monitoring on desktop computers.
7. Create `systems/greenhouse-1/telemetry/current` in Firestore with fields:

   | Field | Type | Owner | Purpose |
   | --- | --- | --- | --- |
   | `moisture` | number | ESP32 | Current soil moisture, percent |
   | `fieldAMoisture` | number | ESP32 | Field A soil moisture, percent |
   | `fieldBMoisture` | number | ESP32 | Field B soil moisture, percent |
   | `threshold` | number | App | Moisture level that triggers watering |
   | `mode` | string | App | `automatic` or `manual` |
   | `pumpCommand` | boolean | App | Desired pump state in manual mode |
   | `actualPumpOn` | boolean | ESP32 | Confirmed pump state |
   | `valveAOpen` | boolean | ESP32 | Confirmed Field A valve state |
   | `valveBOpen` | boolean | ESP32 | Confirmed Field B valve state |
   | `valveACommand` | boolean | App | Desired Field A valve state in manual mode |
   | `valveBCommand` | boolean | App | Desired Field B valve state in manual mode |
   | `waterUsedToday` | number | ESP32 | Today's measured water use, liters |
   | `fieldAWaterToday` | number | ESP32 | Optional Field A water use today, liters |
   | `fieldBWaterToday` | number | ESP32 | Optional Field B water use today, liters |
   | `baselineWater` | number | Setup | Average daily use before automation |
   | `automatedWater` | number | ESP32 | Average daily use after automation |
   | `lastUpdated` | timestamp | ESP32 | Time of the latest sensor update |

The app listens to the current telemetry document in real time. Its sliders and
controls write `threshold`, `mode`, `pumpCommand`, and valve commands back to
that document. For existing single-field installations, `moisture` is used as
Field A's reading and also as Field B's fallback until the new fields are added.
Configure Firestore security rules so only authenticated, authorized users and
the device can access the system data; do not leave production data public.

The app has Dashboard, Field map, History, and Settings tabs. Dashboard and
History link to the Alerts and Water usage report screens. The report shows
weekly water volume based on the configured daily average. Field-level water
breakdown is shown only when `fieldAWaterToday` and `fieldBWaterToday` have
been provided; otherwise the app reports that those values are unavailable.

The Dashboard and History tabs also read soil samples from
`systems/greenhouse-1/readings`. Have the ESP32 (or a trusted backend) append
documents with `moisture` (number, percent) and `recordedAt` (Firestore
timestamp). Add optional `fieldBMoisture` (number, percent) for Field B history.
The dashboard groups up to 168 samples from the most recent seven days into
daily averages, so archive roughly hourly samples to keep the full week
represented. The device should use server timestamps where available.
Ensure Firestore rules allow authorized users to read this collection and only
the device/backend to append samples.

When the app is open, it shows an in-app alert when either field newly drops
below the configured moisture threshold. Existing dry readings are shown on the
dashboard without repeatedly generating alerts. These are foreground in-app
alerts; operating-system push notifications while the app is closed require a
push notification service and mobile platform configuration.

Activity and alert history is read from
`systems/greenhouse-1/events`, ordered by `occurredAt` descending. Each
document should contain `title` (string), `details` (string), `type` (string,
such as `watering`, `normal`, `reminder`, or `report`), and `occurredAt`
(Firestore timestamp). The ESP32 or a trusted backend should write these event
records. The app only writes the current mode and control commands.

## ESP32 behavior

The device firmware is responsible for continuously sampling the moisture
sensor for both fields, publishing telemetry and history samples, and
physically controlling the shared pump and each field valve. In `automatic`
mode, open the valve for a field when its moisture falls below `threshold` and
close it when moisture recovers above the threshold; run the shared pump while
at least one valve is open. In `manual` mode, follow
`valveACommand`/`valveBCommand`; run the pump while either commanded valve is
open, or when `pumpCommand` is true. Publish confirmed states as
`actualPumpOn`, `valveAOpen`, and `valveBOpen`. Add appropriate sensor
validation, a maximum pump-run timeout, and a safe pump-off behavior if the
device loses connectivity or receives invalid readings.

To measure savings, record water use over comparable periods before and after
automation. Set `baselineWater` and `automatedWater` to the measured daily
averages (liters); the app calculates the difference and percent saved. If
automated use exceeds the baseline, the app reports the increase instead of
showing misleading zero savings.

## Notes

- Demo mode uses generated readings and sample usage figures; it is not a
  connection to a real sensor or pump.
- This workspace contains the Flutter app source. The platform runner folders
  are generated by the `flutter create` command above. Building or signing
  iOS apps requires macOS and Xcode.
- The Firebase integration requires native Firebase configuration and an
  initialized Firestore document before live use. The live web build also
  requires the Firebase Web configuration values above.
