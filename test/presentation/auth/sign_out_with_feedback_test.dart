import 'package:accounting_saver/domain/auth/app_user.dart';
import 'package:accounting_saver/domain/auth/auth_exception.dart';
import 'package:accounting_saver/presentation/auth/auth_providers.dart';
import 'package:accounting_saver/presentation/common/session_feedback_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';

const _user = AppUser(
  uid: 'user-1',
  email: 'ana@example.com',
  emailVerified: true,
  providerIds: ['password'],
);

void main() {
  group('signOutWithFeedbackProvider', () {
    test('si signOut termina con éxito, deja signedOut en sessionFeedbackProvider', () async {
      final repository = FakeAuthRepository(initialUser: _user);
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await container.read(signOutWithFeedbackProvider)();

      expect(repository.currentUser, isNull);
      expect(container.read(sessionFeedbackProvider), SessionFeedbackKind.signedOut);
    });

    test('si signOut falla, no deja ningún aviso y propaga el error', () async {
      final repository = FakeAuthRepository(
        initialUser: _user,
        signOutError: const AuthException('network-request-failed'),
      );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(signOutWithFeedbackProvider)(),
        throwsA(isA<AuthException>()),
      );

      expect(repository.currentUser, isNotNull); // not actually signed out
      expect(container.read(sessionFeedbackProvider), isNull);
    });
  });
}
