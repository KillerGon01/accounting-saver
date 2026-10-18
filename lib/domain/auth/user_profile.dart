import 'app_user.dart';

/// Provider the user signed in with. The application only offers these
/// two, so any other identifier is treated as email.
enum SignInProvider { password, google }

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.provider,
    required this.emailVerified,
    required this.createdAt,
    required this.lastSignInAt,
  });

  factory UserProfile.fromAppUser(AppUser user) {
    return UserProfile(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      provider: user.providerIds.contains(googleProviderId)
          ? SignInProvider.google
          : SignInProvider.password,
      emailVerified: user.emailVerified,
      createdAt: user.createdAt,
      lastSignInAt: user.lastSignInAt,
    );
  }

  final String uid;
  final String? email;
  final String? displayName;
  final SignInProvider provider;
  final bool emailVerified;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
}
