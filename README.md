# accounting-saver
[![CI](https://github.com/KillerGon01/accounting-saver/actions/workflows/ci.yml/badge.svg)](https://github.com/KillerGon01/accounting-saver/actions/workflows/ci.yml)

Personal finance assistant powered by AI (Gemini), built with Flutter and Firebase. Final Master's project for the AI Development Master's program.

## Integración continua

En cada pull request hacia `main` y en cada push a `main`, GitHub Actions ejecuta `flutter analyze` y `flutter test` (job `analyze_and_test`, bloqueante) y comprueba que `flutter build web --release` compila (job `build_web`, temporalmente no bloqueante). Sin secretos ni IA activada: ver docs/testing.md ("Integración continua (CI)") para el detalle.

## Compilar con la IA activada

La interfaz de IA (entrada en lenguaje natural y chat) solo se compila si se pasa `ENABLE_AI=true`. Por defecto está desactivada, para no exigir configurar Firebase AI Logic y App Check solo para compilar la app.

**Desarrollo local (web o Android, modo debug):**

```bash
flutter run --dart-define=ENABLE_AI=true
```

App Check se activa con el **proveedor de depuración** (`WebDebugProvider` / `AndroidDebugProvider`): el primer arranque imprime un token en la consola del navegador o en el log de Android que hay que registrar a mano en *Firebase Console → App Check → Manage debug tokens* (ver docs/security.md).

**Producción, build de release para web:**

```bash
flutter build web --release \
  --dart-define=ENABLE_AI=true \
  --dart-define=RECAPTCHA_SITE_KEY=<clave-de-sitio-de-reCAPTCHA-Enterprise>
```

App Check usa en este caso **Fraud Defense (reCAPTCHA Enterprise)**, el proveedor que Firebase recomienda para App Check en web. La clave de sitio **nunca se escribe en el repositorio**: se pasa solo en este `--dart-define`, en el comando de compilación de quien hace el release (o en un archivo local fuera de control de versiones con `--dart-define-from-file`). Si se omite ese `--dart-define` (o se deja vacío) en una build de release, la app no se rompe: la IA se oculta automáticamente, igual que con `ENABLE_AI=false`.

reCAPTCHA Enterprise tiene un **nivel gratuito de 10.000 evaluaciones al mes por organización de Google Cloud**; al superarlo, las peticiones de evaluación fallan en vez de cobrarse automáticamente. El SDK de App Check cachea el token con un **TTL de 1 hora**, así que no se gasta una evaluación en cada llamada a Gemini, solo aproximadamente una por hora de uso continuado. Detalles completos (incluida la detección del 403 de App Check) en docs/security.md.

Android en producción (Play Integrity) sigue pendiente: ver docs/security.md.
