import 'package:accounting_saver/domain/auth/app_user.dart';
import 'package:accounting_saver/domain/auth/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('un usuario de correo y contraseña se identifica como password', () {
    final profile = UserProfile.fromAppUser(
      AppUser(
        uid: 'u1',
        email: 'ana@example.com',
        emailVerified: true,
        providerIds: const ['password'],
      ),
    );

    expect(profile.provider, SignInProvider.password);
    expect(profile.emailVerified, isTrue);
  });

  test('un usuario de Google se identifica como google y conserva las fechas', () {
    final created = DateTime(2026, 1, 5);
    final lastSignIn = DateTime(2026, 10, 6);
    final profile = UserProfile.fromAppUser(
      AppUser(
        uid: 'u2',
        email: 'ana@gmail.com',
        emailVerified: true,
        providerIds: const ['google.com'],
        createdAt: created,
        lastSignInAt: lastSignIn,
      ),
    );

    expect(profile.provider, SignInProvider.google);
    expect(profile.createdAt, created);
    expect(profile.lastSignInAt, lastSignIn);
  });

  test('solo las cuentas de correo sin verificar necesitan verificación', () {
    AppUser user({required bool verified, required List<String> providers}) => AppUser(
      uid: 'u',
      email: 'ana@example.com',
      emailVerified: verified,
      providerIds: providers,
    );

    expect(user(verified: false, providers: const ['password']).needsEmailVerification, isTrue);
    expect(user(verified: true, providers: const ['password']).needsEmailVerification, isFalse);
    expect(user(verified: false, providers: const ['google.com']).needsEmailVerification, isFalse);
  });
}
