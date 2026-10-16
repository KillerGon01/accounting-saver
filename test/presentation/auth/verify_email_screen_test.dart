import 'package:accounting_saver/domain/auth/app_user.dart';
import 'package:accounting_saver/domain/auth/auth_exception.dart';
import 'package:accounting_saver/presentation/auth/auth_providers.dart';
import 'package:accounting_saver/presentation/auth/verify_email_screen.dart';
import 'package:accounting_saver/presentation/common/session_feedback_providers.dart';
import 'package:accounting_saver/presentation/common/app_localization.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';

const _user = AppUser(
  uid: 'user-1',
  email: 'ana@example.com',
  emailVerified: false,
  providerIds: ['password'],
);

const _resendLabel = 'Reenviar correo';

Future<void> _pump(WidgetTester tester, FakeAuthRepository repository) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: appLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: const VerifyEmailScreen(user: _user),
      ),
    ),
  );
  await tester.pump();
}

OutlinedButton _resend(WidgetTester tester) =>
    tester.widget<OutlinedButton>(find.byType(OutlinedButton));

void main() {
  testWidgets('muestra el correo del usuario y el aviso de spam', (tester) async {
    await _pump(tester, FakeAuthRepository(initialUser: _user));

    expect(find.textContaining('ana@example.com'), findsOneWidget);
    expect(find.textContaining('carpeta de spam'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Ya lo he verificado'), findsOneWidget);
  });

  testWidgets('reenviar respeta la espera de 60 segundos', (tester) async {
    final repository = FakeAuthRepository(initialUser: _user);
    await _pump(tester, repository);

    // El correo se envió al registrarse: el contador empieza al abrir la pantalla.
    expect(find.text('Reenviar correo (en 60 s)'), findsOneWidget);
    expect(_resend(tester).onPressed, isNull);

    await tester.pump(const Duration(seconds: 59));
    expect(find.text('Reenviar correo (en 1 s)'), findsOneWidget);
    expect(_resend(tester).onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_resendLabel), findsOneWidget);
    expect(_resend(tester).onPressed, isNotNull);

    await tester.tap(find.text(_resendLabel));
    await tester.pump();

    expect(repository.verificationEmailsSent, 1);
    expect(find.text('Reenviar correo (en 60 s)'), findsOneWidget);
    expect(_resend(tester).onPressed, isNull);
  });

  testWidgets('muestra en español el límite de envíos al reenviar', (tester) async {
    final repository = FakeAuthRepository(
      initialUser: _user,
      sendVerificationError: const AuthException('too-many-requests'),
    );
    await _pump(tester, repository);

    await tester.pump(const Duration(seconds: 60));
    await tester.tap(find.text(_resendLabel));
    await tester.pump();

    expect(
      find.text('Demasiados intentos. Espera un momento e inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(find.text(_resendLabel), findsOneWidget);
  });

  testWidgets('"Ya lo he verificado" muestra aviso si el correo sigue sin verificar', (tester) async {
    final repository = FakeAuthRepository(initialUser: _user);
    await _pump(tester, repository);

    await tester.tap(find.widgetWithText(FilledButton, 'Ya lo he verificado'));
    await tester.pump();

    expect(repository.reloadCount, 1);
    expect(
      find.textContaining('Todavía no has verificado tu correo'),
      findsOneWidget,
    );
  });

  testWidgets('"Cerrar sesión / usar otro correo" cierra la sesión y deja signedOut', (tester) async {
    final repository = FakeAuthRepository(initialUser: _user);
    await _pump(tester, repository);

    await tester.tap(find.text('Cerrar sesión / usar otro correo'));
    await tester.pump();

    expect(repository.currentUser, isNull);
    expect(
      ProviderScope.containerOf(tester.element(find.byType(VerifyEmailScreen))).read(sessionFeedbackProvider),
      SessionFeedbackKind.signedOut,
    );
  });
}
