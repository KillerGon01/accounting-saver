/// Firebase Auth provider identifiers used by the application.
const passwordProviderId = 'password';
const googleProviderId = 'google.com';

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
    required this.providerIds,
    this.displayName,
    this.createdAt,
    this.lastSignInAt,
  });

  final String uid;
  final String? email;
  final bool emailVerified;
  final List<String> providerIds;
  final String? displayName;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;

  /// Accounts created with email and password must verify their email
  /// before using the app. Google users already come verified.
  bool get needsEmailVerification =>
      !emailVerified && providerIds.contains(passwordProviderId);
}
