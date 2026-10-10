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

## Ejecución con Docker

`Dockerfile` multi-etapa: compila `flutter build web --release` con el mismo Flutter que el CI (3.47.6, SDK descargado del archivo oficial de Google con su sha256 fijado — no hay todavía ninguna imagen de Docker, oficial ni de comunidad, con esta versión) y sirve el resultado con `nginxinc/nginx-unprivileged` (nginx sin privilegios: usuario no root, puerto 8080, no el 80). Detalles de las dos imágenes elegidas y la verificación del checksum en docs/design.md.

**Con `docker compose` (recomendado, un solo comando):**

```bash
docker compose up --build
```

Sirve la app en `http://localhost:8080`. Para bajarlo: `docker compose down`.

**Con `docker build`/`docker run` directamente:**

```bash
docker build -t accounting-saver-web .
docker run --rm -p 8080:8080 accounting-saver-web
```

**Argumentos de build** (`--build-arg` con `docker build`, o la sección `args` de `docker-compose.yml`): `ENABLE_AI` y `RECAPTCHA_SITE_KEY`, los dos **vacíos por defecto** — nunca hay un valor real en el `Dockerfile` ni en el repositorio. Se pasan tal cual como `--dart-define` a `flutter build web`.

**Esta imagen está pensada para ejecutar la app sin IA.** La clave de sitio de reCAPTCHA Enterprise (App Check en producción, ver docs/security.md) solo admite los dominios que se hayan registrado para ella en Firebase/Google Cloud — normalmente los de **Firebase Hosting**. Si se construye la imagen con `ENABLE_AI=true` y esa clave, y se sirve en `http://localhost:8080` (o cualquier otro dominio no registrado), App Check rechazará el token de reCAPTCHA y la IA no funcionará, aunque la interfaz se muestre (fallará al primer intento de usarla, con el mensaje de "La IA no está disponible ahora mismo"). El despliegue oficial de la app sigue siendo **Firebase Hosting** (`firebase deploy`, ver `firebase.json`); Docker es una forma reproducible de servir el mismo `build/web` — útil para probarlo en local o en cualquier otro sitio que no sea Firebase Hosting, sin la IA.
