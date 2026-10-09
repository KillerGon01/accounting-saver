/// La interfaz de IA (entrada en lenguaje natural, y lo que venga después)
/// solo se activa si se compila con `--dart-define=ENABLE_AI=true`. Por
/// defecto está desactivada, para no exigir que cada persona que clona el
/// repositorio configure Firebase AI Logic y App Check solo para poder
/// compilar la app.
///
/// Esta es la petición ("se quiere activar la IA"), no si la IA está
/// realmente disponible en esta build: para eso, ver `effectiveEnableAi`
/// en `app_check_config.dart`, que además exige una clave de reCAPTCHA en
/// release. `main.dart` usa esta constante solo para decidir el proveedor
/// de depuración en builds que no son de release.
const enableAi = bool.fromEnvironment('ENABLE_AI');

/// Clave de sitio de reCAPTCHA Enterprise para App Check en producción
/// (web), pasada con `--dart-define=RECAPTCHA_SITE_KEY=...` al compilar.
/// Nunca se escribe en el repositorio: vacía por defecto, y solo tiene
/// valor en el entorno de compilación de quien hace el build de
/// producción (ver docs/security.md).
const recaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');
