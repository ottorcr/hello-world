# Random Thoughts 💭

A tiny Flutter app for **iPhone and Android**: you post random thoughts, and
they show up on your friends' home screens as a widget.

- **Author (you):** sign in inside the app, tap **+ New thought**, done.
- **Friends:** install the app, open it once, and add the *Random Thoughts*
  widget. No account needed.
- **Widget:** shows a random thought, rotates on its own (about every 30 min),
  and has a **Shuffle** button. It pulls new thoughts from Firestore by
  itself, so friends don't need to open the app again.

```
┌──────────────┐  post   ┌────────────┐  REST (public read)  ┌──────────────┐
│ App (author) │ ──────▶ │ Firestore  │ ───────────────────▶ │ Home widgets │
└──────────────┘         │ /thoughts  │ ◀── live stream ──── │ App (friend) │
                         └────────────┘                      └──────────────┘
```

## Project layout

| Path | What it is |
| --- | --- |
| `lib/` | Flutter app: feed, author sign-in, compose, and widget sync |
| `lib/widget_sync.dart` | Saves thoughts and the Firebase project ID to shared storage for the widgets |
| `android/app/src/main/kotlin/.../ThoughtsWidgetProvider.kt` | Android home-screen widget |
| `android/app/src/main/res/{layout,xml,values}/` | Android widget layout, metadata, and colors |
| `ios/WidgetSources/` | iOS WidgetKit extension (home screen + lock screen) |
| `firestore.rules` | Security rules: anyone reads, only you write |

## 1. Firebase setup (once)

1. Create a project at <https://console.firebase.google.com>.
2. **Firestore Database** → *Create database* (production mode).
3. **Authentication** → *Sign-in method* → enable **Email/Password**. Then
   under *Users* → *Add user*, add yourself. Copy your **User UID**.
4. Open `firestore.rules`, replace `REPLACE_WITH_YOUR_UID` with that UID, and
   paste the file into **Firestore → Rules → Publish**.
5. Connect the app (this overwrites the placeholder `lib/firebase_options.dart`):
   ```sh
   dart pub global activate flutterfire_cli
   cd app
   flutterfire configure   # pick your project, select android + ios
   ```

> **Privacy note:** thoughts are publicly readable by anyone who knows your
> Firebase project ID. That's what lets the widgets fetch without a login.
> Don't post anything secret.

## 2. Android

The widget is already wired up.

```sh
cd app
flutter run            # with a phone plugged in or an emulator running
```

Long-press the home screen → **Widgets** → **Random Thoughts**.

## 3. iOS (needs a Mac with Xcode 16+)

The widget code is in `ios/WidgetSources/`. Xcode has to create the extension
target once:

1. `open ios/Runner.xcworkspace`
2. **File → New → Target… → Widget Extension**. Name it **`ThoughtsWidget`**,
   uncheck *Include Live Activity*, *Include Control*, and *Include
   Configuration App Intent*. Click **Activate** when prompted.
3. Replace the generated files with ours:
   ```sh
   cp ios/WidgetSources/*.swift ios/ThoughtsWidget/
   ```
4. Select the **ThoughtsWidgetExtension** target → *General* → set
   *Minimum Deployments* to **iOS 17.0**. That's needed for the Shuffle
   button.
5. **App Group:** for **both** the *Runner* and *ThoughtsWidgetExtension*
   targets, go to *Signing & Capabilities* → **+ Capability → App Groups**,
   and add `group.com.ottorcr.randomThoughts`. Use the same team for both.
6. **Build-cycle fix:** on the *Runner* target → *Build Phases*, drag
   **Embed Foundation Extensions** above **Run Script** / **Thin Binary**.
   Without this, Flutter + widget extension builds fail with "Cycle inside
   Runner".
7. `flutter run`, then long-press the home screen → **+** → *Random Thoughts*.

If you change the bundle ID or App Group, update `WidgetSync.appGroupId` in
`lib/widget_sync.dart` and `appGroupId` in `ThoughtsWidget.swift` to match.

## 3½. Getting it onto friends' phones

- **Android:** `flutter build apk --release`, then send them the APK from
  `build/app/outputs/flutter-apk/`. Or use Firebase App Distribution.
- **iPhone:** you need an Apple Developer account ($99/yr). Upload with
  `flutter build ipa` and invite friends through **TestFlight**.

## How the widget refreshes

| | Android | iOS |
| --- | --- | --- |
| New random thought | every ~30 min (`updatePeriodMillis`) | every 30 min (6-entry timeline) |
| Fetch new thoughts | on each update, via Firestore REST | on each timeline reload |
| Shuffle button | broadcast → re-pick from cache | AppIntent → timeline reload |
| App open | pushes the latest thoughts right away | same |

Both OSes throttle widget refreshes, so a brand-new thought can take up to
about 30 minutes to reach a friend's widget unless they open the app.
