import 'package:accounting_saver/app_check_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chooseAppCheckConfig', () {
    test('IA desactivada: nada de App Check, en ninguna plataforma', () {
      final config = chooseAppCheckConfig(
        enableAi: false,
        isRelease: false,
        isWeb: true,
        recaptchaSiteKey: '',
      );

      expect(config.effectiveEnableAi, isFalse);
      expect(config.webProvider, WebAppCheckProviderChoice.none);
      expect(config.androidProvider, AndroidAppCheckProviderChoice.none);
    });

    test('IA desactivada incluso en release con clave: ENABLE_AI manda primero', () {
      final config = chooseAppCheckConfig(
        enableAi: false,
        isRelease: true,
        isWeb: true,
        recaptchaSiteKey: 'una-clave',
      );

      expect(config.effectiveEnableAi, isFalse);
      expect(config.webProvider, WebAppCheckProviderChoice.none);
      expect(config.androidProvider, AndroidAppCheckProviderChoice.none);
    });

    test('debug web: proveedor de depuración, sin necesitar clave', () {
      final config = chooseAppCheckConfig(
        enableAi: true,
        isRelease: false,
        isWeb: true,
        recaptchaSiteKey: '',
      );

      expect(config.effectiveEnableAi, isTrue);
      expect(config.webProvider, WebAppCheckProviderChoice.debug);
      expect(config.androidProvider, AndroidAppCheckProviderChoice.debug);
    });

    test('debug Android: proveedor de depuración, sin necesitar clave', () {
      final config = chooseAppCheckConfig(
        enableAi: true,
        isRelease: false,
        isWeb: false,
        recaptchaSiteKey: '',
      );

      expect(config.effectiveEnableAi, isTrue);
      expect(config.webProvider, WebAppCheckProviderChoice.debug);
      expect(config.androidProvider, AndroidAppCheckProviderChoice.debug);
    });

    test('release web con clave: reCAPTCHA Enterprise, la IA se muestra', () {
      final config = chooseAppCheckConfig(
        enableAi: true,
        isRelease: true,
        isWeb: true,
        recaptchaSiteKey: 'una-clave',
      );

      expect(config.effectiveEnableAi, isTrue);
      expect(config.webProvider, WebAppCheckProviderChoice.recaptchaEnterprise);
      expect(config.androidProvider, AndroidAppCheckProviderChoice.none);
    });

    test('release web sin clave: la IA se oculta en vez de dejarla fallar', () {
      final config = chooseAppCheckConfig(
        enableAi: true,
        isRelease: true,
        isWeb: true,
        recaptchaSiteKey: '',
      );

      expect(config.effectiveEnableAi, isFalse);
      expect(config.webProvider, WebAppCheckProviderChoice.none);
      expect(config.androidProvider, AndroidAppCheckProviderChoice.none);
    });

    test(
      'release Android con clave: la IA se oculta igual, no hay proveedor de producción para Android',
      () {
        final config = chooseAppCheckConfig(
          enableAi: true,
          isRelease: true,
          isWeb: false,
          recaptchaSiteKey: 'una-clave',
        );

        expect(config.effectiveEnableAi, isFalse);
        expect(config.webProvider, WebAppCheckProviderChoice.none);
        expect(config.androidProvider, AndroidAppCheckProviderChoice.none);
      },
    );

    test('release Android sin clave: la IA se oculta igual', () {
      final config = chooseAppCheckConfig(
        enableAi: true,
        isRelease: true,
        isWeb: false,
        recaptchaSiteKey: '',
      );

      expect(config.effectiveEnableAi, isFalse);
      expect(config.webProvider, WebAppCheckProviderChoice.none);
      expect(config.androidProvider, AndroidAppCheckProviderChoice.none);
    });
  });
}
