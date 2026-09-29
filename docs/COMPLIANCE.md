# Legal & store compliance notes (US + EU)

> **Not legal advice.** This is a developer's checklist compiled in September
> 2026 for a small, free, friends-only app. Laws change. If the app grows
> beyond friends, or you start charging or showing ads, talk to a lawyer.

## What the app does (and deliberately doesn't)

| | |
| --- | --- |
| Accounts | Email + password (Firebase Auth), with verified email |
| Data collected | Email, display name, friend list, thoughts and photos you share |
| Who can see content | Only friends you approved. Enforced by `app/firestore.rules` and tested in `app/firestore-tests/` |
| Payments / in-app purchases | **None** |
| Ads, analytics, tracking SDKs | **None** |
| Social logins (Google, Facebook…) | **None** (keeps Apple guideline 4.8 simple) |
| Minimum age | **18+** (`AppConfig.minimumAge`) |
| Photos | Resized, and all EXIF metadata (including GPS location) removed on the device before upload |
| Spotify | Paste a song link. No Spotify login, SDK or API key. Only the track ID, title and Spotify-CDN cover art are stored (enforced by the rules) |

## Checklist

### 🇪🇺 GDPR (EU/EEA users)

- [x] **Lawful basis:** performance of a contract (Art. 6(1)(b)). The app
      only processes what it needs to deliver thoughts to your friends.
- [x] **Data minimization:** no phone numbers, contacts upload, location, or
      analytics.
- [x] **Right to erasure (Art. 17):** in-app *Me → Delete account* removes
      the account, friendships, and everything the user shared, including
      friends' copies.
- [x] **Privacy policy:** [`privacy-policy.md`](privacy-policy.md), linked
      in the app. **You must fill in your contact email before publishing.**
- [ ] **Right of access/portability (Art. 15/20):** handled by email request
      for now (see the privacy policy). An in-app export could be added later.
- [x] **Children (Art. 8):** the digital age of consent is 13–16 depending on
      the country. The 18+ minimum avoids needing parental consent.
- [ ] **Processor agreement:** accept Google's
      [Firebase Data Processing Terms](https://firebase.google.com/terms/data-processing-terms)
      in the Firebase console (*Project settings → Privacy*).
- [ ] **Data location:** choose an EU Firestore location (for example
      `eur3`) if most users are in Europe.
- Note: the GDPR "household exemption" covers purely personal activity. An
  app published on a store for other people is safest treated as *in
  scope*, and everything above is cheap to do.

### 🇪🇺 Digital Services Act

- A free friends-only app run by one person is a *micro enterprise*, which
  is exempt from most DSA platform duties. The Commission's July 2025
  guidelines on protecting minors
  ([Art. 28](https://digital-strategy.ec.europa.eu/en/library/commission-publishes-guidelines-protection-minors))
  also exclude micro and small enterprises, and the 18+ minimum sidesteps
  them anyway.
- [x] Report and block tools exist (also required by Apple, below).

### 🇺🇸 COPPA (children under 13)

- The FTC's amended COPPA Rule has been enforceable since **April 22, 2026**.
  It applies to services directed at children, or with *actual knowledge* of
  users under 13.
- [x] The app isn't directed at children, requires 18+, and collects no
      birthdate. If you learn a user is under 13, delete their account.

### 🇺🇸 State "App Store Accountability Acts"

- **Texas SB 2420** has been in effect since the 5th Circuit stayed the
  injunction (May 28, 2026). Apple began enforcing it for developers on
  June 4, 2026. Utah's compliance date moved to **May 6, 2027**, and
  Louisiana has a similar law.
- They require developers to get the user's **age category from the app
  store** (Apple's *Declared Age Range* API, Google Play's *Age Signals*
  API) and to block minors or get parental consent through the store.
- [ ] **Before a public App Store / Play Store release** that includes
      Texas, add an age-range check using those store APIs. There is no
      Flutter plugin in this project for that yet. A self-declared "I'm 18+"
      checkbox is probably **not enough** under these laws.
- Distributing only to friends through TestFlight or a direct APK is lower
  risk, but a lawyer should confirm before any public listing.

### 🇺🇸 State privacy laws (CCPA/CPRA etc.)

- These only apply above revenue or user-count thresholds (CCPA: $25M+
  revenue, or 100k+ California consumers). A free hobby app is well below
  them. The privacy policy covers the basics anyway.

### 🍎 Apple App Store

- [x] **5.1.1(v) account deletion** in the app, including user-generated
      content shared with others.
- [x] **1.2 user-generated content:** report (*⋮ → Report*), block
      (*⋮ → Block*), and posting limited to approved friends.
      [ ] Publish a support contact in the store listing.
- [x] **4.8 login services:** not triggered (no third-party/social login).
- [ ] **Privacy "nutrition label":** Contact Info (email), User Content
      (photos, other content), Identifiers (user ID). Not used for tracking.
- [ ] **Texas age range:** see above.

### 🤖 Google Play

- [x] **Account deletion in the app**, plus a public web page:
      [`delete-account.md`](delete-account.md). Put its URL in *Data safety
      → Data deletion*.
- [ ] **Data safety form:** email, name, photos, and messages are collected
      and encrypted in transit. Users can request deletion. Nothing is shared
      with third parties.
- [x] **UGC policy:** report and block tools, and friends-only visibility.

## Sources

- Texas/Utah app store acts: [Wiley](https://www.wiley.law/alert-Key-Developments-With-State-App-Store-Accountability-Acts-as-Texas-Act-Takes-Effect), [Future of Privacy Forum](https://fpf.org/blog/comparing-enacted-app-store-accountability-acts/), [Apple: apps distributed in Texas](https://developer.apple.com/news/?id=8jzbigf4)
- COPPA amendments: [Davis Polk](https://www.davispolk.com/insights/client-update/ftc-prioritizes-coppa-enforcement-new-compliance-obligations-take-effect), [Finnegan](https://www.finnegan.com/en/insights/articles/coppas-amended-rule-is-now-in-full-effect-what-operators-need-to-know.html)
- GDPR Art. 8 ages: [GDPR-Text Art. 8](https://gdpr-text.com/read/article-8/), [EuConsent](https://euconsent.eu/digital-age-of-consent-under-the-gdpr/)
- DSA minors guidelines: [European Commission](https://digital-strategy.ec.europa.eu/en/library/commission-publishes-guidelines-protection-minors), [Taylor Wessing](https://www.taylorwessing.com/en/insights-and-events/insights/2025/07/rd-european-commission-guidelines-on-protection-of-minors-under-the-digital-services-act)
- Apple account deletion: [Apple Developer](https://developer.apple.com/support/offering-account-deletion-in-your-app); Apple 4.8: [Apple Developer News](https://developer.apple.com/news/?id=j9zukcr6)
- Google Play account deletion: [Play Console Help](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en)
