import 'package:accounting_saver/main.dart';
import 'package:accounting_saver/presentation/auth/auth_providers.dart';
import 'package:accounting_saver/presentation/auth/login_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_auth_repository.dart';

void main() {
  testWidgets('muestra la pantalla de login cuando no hay usuario', (
    WidgetTester tester,
  ) async {
    final fakeAuthRepository = FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuthRepository),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
