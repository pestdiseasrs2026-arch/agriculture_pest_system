# Agriculture Pest and Disease Detection System

Enterprise Flutter/Firebase application for farm management, AI-assisted crop diagnosis, GIS, IoT monitoring, soil testing, fertilizer inventory, analytics, notifications, and reports.

## Requirements

- Flutter 3.44 or newer and Dart 3.12 or newer
- Android Studio JDK 21
- Android SDK 36.1
- Firebase CLI for rules, indexes, and Hosting deployment
- A configured Firebase project and platform applications

## Local setup

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter run -d chrome
```

The real AI endpoint is provided at build time. Do not commit API tokens:

```powershell
flutter run --dart-define=AI_API_URL=https://example/api/predict --dart-define=AI_API_TOKEN=secret
```

Without `AI_API_URL`, the detection service must be treated as a development integration and not a production diagnosis service.

## Firebase authorization

The checked-in rules use Firebase Authentication and custom `role` claims. Supported privileged claims are `admin`, `administrator`, `agricultural_officer`, and `laboratory_staff`. Claims must be assigned from a trusted server or Cloud Function; never let a client assign its own role.

Before deploying rules:

1. Verify existing documents contain an ownership field used by the rules: `userId`, `ownerId`, `farmerId`, or `uid`.
2. Test farmer and privileged-role access with the Firebase Emulator Suite.
3. Back up production data and deploy to a staging project first.

```powershell
firebase emulators:start
firebase deploy --only firestore:rules,firestore:indexes,database,storage
```

Rules are deny-by-default. Do not deploy them blindly to collections with a different ownership schema.

## Web release

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter build web --release --no-pub
firebase deploy --only hosting
```

Hosting uses a single-page application rewrite and immutable caching for hashed JavaScript, CSS, and Wasm assets.

## Android build

```powershell
flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"
cd android
$env:JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"
.\gradlew.bat --stop
cd ..
flutter doctor --android-licenses
flutter doctor -v
flutter build apk --debug --no-pub
```

If Gradle hangs during JAR transforms, close VS Code first because its Gradle extension may start a separate daemon using the system JDK. Then stop Java/Gradle processes and build from a standalone terminal. Android is not verified until `build/app/outputs/flutter-apk/app-debug.apk` exists.

## Accessibility and performance checklist

- Test keyboard-only traversal and visible focus on Web.
- Test TalkBack/VoiceOver labels and reading order.
- Test 200% text scaling without clipped controls.
- Test reduced-motion and high-contrast OS preferences.
- Keep interactive controls at least 48×48 logical pixels.
- Use text and icons alongside semantic status colors.
- Paginate Firestore queries and cap chart/activity records.
- Compress uploads and expose retry, offline, empty, loading, and error states.
- Avoid adding collection-wide listeners during application startup.

## Stabilization gate

After every small feature group, run:

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter build web --release --no-pub
```

Deploy rules, indexes, Storage, Realtime Database, and Hosting independently so each change can be rolled back without coupling it to an application release.
