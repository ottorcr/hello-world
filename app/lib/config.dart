/// App-wide settings. Change these before publishing.
class AppConfig {
  /// Where the privacy policy is hosted. The stores require a public URL.
  static const privacyPolicyUrl =
      'https://github.com/ottorcr/hello-world/blob/master/docs/privacy-policy.md';

  /// Where people can request account deletion without the app (Google Play
  /// requires this link).
  static const deleteAccountUrl =
      'https://github.com/ottorcr/hello-world/blob/master/docs/delete-account.md';

  /// Minimum age to use the app. See docs/COMPLIANCE.md before lowering it.
  static const minimumAge = 18;

  static const maxTextLength = 280;
  static const maxNameLength = 40;

  /// Upper bound for a stored photo (Firestore documents max out at 1 MiB).
  static const maxImageBytes = 900 * 1024;

  /// Firestore batches cap at 500 writes, and the rules cap recipients at 200.
  static const maxRecipients = 200;
}
