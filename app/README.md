# Random Thoughts 💭

A small, private Flutter app for **iPhone and Android**. Friends share short
thoughts and photos, and a random one shows up on each other's home-screen
widget.

- **Only approved friends:** you add someone by their 8-character friend
  code, and they have to approve. Nothing is public.
- **Text + photos + songs:** photos are resized, and GPS/EXIF data is
  stripped on the phone before upload. Attach a **Spotify song** by
  pasting its link. Friends tap it to play it in Spotify, from the app or
  from the widget.
- **Widgets:** home screen (both platforms) and lock screen (iOS). A random
  thought every ~30 minutes, plus a **Shuffle** button.
- **Safety:** hide, report, block, unfriend, unsend, and full account
  deletion.
- **No payments, ads, or tracking.**

```
 Alice's phone                     Firestore                         Bob's phone
┌─────────────┐  send (batch)  ┌──────────────────────────┐  live   ┌─────────────┐
│ compose     │ ─────────────▶ │ users/bob/inbox/{post}   │ ──────▶ │ app feed    │
│ text+photo  │                │ images/{post}  (gated)   │         │   │         │
└─────────────┘                │ users/alice/sent/{post}  │         │   ▼ cache   │
                               └──────────────────────────┘         │ widget 🏠   │
   rules: Alice may write to Bob's inbox only if Bob has Alice      └─────────────┘
          in his friends list. Only Bob can read his inbox.
```

## Project layout

| Path | What it is |
| --- | --- |
| `lib/data/repository.dart` | All Firestore access: profile, friend codes, requests, friends, posts, block/report, account deletion |
| `lib/data/image_prep.dart` | Resizes photos and strips their metadata |
| `lib/data/spotify.dart` | Parses Spotify links and looks up title/cover art (public oEmbed, no login) |
| `lib/ui/` | Screens: sign in, verify email, setup, feed, compose, friends, me |
| `lib/widget_sync.dart` | Writes the feed to on-device storage for the widgets. Background refresh on Android |
| `firestore.rules` | **The security model.** Read the comments at the top |
| `firestore-tests/` | Emulator tests that try to break the rules (`npm test`) |
| `android/.../ThoughtsWidgetProvider.kt` | Android widget (text and photo layouts) |
| `ios/ThoughtsWidget/` | iOS WidgetKit extension (already added to the Xcode project) |
| `../docs/` | Privacy policy, account-deletion page, legal/store checklist |
| `../.github/workflows/app.yml` | CI: rules tests, analyze/test, **Android APK**, and an unsigned iOS build |

## 1. Firebase setup (once)

1. Create a project at <https://console.firebase.google.com>. The free
   Spark plan is enough, and photos are stored in Firestore.
2. **Firestore Database** → *Create database*. Pick an EU location (such as
   `eur3`) if most of your friends are in Europe.
3. **Authentication** → *Sign-in method* → enable **Email/Password**.
4. Deploy the rules:
   ```sh
   npm i -g firebase-tools
   firebase login
   cd app
   firebase use --add            # pick your project
   firebase deploy --only firestore
   ```
5. Connect the app. This overwrites the placeholder `lib/firebase_options.dart`:
   ```sh
   dart pub global activate flutterfire_cli
   flutterfire configure   # pick your project; select android + ios
   ```
   Commit the generated `lib/firebase_options.dart`. Firebase API keys are
   identifiers, not secrets. The security rules protect the data.
6. Fill in `YOUR_CONTACT_EMAIL` in `../docs/privacy-policy.md` and
   `../docs/delete-account.md`.

## 2. Building without a local Android SDK

You don't need your PC. Every push runs **GitHub Actions**
(`.github/workflows/app.yml`), which:

- runs the security-rules tests against the Firestore emulator,
- runs `flutter analyze` and the unit tests,
- builds a release **APK**. Download it from the workflow run's *Artifacts*
  section and send it to your Android friends,
- builds the iOS app (unsigned) to check that it and the widget compile.

For a local build instead: install Flutter + Android Studio, then run
`flutter run` inside `app/`.

## 3. iOS

The widget extension target is already in the Xcode project. On a Mac:

1. `open ios/Runner.xcworkspace`
2. For **both** targets (*Runner* and *ThoughtsWidgetExtension*):
   *Signing & Capabilities* → pick your Team. The App Group
   `group.com.ottorcr.randomThoughts` is already declared in the
   entitlements, and Xcode registers it for you.
3. `flutter run`, then long-press the home screen → **+** → *Random Thoughts*.

Sharing with iPhone friends requires an Apple Developer account
($99/yr) and **TestFlight**.

## Testing

```sh
cd app
flutter analyze && flutter test          # Dart
cd firestore-tests && npm ci && npm test # security rules (needs Java 21)
```

## How the widget stays fresh

| | Android | iOS |
| --- | --- | --- |
| Source | on-device copy written by the app, never the network | same |
| New random thought | ~every 30 min | every 30 min (timeline) |
| Fetch new posts | app open, plus a background refresh when the copy is >25 min old | app open |
| Shuffle | instant, native | instant (AppIntent) |
| Sign out / delete account | copy wiped | copy wiped |

Instant pushes to widgets would need Cloud Functions + FCM, and that needs
the Blaze plan. It's easy to add later if you want it.

## Why songs are shared by link (not a Spotify login)

Spotify's Web API needs either a client secret, which can't safely ship
inside an app, or each user logging in with OAuth. It also limits apps that
Spotify hasn't approved to a handful of test users. Pasting a link through
the public oEmbed endpoint needs no keys or accounts and works for
everyone. If you later want in-app search, add a tiny backend (for example a
Cloud Function holding the client secret) that proxies Spotify's search.

## Legal

See [`../docs/COMPLIANCE.md`](../docs/COMPLIANCE.md). Short version: 18+,
email login only, in-app account deletion, report and block, and a privacy
policy. **Before a public App Store / Play Store release in Texas, add the
store age-range check.**
