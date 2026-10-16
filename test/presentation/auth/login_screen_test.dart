import 'dart:async';

import 'package:accounting_saver/domain/auth/auth_exception.dart';
import 'package:accounting_saver/presentation/auth/auth_providers.dart';
import 'package:accounting_saver/presentation/auth/login_screen.dart';
import 'package:accounting_saver/presentation/common/app_localization.dart';
import 'package:accounting_saver/presentation/common/session_feedback_providers.dart';
import 'package:accounting_saver/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';

const _genericError = 'No se pudo completar la operación. Inténtalo de nuevo.';

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
        home: const LoginScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _enter(WidgetTester tester, {String? email, String? password, String? confirm}) async {
  if (email != null) await tester.enterText(_field('Correo electrónico'), email);
  if (password != null) await tester.enterText(_field('Contraseña'), password);
  if (confirm != null) await tester.enterText(_field('Confirmar contraseña'), confirm);
}

Future<void> _switchToRegister(WidgetTester tester) async {
  await tester.tap(find.text('¿No tienes cuenta? Crear cuenta'));
  await tester.pumpAndSettle();
}

Future<void> _tapSubmit(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('muestra el modo inicio de sesión por defecto', (tester) async {
    await _pump(tester, FakeAuthRepository());

    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
    expect(_field('Confirmar contraseña'), findsNothing);
    expect(find.text('¿Has olvidado la contraseña?'), findsOneWidget);
  });

  testWidgets('alterna entre inicio de sesión y creación de cuenta', (tester) async {
    await _pump(tester, FakeAuthRepository());

    await _switchToRegister(tester);

    expect(find.widgetWithText(FilledButton, 'Crear cuenta'), findsOneWidget);
    expect(_field('Confirmar contraseña'), findsOneWidget);
    expect(find.text('¿Has olvidado la contraseña?'), findsNothing);

    await tester.tap(find.text('¿Ya tienes cuenta? Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
    expect(_field('Confirmar contraseña'), findsNothing);
  });

  testWidgets('rechaza un correo con formato inválido sin llamar al repositorio', (tester) async {
    final repository = FakeAuthRepository();
    await _pump(tester, repository);

    await _enter(tester, email: 'correo-malo', password: 'cualquiera');
    await _tapSubmit(tester, 'Entrar');

    expect(find.text('El correo electrónico no tiene un formato válido'), findsOneWidget);
    expect(repository.signInCalls, isEmpty);
  });

  testWidgets('exige al menos 8 caracteres al crear cuenta', (tester) async {
    final repository = FakeAuthRepository();
    await _pump(tester, repository);
    await _switchToRegister(tester);

    await _enter(tester, email: 'ana@example.com', password: '1234567', confirm: '1234567');
    await _tapSubmit(tester, 'Crear cuenta');

    expect(find.text('La contraseña debe tener al menos 8 caracteres'), findsOneWidget);
    expect(repository.signUpCalls, isEmpty);
  });

  testWidgets('no permite crear cuenta si las contraseñas no coinciden', (tester) async {
    final repository = FakeAuthRepository();
    await _pump(tester, repository);
    await _switchToRegister(tester);

    await _enter(tester, email: 'ana@example.com', password: 'secreta123', confirm: 'secreta124');
    await _tapSubmit(tester, 'Crear cuenta');

    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
    expect(repository.signUpCalls, isEmpty);
  });

  testWidgets('crea la cuenta con el correo recortado', (tester) async {
    final repository = FakeAuthRepository();
    await _pump(tester, repository);
    await _switchToRegister(tester);

    await _enter(tester, email: '  ana@example.com ', password: 'secreta123', confirm: 'secreta123');
    await _tapSubmit(tester, 'Crear cuenta');

    expect(repository.signUpCalls.single.email, 'ana@example.com');
    expect(repository.signUpCalls.single.password, 'secreta123');
    expect(find.text(_genericError), findsNothing);
  });

  testWidgets('envía el correo de verificación tras registrarse', (tester) async {
    final repository = FakeAuthRepository();
    await _pump(tester, repository);
    await _switchToRegister(tester);

    await _enter(tester, email: 'ana@example.com', password: 'secreta123', confirm: 'secreta123');
    await _tapSubmit(tester, 'Crear cuenta');

    expect(repository.verificationEmailsSent, 1);
  });

  testWidgets('si el correo de verificación falla, la cuenta se crea igualmente', (tester) async {
    final repository = FakeAuthRepository(
      sendVerificationError: const AuthException('too-many-requests'),
    );
    await _pump(tester, repository);
    await _switchToRegister(tester);

    await _enter(tester, email: 'ana@example.com', password: 'secreta123', confirm: 'secreta123');
    await _tapSubmit(tester, 'Crear cuenta');

    expect(repository.signUpCalls, hasLength(1));
    expect(repository.currentUser, isNotNull);
    expect(find.text(_genericError), findsNothing);
  });

  testWidgets('deshabilita el botón y muestra carga mientras se procesa', (tester) async {
    final gate = Completer<void>();
    final repository = FakeAuthRepository()..responseGate = gate.future;
    await _pump(tester, repository);

    await _enter(tester, email: 'ana@example.com', password: 'secreta123');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();

    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });

  final errorCases = <({String code, bool register, String message})>[
    (code: 'email-already-in-use', register: true, message: 'Ya existe una cuenta con este correo electrónico.'),
    (code: 'weak-password', register: true, message: 'La contraseña es demasiado débil. Usa al menos 8 caracteres.'),
    (code: 'invalid-email', register: false, message: 'El correo electrónico no tiene un formato válido.'),
    (code: 'invalid-credential', register: false, message: 'Correo o contraseña incorrectos.'),
    (code: 'wrong-password', register: false, message: 'Correo o contraseña incorrectos.'),
    (code: 'user-not-found', register: false, message: 'Correo o contraseña incorrectos.'),
    (code: 'too-many-requests', register: false, message: 'Demasiados intentos. Espera un momento e inténtalo de nuevo.'),
    (code: 'network-request-failed', register: false, message: 'Sin conexión. Comprueba tu red e inténtalo de nuevo.'),
    (code: 'codigo-desconocido', register: false, message: _genericError),
  ];

  for (final errorCase in errorCases) {
    testWidgets('muestra en español el error ${errorCase.code}', (tester) async {
      final error = AuthException(errorCase.code);
      final repository = errorCase.register
          ? FakeAuthRepository(signUpError: error)
          : FakeAuthRepository(signInError: error);
      await _pump(tester, repository);

      if (errorCase.register) {
        await _switchToRegister(tester);
        await _enter(tester, email: 'ana@example.com', password: 'secreta123', confirm: 'secreta123');
        await _tapSubmit(tester, 'Crear cuenta');
      } else {
        await _enter(tester, email: 'ana@example.com', password: 'secreta123');
        await _tapSubmit(tester, 'Entrar');
      }

      expect(find.text(errorCase.message), findsOneWidget);
    });
  }

  testWidgets('muestra el mensaje genérico ante un error que no es de autenticación', (tester) async {
    await _pump(tester, FakeAuthRepository(signInError: StateError('fallo interno')));

    await _enter(tester, email: 'ana@example.com', password: 'secreta123');
    await _tapSubmit(tester, 'Entrar');

    expect(find.text(_genericError), findsOneWidget);
    expect(find.textContaining('fallo interno'), findsNothing);
  });

  testWidgets('envía el enlace de restablecimiento y muestra un mensaje neutro', (tester) async {
    final repository = FakeAuthRepository();
    await _pump(tester, repository);

    await _enter(tester, email: ' ana@example.com ');
    await tester.tap(find.text('¿Has olvidado la contraseña?'));
    await tester.pumpAndSettle();

    expect(repository.resetPasswordCalls, ['ana@example.com']);
    expect(find.textContaining('Si existe una cuenta con ese correo'), findsOneWidget);
  });

  testWidgets('pide un correo válido antes de enviar el restablecimiento', (tester) async {
    final repository = FakeAuthRepository();
    await _pump(tester, repository);

    await _enter(tester, email: 'no-es-correo');
    await tester.tap(find.text('¿Has olvidado la contraseña?'));
    await tester.pumpAndSettle();

    expect(find.text('El correo electrónico no tiene un formato válido'), findsOneWidget);
    expect(repository.resetPasswordCalls, isEmpty);
  });

  group('visibilidad de la contraseña', () {
    Finder toggleIn(String label) =>
        find.descendant(of: _field(label), matching: find.byType(IconButton));

    EditableText editableIn(WidgetTester tester, String label) => tester.widget<EditableText>(
      find.descendant(of: _field(label), matching: find.byType(EditableText)),
    );

    bool isObscured(WidgetTester tester, String label) =>
        editableIn(tester, label).obscureText;

    testWidgets('la contraseña empieza oculta', (tester) async {
      await _pump(tester, FakeAuthRepository());

      expect(isObscured(tester, 'Contraseña'), isTrue);
      expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
    });

    testWidgets('el icono muestra la contraseña y la vuelve a ocultar sin perder texto ni foco', (tester) async {
      await _pump(tester, FakeAuthRepository());
      await _enter(tester, password: 'secreta123');
      await tester.tap(_field('Contraseña'));
      await tester.pump();

      await tester.tap(toggleIn('Contraseña'));
      await tester.pump();

      expect(isObscured(tester, 'Contraseña'), isFalse);
      expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
      expect(editableIn(tester, 'Contraseña').controller.text, 'secreta123');
      expect(editableIn(tester, 'Contraseña').focusNode.hasFocus, isTrue);

      await tester.tap(toggleIn('Contraseña'));
      await tester.pump();

      expect(isObscured(tester, 'Contraseña'), isTrue);
      expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
      expect(editableIn(tester, 'Contraseña').controller.text, 'secreta123');
    });

    testWidgets('al cambiar a crear cuenta la contraseña vuelve a ocultarse', (tester) async {
      await _pump(tester, FakeAuthRepository());
      await tester.tap(toggleIn('Contraseña'));
      await tester.pump();

      await _switchToRegister(tester);

      expect(isObscured(tester, 'Contraseña'), isTrue);
      expect(isObscured(tester, 'Confirmar contraseña'), isTrue);
    });

    testWidgets('en el registro, los dos campos tienen su propio icono independiente', (tester) async {
      await _pump(tester, FakeAuthRepository());
      await _switchToRegister(tester);

      await tester.tap(toggleIn('Contraseña'));
      await tester.pump();

      expect(isObscured(tester, 'Contraseña'), isFalse);
      expect(isObscured(tester, 'Confirmar contraseña'), isTrue);

      await tester.tap(toggleIn('Confirmar contraseña'));
      await tester.pump();

      expect(isObscured(tester, 'Contraseña'), isFalse);
      expect(isObscured(tester, 'Confirmar contraseña'), isFalse);

      await tester.tap(toggleIn('Contraseña'));
      await tester.pump();

      expect(isObscured(tester, 'Contraseña'), isTrue);
      expect(isObscured(tester, 'Confirmar contraseña'), isFalse);
    });
  });

  group('aviso de sesión', () {
    // Helper propio, aparte de `_pump`: necesita sembrar el estado de
    // `sessionFeedbackProvider` antes del primer frame, así que monta con
    // `UncontrolledProviderScope` + un `ProviderContainer` propio en vez
    // del `ProviderScope` normal que usa `_pump` — ningún test de arriba
    // se toca.
    Future<ProviderContainer> pumpWithFeedback(WidgetTester tester, SessionFeedbackKind? seeded) async {
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())],
      );
      addTearDown(container.dispose);
      if (seeded != null) {
        container.read(sessionFeedbackProvider.notifier).set(seeded);
      }

      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            locale: appLocale,
            supportedLocales: appSupportedLocales,
            localizationsDelegates: appLocalizationsDelegates,
            home: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('tras cerrar sesión, muestra "Has cerrado sesión" una vez y lo limpia', (tester) async {
      final container = await pumpWithFeedback(tester, SessionFeedbackKind.signedOut);

      expect(find.text('Has cerrado sesión'), findsOneWidget);
      // Limpiado inmediatamente: un rebuild posterior de esta misma
      // pantalla (o un hot reload) no vuelve a leer ningún aviso.
      expect(container.read(sessionFeedbackProvider), isNull);
    });

    testWidgets('tras un borrado completo, muestra el aviso de cuenta eliminada una vez', (tester) async {
      final container = await pumpWithFeedback(tester, SessionFeedbackKind.accountDeleted);

      expect(
        find.text('Tu cuenta y todos tus datos se han eliminado correctamente'),
        findsOneWidget,
      );
      expect(container.read(sessionFeedbackProvider), isNull);
    });

    testWidgets('sin ningún aviso pendiente, no muestra ningún SnackBar', (tester) async {
      await pumpWithFeedback(tester, null);

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
