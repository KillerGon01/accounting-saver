import 'package:accounting_saver/app_check_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chooseAppCheckConfig', () {
    test('IA desactivada: nada de App Check, en ninguna plataforma', () {
      final config = chooseAppCheckConfig(enableAi: false, isRelease: false, recaptchaSiteKey: '');

      expect(config.effectiveEnableAi, isFalse);
      expect(config.webProvider, WebAppCheckProviderChoice.none);
      expect(config.androidProvider, AndroidAppCheckProviderChoice.none);
    });

    test('IA desactivada incluso en release con clave: ENABLE_AI manda primero', () {
      final config = chooseAppCheckConfig(
        enableAi: false,
        isRelease: true,
        recaptchaSiteKey: 'una-clave',
      );

      expect(config.effectiveEnableAi, isFalse);
      expect(config.webProvider, WebAppCheckProviderChoice.none);
      expect(config.androidProvider, AndroidAppCheckProviderChoice.none);
    });

    test('debug local: proveedor de depuración en web y en Android, sin necesitar clave', () {
      final config = chooseAppCheckConfig(enableAi: true, isRelease: false, recaptchaSiteKey: '');

      expect(config.effectiveEnableAi, isTrue);
      expect(config.webProvider, WebAppCheckProviderChoice.debug);
      expect(config.androidProvider, AndroidAppCheckProviderChoice.debug);
    });

    test('release con clave: reCAPTCHA Enterprise en web, la IA se muestra', () {
      final config = chooseAppCheckConfig(
        enableAi: true,
        isRelease: true,
        recaptchaSiteKey: 'una-clave',
      );

      expect(config.effectiveEnableAi, isTrue);
      expect(config.webProvider, WebAppCheckProviderChoice.recaptchaEnterprise);
    });

    test('release sin clave: la IA se oculta en vez de dejarla fallar', () {
      final config = chooseAppCheckConfig(enableAi: true, isRelease: true, recaptchaSiteKey: '');

      expect(config.effectiveEnableAi, isFalse);
      expect(config.webProvider, WebAppCheckProviderChoice.none);
    });

    test('Android en release: nunca el proveedor de depuración, con o sin clave web', () {
      final withKey = chooseAppCheckConfig(
        enableAi: true,
        isRelease: true,
        recaptchaSiteKey: 'una-clave',
      );
      final withoutKey = chooseAppCheckConfig(enableAi: true, isRelease: true, recaptchaSiteKey: '');

      expect(withKey.androidProvider, AndroidAppCheckProviderChoice.productionDefault);
      expect(withoutKey.androidProvider, AndroidAppCheckProviderChoice.productionDefault);
      expect(withKey.androidProvider, isNot(AndroidAppCheckProviderChoice.debug));
      expect(withoutKey.androidProvider, isNot(AndroidAppCheckProviderChoice.debug));
    });
  });
}
