# Fitness Tracker

A personal training log for the phone. Hold the microphone, say the session, confirm the card. The plan, the check-ins, the warnings, and next week's lift cards all stay on the device.

There is no account, no cloud, and no analytics. The app does not make network calls.

## Clone

Clone onto a normal local disk. Do not put the project in iCloud Drive, in Documents if that folder is synced, or in a Grok folder. Flutter's build tools fail on those paths.

```bash
git clone https://github.com/Lewis-AI-Collab/fitness-tracker.git fitness-tracker
cd fitness-tracker
flutter pub get
```

## Run

Flutter 3.47 (stable) and the Android SDK.

```bash
flutter run
```

Speech recognition is on-device British English. It is unreliable on an emulator. Use a phone.

The first launch asks for the microphone and for notifications. Morning check-in defaults to 08:00 and evening to 21:00. Both can be turned off in Settings. Evening check-ins feed readiness, the same as the morning ones.

Units are kilograms and kilometres. If a log says pounds or miles, the app converts them and does not offer a unit setting.

## Android sideload

There is no Play Store listing. Build an APK and install it yourself.

Debug:

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Release:

```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Allow installs from unknown sources if the phone asks. After install, grant the microphone and notification permissions.

## iOS

Open `ios/Runner.xcworkspace` in Xcode on a Mac and run on a simulator or a device. A Linux machine cannot build the iOS simulator target.

The microphone and speech-recognition usage strings are in `ios/Runner/Info.plist`.

## Export

One share icon opens swipeable cards for a workout, the day, the week, or the month. Copy and Grok hand over one plain-text block: headings, dates, sets x reps x kg, RIR, runs in kilometres with pace, check-ins, and notes. Week and month blocks also include the balance check and the goal lines. Share sends that text, plus `fitness.txt`, `fitness-summary-v1.json`, and `summary.md`.

## Goals and balance

Settings holds one or more goals: a target pace, a target lift, or a general goal (strength, fitness, hypertrophy). Strength suggestions use 3–6 reps and heavier steps. The weekly plan shows push, pull, legs, and core bars, a load chart, and the goal lines. A lift goal has a ruler for the target. The rules are in `docs/SPEC.md`.

## Tests

```bash
flutter analyze
flutter test
```

## What stays local

Sessions, sets, Muay Thai blocks, plans, check-ins, warnings, patterns, and lift suggestions are in a SQLite file on the phone. Pattern notes and the weekly cards are rules over that file. Nothing is uploaded.
