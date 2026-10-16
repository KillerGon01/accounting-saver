# Seguridad

## Autenticación

- Email/contraseña y Google mediante `firebase_auth`.
- La pantalla principal solo se muestra con sesión iniciada (`AuthGate` en `main.dart`).
- No hay secretos en el repositorio. `google-services.json` está en `.gitignore`.

## Reglas de Firestore (`firestore.rules`)

Cada usuario solo puede leer y borrar sus propios movimientos, **y solo si su correo está verificado** (`isVerified()`: `request.auth.token.email_verified == true`, combinada con `isOwner(userId)` en las dos reglas, `read/delete` y `create/update`). Crear o editar exige además que el documento tenga exactamente los campos que escribe `FirestoreTransactionRepository`, con los tipos y valores válidos:

| Campo | Condición |
|---|---|
| (conjunto de campos) | Exactamente `amountCents`, `date`, `description`, `categoryId`, `source`, `createdAt`. Ni más ni menos. |
| `amountCents` | `int`, distinto de 0, entre -100.000.000 y 100.000.000 céntimos. |
| `description` | `string` de 1 a 200 caracteres. |
| `categoryId` | Uno de los nombres de `Category`. |
| `source` | Uno de los nombres de `TransactionSource`. |
| `date`, `createdAt` | `timestamp`. |

**Metas de ahorro (`users/{uid}/goals/{id}`), mismo patrón, regla propia y separada —`transactions` no se ha tocado.** Mismo `isOwner`/`isVerified` para leer y borrar; crear/editar exige exactamente los campos de `FirestoreSavingsGoalRepository`:

| Campo | Condición |
|---|---|
| (conjunto de campos) | Exactamente `name`, `targetCents`, `savedCents`, `deadline`, `createdAt`. Ni más ni menos. |
| `name` | `string` de 1 a 60 caracteres. |
| `targetCents` | `int`, mayor que 0, hasta 100.000.000 céntimos. |
| `savedCents` | `int`, entre 0 y 100.000.000 céntimos (nunca negativo: a diferencia de `amountCents`, aquí no hay gastos). |
| `deadline`, `createdAt` | `timestamp`. |

**El máximo de 10 metas por usuario no está aquí.** `CreateSavingsGoal.maxGoalsPerUser` (aplicación, no reglas) lo comprueba con una consulta de recuento antes de crear; las reglas de Firestore no limitan cuántos documentos de `goals` puede escribir un usuario verificado, igual que ya pasa con `transactions`. Es, a propósito, un límite de cuota razonable aplicado en código, **no una garantía de seguridad**: la comprobación no es atómica (`count()` y `add()` son dos llamadas separadas), así que dos creaciones casi simultáneas desde dos pestañas de la misma cuenta podrían dejar 11 metas en vez de 10 — nada grave depende de que el tope sea exacto (ver "Límites conocidos" más abajo y docs/design.md, "Metas de ahorro").

### Correo verificado, también en las reglas (no solo en la interfaz)

Antes, `AuthGate` ya ocultaba las pantallas con Firestore a quien no hubiera verificado su correo (ver "Autenticación" más abajo), pero las reglas no lo exigían: alguien que llamara directamente a la API de Firebase con una cuenta sin verificar podía seguir leyendo y escribiendo en su propio espacio. `isVerified()` cierra ese hueco exigiéndolo también en el servidor.

- **Las cuentas de Google no necesitan nada nuevo.** Firebase ya marca `email_verified: true` en su token desde el primer inicio de sesión, así que `AppUser.needsEmailVerification` (dominio) ya las trataba como verificadas y la regla nueva no les añade ninguna fricción.
- **El hueco real era el token, no el perfil.** `user.reload()` (lo único que hacía `FirebaseAuthRepository.reloadUser()` hasta ahora) actualiza el `emailVerified` que lee la app para decidir qué pantalla mostrar, pero **no** el token que Firestore valida en sus reglas — ese token puede seguir diciendo `email_verified: false` hasta que expire solo (hasta 1 hora) o se cierre y abra sesión de nuevo. `reloadUser()` ahora hace `await user.reload(); await user.getIdToken(true);`, en ese orden, antes de devolver el `AppUser` — así, para cuando `VerifyEmailScreen` deja pasar a `TransactionsScreen` (`ref.invalidate(authStateChangesProvider)`, que solo se llama después de esperar a `reloadUser()`), el token que usará Firestore ya es el nuevo. Probado en `test/widget_test.dart` ("no muestra la pantalla de movimientos hasta que termina el refresco completo...") con un `FakeAuthRepository.responseGate` que retrasa esa operación a propósito: mientras no se completa, sigue en `VerifyEmailScreen`.
  - Esto no se puede probar con un fake hasta el nivel de `FirebaseAuthRepository` (requeriría un mock del `User` de `firebase_auth`, un paquete nuevo que no se ha añadido): el test de arriba comprueba el contrato que depende de ello (la pantalla no cambia hasta que la operación termina), no las dos llamadas de bajo nivel por separado.
- **Mensaje de error, nunca crudo.** Si Firestore deniega una lectura o escritura (`FirebaseException` con `code: 'permission-denied'` — por ejemplo, con un token todavía no refrescado), `firestoreErrorMessage` (`lib/presentation/common/firestore_error_messages.dart`) lo traduce a "No tienes permiso para ver estos datos. Si acabas de verificar tu correo, cierra sesión y vuelve a entrar.", usado en `TransactionsScreen`, `MonthlyReportScreen` y el resumen de actividad de `ProfileScreen`. A propósito no afirma que la causa sea el correo (podría ser otra), solo lo sugiere como la pista más probable. Cualquier otro error muestra un mensaje genérico de la propia pantalla, nunca el error crudo (`$error`) que se mostraba antes.
- **Flujos no afectados.** Login con Google (ya verificado desde el principio), carga de datos de ejemplo y borrado de cuenta (los dos solo son accesibles tras pasar la verificación, nunca antes) siguen funcionando igual; el orden de `DeleteAccount` (reautenticar → borrar movimientos → borrar la cuenta de Auth) no cambia.

### Pruebas de las reglas contra el emulador (`firestore-tests/`)

Carpeta aparte, sin relación con el proyecto Flutter ni con `pubspec.yaml`: tiene su propio `package.json` (un solo paquete, `@firebase/rules-unit-testing`, versión exacta `6.0.0` sin `^`, con `package-lock.json` versionado; `firestore-tests/node_modules/` en `.gitignore`). Las pruebas (`firestore-tests/rules.test.js`, con el *test runner* nativo de Node, sin `mocha` ni ningún otro paquete) cargan el **`firestore.rules` real de la raíz** por ruta relativa (`path.resolve(__dirname, '..', 'firestore.rules')`) y lo suben al emulador con `initializeTestEnvironment`, nunca una copia.

Para ejecutarlas (Node, npm, Java y el CLI de `firebase` instalados; el emulador de Firestore se descarga solo la primera vez):

```bash
cd firestore-tests
npm install
npm run test:emulator
```

Casos cubiertos, los once ejecutados de verdad contra el emulador el 15/10/2026 (**11 de 11 superados**, `firebase emulators:exec --only firestore "npm test"`, código de salida 0) — los seis de siempre sobre `transactions` (un usuario verificado lee, escribe y borra su propio movimiento; uno sin verificar no puede ni leyendo ni escribiendo, aunque sea el dueño; otro usuario verificado no puede leer ni escribir los movimientos de alguien distinto; sin sesión no se puede nada; los campos inválidos o el importe fuera de rango se rechazan aunque el usuario esté verificado (importe 0, importe por encima de 100.000.000, importe decimal, categoría inexistente, origen inexistente, descripción vacía, campo que falta, campo que no debería estar) — y, dentro de ese mismo caso, un origen `payroll` sí se acepta (`source` válido desde que se añadió la lectura de nóminas, ver "Lectura de nóminas en PDF" más abajo); y las colecciones no previstas se deniegan, tanto dentro de `users/{uid}` como sueltas — más cinco nuevos sobre `goals` (metas de ahorro), el mismo patrón: verificado crea, lee, edita y borra lo suyo; sin verificar no; otro usuario no; sin sesión no; y una batería de campos inválidos (objetivo 0 o negativo, objetivo por encima del límite, ahorrado negativo, importe decimal, nombre vacío o de más de 60 caracteres —con el de exactamente 60 aceptado—, campo que falta, campo que no debería estar).

**Mejora pendiente, opcional, para el CI:** estas pruebas no se ejecutan en `.github/workflows/ci.yml` (que sigue sin tocarse) porque requieren Java y el CLI de `firebase`, software más pesado que lo que ya instala el job de Flutter; se pueden añadir más adelante como un job aparte (`firestore-rules` o similar) que instale Node/Java, haga `cd firestore-tests && npm ci && npm run test:emulator`, y decidir entonces si debe ser bloqueante.

## Límites conocidos

- **Registro abierto.** La aplicación tiene el caso de uso `SignUpWithEmailAndPassword`, aunque la pantalla de login no lo expone. Firebase Auth acepta altas por correo y contraseña mientras el proveedor esté habilitado, y la configuración web de Firebase es pública. Cualquiera con esa configuración podría crear cuentas en masa y consumir la cuota gratuita de Firestore. No he comprobado la configuración del proyecto en la consola de Firebase.
- **App Check solo para Gemini, no para Firestore.** Se activa únicamente cuando `ENABLE_AI` es verdadero y solo con el proveedor de depuración (ver "App Check" más abajo). Firestore sigue sin ninguna comprobación de que las peticiones provienen de la aplicación; el punto anterior (registro abierto) sigue sin resolverse.
- **Sin límite de frecuencia.** Las reglas no limitan cuántos documentos puede escribir un usuario autenticado. Sin Cloud Functions, la única protección de cuota es la que aplique Firebase.
- **Lista de valores fijos.** Las categorías y fuentes válidas están escritas en `firestore.rules`. Si se añade un valor al enum en Dart, hay que añadirlo también en las reglas.
- **Detección del 503 de Gemini por texto, no por código.** `isTransientGeminiError` (`lib/infrastructure/common/gemini_transient_retry.dart`) reconoce un fallo transitorio del servidor buscando `UNAVAILABLE`, `Deadline expired` o `Server Error [503]` dentro del `message` de la excepción, porque el paquete `firebase_ai` no expone el código de estado HTTP como un campo propio para este caso (ver docs/design.md). Si Google cambia el texto exacto de este error, la detección deja de funcionar silenciosamente: el fallo pasaría a tratarse como cualquier otro `service-error`, sin reintento, pero sin romper nada más.
- **Detección del 403 de App Check también por texto.** Igual que el 503, `isAppCheckAttestationError` (`lib/infrastructure/common/app_check_error.dart`) reconoce el 403 `PERMISSION_DENIED`/"App attestation failed" buscando ese texto en el mensaje, no por un código o campo estructurado — la misma limitación, el mismo riesgo si Google cambia el texto exacto (ver "App Check" más abajo).
- **Un 429 por minuto agota un modelo durante 1 hora, aunque la cuota real ya esté disponible.** `GeminiModelAvailability` (mismo archivo) marca un modelo como agotado durante `geminiModelExhaustionDuration` (1 hora) ante cualquier `QuotaExceeded`, sin distinguir el límite que lo causó: un solo pico puntual de 5 RPM (que se resetea en segundos) deja ese modelo fuera de la lista de fallback durante una hora entera, igual que si se hubiera agotado el cupo diario de 20 peticiones. No hay forma de diferenciar ambos casos con la información que da hoy el backend.
- **El máximo de 10 metas de ahorro por usuario es de la aplicación, no de las reglas, y no es atómico.** `CreateSavingsGoal.maxGoalsPerUser` comprueba un recuento antes de escribir; las reglas de `users/{uid}/goals` no imponen ningún tope (ver "Reglas de Firestore" más arriba). Dos creaciones casi simultáneas desde dos pestañas de la misma cuenta podrían dejar 11 metas en vez de 10 — una cuota razonable, no una garantía de seguridad.

## Eliminación de cuenta

- **Reautenticación obligatoria.** Antes de borrar nada, el usuario vuelve a probar su identidad: contraseña (correo y contraseña) o popup de Google. Si falla o se cancela, no se borra ningún dato.
- **Orden.** Primero los movimientos, después la cuenta de Auth. Así, si la cuenta siguiera existiendo tras un fallo, el usuario puede volver a intentarlo; lo contrario dejaría datos huérfanos sin forma de reintentar desde la app.
- **Cobertura.** `userDataCollections` (en `firestore_user_data_repository.dart`) es la lista de colecciones que se borran. Cualquier colección nueva con datos del usuario debe añadirse ahí. Hoy son `transactions` y `goals` (las metas de ahorro, añadida sin tocar `DeleteAccount` ni su orden: `deleteAllForUser` ya es agnóstico de qué colecciones recorre, así que basta con añadir el nombre a la lista). Probado con `test/infrastructure/user_data/firestore_user_data_repository_test.dart`, que compara `userDataCollections` con la lista exacta esperada — si un refactor futuro olvida añadir una colección nueva aquí, ese test falla, en vez de dejar documentos huérfanos en silencio tras borrar la cuenta de Auth.
- **Reglas.** El borrado usa la regla `allow delete` de `users/{uid}/transactions` y, ahora también, de `users/{uid}/goals` (solo el propio usuario en cada una). Las consultas agregadas del resumen usan la regla `allow read` de `transactions`. No hace falta ninguna regla nueva aparte de la propia de `goals`.
- **Sin Cloud Functions.** Todo el borrado lo ejecuta el cliente. Un cierre de la pestaña a mitad deja la cuenta con datos parcialmente borrados; la cuenta sigue existiendo y basta con volver a iniciar sesión y reintentar.
- **Confirmación por correo exacto.** Es una barrera contra clics accidentales, no contra un atacante con sesión iniciada, que ya puede borrar sus datos.
- **Pendiente.** El borrado de movimientos (y de metas) no es atómico: se hace en lotes de 400 y un lote no puede abarcar toda una colección grande. Por eso un fallo a mitad deja datos parciales, que el reintento completa. Una atomicidad total requeriría una Cloud Function que el proyecto no usa por coste.
- **Límite de las pruebas con metas: solo con fakes, no contra el emulador real de punta a punta.** `test/application/auth/delete_account_test.dart` prueba (con `FakeSavingsGoalRepository`) que `DeleteAccount` borra también las metas, incluido un fallo a mitad y su reintento. No existe, para ninguna colección (ni `transactions` ni `goals`), un test de integración en Dart contra el emulador real que ejercite `FirestoreUserDataRepository.deleteAllForUser` de verdad — sigue pendiente en docs/testing.md. Lo que sí se prueba contra el emulador real (ver "Reglas de Firestore" más arriba) es la regla `allow delete` de `goals` en la que se apoya ese borrado.

## App Check (Firebase AI Logic)

Desde noviembre de 2026 Firebase AI Logic exige App Check para llamar a Gemini; sin él, la petición falla con un 401 ("Firebase App Check token is invalid"). Qué proveedor se activa depende de la build y de la plataforma, calculado en `lib/app_check_config.dart` (lógica pura, sin Firebase ni Flutter más allá de `kReleaseMode` y `kIsWeb`, probada en `test/app_check_config_test.dart`; tabla completa de los 7 casos en "Android" más abajo):

| Build | Plataforma | `ENABLE_AI` | `RECAPTCHA_SITE_KEY` | Proveedor | ¿Se muestra la IA? |
|---|---|---|---|---|---|
| Cualquiera | cualquiera | `false` | — | ninguno | No |
| Debug/profile | web o Android | `true` | — | `WebDebugProvider` / `AndroidDebugProvider` | Sí |
| Release | web | `true` | vacía | ninguno | **No** (se oculta, no se deja fallar) |
| Release | web | `true` | con valor | `ReCaptchaEnterpriseProvider` | Sí |
| Release | Android | `true` | con o sin valor | ninguno | **No** (se oculta: no hay proveedor de producción para Android, ver "Android" más abajo) |

**Dónde se decide.** `main.dart`, justo después de `Firebase.initializeApp()`, activa App Check solo si `appCheckConfig.effectiveEnableAi` es verdadero — y `effectiveEnableAi` ya tiene en cuenta todo lo anterior, no solo `ENABLE_AI`:

```dart
// lib/app_check_config.dart
AppCheckConfig chooseAppCheckConfig({
  required bool enableAi,
  required bool isRelease,
  required bool isWeb,
  required String recaptchaSiteKey,
}) {
  if (!enableAi) return /* todo a `none`, IA oculta */;
  if (!isRelease) return /* debug en web y Android, IA visible */;
  if (!isWeb) return /* Android en release: todo a `none`, IA oculta */;
  final hasSiteKey = recaptchaSiteKey.isNotEmpty;
  return /* web en release: reCAPTCHA Enterprise si hay clave, si no `none`;
            IA visible solo si hay clave */;
}
```

Las pantallas (`TransactionsScreen`) comprueban `effectiveEnableAi`, no `enableAi` a secas, para decidir si muestran el botón del chat y la entrada en lenguaje natural. Así, un release sin `RECAPTCHA_SITE_KEY` (web) o que no sea web (Android) **no intenta activar la IA, la oculta** igual que si `ENABLE_AI` fuera `false`, en vez de dejarla fallar sin ningún error visible para quien usa la app.

### Depuración (desarrollo local)

Sin cambios respecto a antes, solo que ahora está condicionado explícitamente a que la build **no** sea de release (`kReleaseMode` falso):

```dart
await FirebaseAppCheck.instance.activate(
  providerWeb: WebDebugProvider(),
  providerAndroid: const AndroidDebugProvider(),
);
```

**Dónde aparece el token de depuración.**

- **Web:** en la consola del navegador (F12 → Console), como `AppCheck debug token: "xxxxxxxx-xxxx-...".`. `WebDebugProvider()` sin `debugToken` hace que el SDK de Firebase lo genere y lo guarde en el almacenamiento local del navegador; se mantiene estable en ese navegador y esa máquina mientras no se borre el almacenamiento del sitio.
- **Android:** en el log de Android (logcat / `flutter run` en la terminal), como `Enter this debug secret into the allow list in the Firebase Console: xxxxxxxx-xxxx-...`. Se genera una vez por instalación y se mantiene mientras no se desinstale la app o se borren sus datos.

**Qué hace falta en la consola de Firebase.** Copiar ese token y registrarlo en *Firebase Console → (icono de engranaje) Project settings → App Check → pestaña Apps → menú de los tres puntos de la app correspondiente (web o Android) → Manage debug tokens → Add debug token*. Hay que registrarlo por separado para la app web y para la app Android, y volver a hacerlo si alguna vez se borra el almacenamiento/los datos que lo guardan (saldría un token nuevo).

**Por qué no hay ningún token de depuración en el repositorio.** El token no lo escribe el código: se genera en el dispositivo (navegador o móvil) la primera vez que se activa App Check, y Firebase lo guarda localmente ahí, no en ningún archivo del proyecto. No se ha tocado `web/index.html`: el proveedor de depuración de `firebase_app_check` fija la variable global `FIREBASE_APPCHECK_DEBUG_TOKEN` desde Dart en tiempo de ejecución, dentro del propio paquete, así que no hace falta (ni se debe) añadir ese script a mano.

### Producción en web: Fraud Defense (reCAPTCHA Enterprise)

**Proveedor.** `ReCaptchaEnterpriseProvider(siteKey)` (paquete `firebase_app_check` 0.4.8 / `firebase_app_check_platform_interface` 0.4.2+1, clase confirmada leyendo `lib/src/web_providers.dart` del paquete en `.pub-cache`). Es el proveedor "Fraud Defense" que recomienda la consola de Firebase para App Check en web.

**Clave de sitio, nunca en el repo.** `recaptchaSiteKey` (`lib/enable_ai.dart`) es `String.fromEnvironment('RECAPTCHA_SITE_KEY')`: vacía por defecto, solo tiene un valor real si quien compila la pasa con `--dart-define`. No se escribe en ningún archivo del repositorio ni se hardcodea en ningún sitio; hay que crearla en *Firebase Console → App Check → Apps → app web → reCAPTCHA Enterprise* (o directamente en Google Cloud Console, reCAPTCHA Enterprise) y pegarla solo en el comando de compilación, o en un `--dart-define-from-file` que apunte a un archivo fuera de control de versiones.

**Comando de compilación (producción, web):**

```bash
flutter build web --release \
  --dart-define=ENABLE_AI=true \
  --dart-define=RECAPTCHA_SITE_KEY=<clave-de-sitio-de-reCAPTCHA-Enterprise>
```

Sin el segundo `--dart-define`, la build compila igual (no rompe nada: ver la tabla de arriba), pero la IA queda oculta por `effectiveEnableAi`.

**Nivel gratuito.** reCAPTCHA Enterprise (evaluaciones de "assessment", que es lo que consume App Check al canjear un token) tiene un nivel gratuito de **10.000 evaluaciones al mes por organización de Google Cloud** (no por proyecto ni por app). Superado ese límite, las peticiones de evaluación empiezan a fallar — no se cobra automáticamente, hay que activar explícitamente la facturación de reCAPTCHA Enterprise en Google Cloud para que siga funcionando por encima del nivel gratuito. Con 20 peticiones/día de cuota gratuita de Gemini como tope real de uso (ver docs/design.md), 10.000 evaluaciones/mes es muy holgado para este proyecto.

**TTL del token.** 1 hora: igual que el resto de proveedores de App Check, el SDK cliente cachea el token y solo canjea uno nuevo cuando el que tiene en memoria/almacenamiento está a punto de caducar (o no existe), así que no se gasta una evaluación de reCAPTCHA en cada llamada a Gemini, solo aproximadamente una por hora de uso continuado.

**`useLimitedUseAppCheckTokens`.** Sigue sin activarse (igual que con el proveedor de depuración): solo aporta algo junto con la protección contra repetición ("replay protection") de App Check, que no se ha activado.

### Android: sin proveedor de producción, la IA se oculta en release

No se ha implementado un proveedor de producción para Android. `chooseAppCheckConfig` (`lib/app_check_config.dart`) recibe también `isWeb` (resuelto una sola vez con `kIsWeb`): en release, `effectiveEnableAi` solo puede ser verdadero en **web** y con `RECAPTCHA_SITE_KEY` no vacía; en cualquier otra plataforma (Android) en release, `effectiveEnableAi` es siempre `false`, aunque haya clave de reCAPTCHA y aunque `ENABLE_AI=true` — igual que si `ENABLE_AI` fuera `false`, y sin activar App Check. Antes de este cambio, un release de Android con `ENABLE_AI=true` y clave mostraba la IA y las llamadas a Gemini fallaban con el 403 que se describe más abajo (`AndroidPlayIntegrityProvider()` por defecto, sin Play Integrity configurado ni probado: falta registrar la huella SHA-256 de la build de release en Firebase Console y vincular la app a un listado de Play Console). El proveedor de depuración de Android (`AndroidDebugProvider`) solo se usa en builds que no son de release, en cualquier plataforma.

**Tabla de casos (`chooseAppCheckConfig`), probada en `test/app_check_config_test.dart`:**

| `ENABLE_AI` | Build | Plataforma | Clave reCAPTCHA | `effectiveEnableAi` | Proveedor web | Proveedor Android |
|---|---|---|---|---|---|---|
| `false` | cualquiera | cualquiera | — | `false` | `none` | `none` |
| `true` | debug/profile | web | no hace falta | `true` | `debug` | `debug` |
| `true` | debug/profile | Android | no hace falta | `true` | `debug` | `debug` |
| `true` | release | web | vacía | `false` | `none` | `none` |
| `true` | release | web | no vacía | `true` | `recaptchaEnterprise` | `none` |
| `true` | release | Android | vacía | `false` | `none` | `none` |
| `true` | release | Android | no vacía | **`false`** | `none` | `none` |

Las dos últimas filas son el caso que motivó el cambio: antes, un release de Android con clave de reCAPTCHA (una clave pensada solo para web) daba `effectiveEnableAi: true` por error.

### Errores de App Check al llamar a Gemini (403, no 401)

Visto de verdad el 8 de octubre de 2026, al activar App Check contra un proyecto real: cuando el token de App Check no es válido, Gemini (vía Firebase AI Logic) no siempre responde con el 401 genérico de "token inválido" — con un token que el backend rechaza específicamente, responde **403 `PERMISSION_DENIED`** con un mensaje como `"App attestation failed."`. `isAppCheckAttestationError` (`lib/infrastructure/common/app_check_error.dart`) reconoce este caso por texto (`App attestation failed` o `PERMISSION_DENIED` en el mensaje del `FirebaseAIException`, descartando explícitamente `QuotaExceeded`) y los dos gateways (`GeminiChatGateway`, `GeminiLlmGateway`) lo traducen a `LlmGatewayException('app-check-failed', ...)`, que la presentación muestra siempre como "La IA no está disponible ahora mismo" — nunca el JSON crudo del error. No se reintenta (no es un fallo transitorio: `isTransientGeminiError` no lo reconoce) ni marca el modelo como agotado (no es `QuotaExceeded`, así que `withGeminiModelFallback` no lo toca). Probado con fakes en `test/infrastructure/common/app_check_error_test.dart` y en `test/presentation/chat/chat_error_messages_test.dart` / `test/presentation/transactions/llm_error_messages_test.dart` (este último también cubre la entrada en lenguaje natural). Esta misma detección por texto (en vez de por un campo estructurado) es la misma limitación que ya tiene `isTransientGeminiError` para el 503 — ver "Límites conocidos" más abajo.

## Android

**Estado: funciona en modo debug, no en release.** Probado en un móvil físico el 11/10/2026: inicio de sesión con correo, movimientos, resumen mensual, entrada en lenguaje natural y chat, todo con el token de depuración de App Check registrado por el administrador del proyecto (ver "Depuración (desarrollo local)" más arriba). El inicio de sesión con Google de esa prueba usaba `signInWithProvider`, el flujo que resultó estar bloqueado (ver "Inicio de sesión con Google en Android" más abajo) — se ha sustituido por el SDK nativo. Comprobado en un móvil físico el 17/10/2026: el inicio de sesión con Google con el SDK nativo funciona, con el selector de cuentas nativo (sin pestaña de Chrome). En una build de **release** no hay ningún proveedor de App Check de producción configurado — Play Integrity exige vincular la app en Play Console, y eso no se ha hecho — así que el APK de release se entrega sin IA: queda oculta automáticamente (`chooseAppCheckConfig`), sin intentar activar App Check, en vez de mostrarla y dejarla fallar (ver "Android: sin proveedor de producción, la IA se oculta en release", dentro de "App Check" más arriba, con la tabla completa de casos).

El APK de depuración con la IA activada se genera con `flutter build apk --debug --dart-define=ENABLE_AI=true`. La IA solo funciona en el móvil donde está registrado el token de depuración de App Check de esa instalación (ver "Depuración (desarrollo local)" más arriba); ese APK no se distribuye.

**`google-services.json` no se versiona.** Está en `.gitignore` (ver "Autenticación" más arriba); cada desarrollador tiene que descargar su propia copia desde *Firebase Console → Configuración del proyecto → tus apps → app Android → google-services.json* y colocarla en `android/app/`.

**Huella SHA-1 de depuración registrada.** La huella SHA-1 del *debug keystore* (la que genera Flutter/Gradle para compilaciones de depuración) está registrada en Firebase Console para la app Android del proyecto; es necesaria para que el inicio de sesión con Google funcione en Android (el inicio de sesión con correo y contraseña no depende de ella) — sigue siéndolo con el SDK nativo (`google_sign_in`) igual que lo era con `signInWithProvider`.

**Clave de API de Android restringida en Google Cloud.** La clave de API que trae `google-services.json` para la app Android está restringida en *Google Cloud Console → APIs y servicios → Credenciales* por nombre de paquete (`com.example.accounting_saver`) y por la huella SHA-1 de la clave de depuración, con las restricciones de API que traía por defecto (no se han cambiado). No se escriben aquí ni la clave ni la huella. Comprobado el 11/10/2026: con esa restricción aplicada, el inicio de sesión con correo, los movimientos, el resumen mensual y el chat seguían funcionando en un móvil físico (el inicio de sesión con Google de esa misma prueba fue el que luego resultó bloqueado — ver más abajo). Si en el futuro se firmara con una clave de release, habría que añadir su SHA-1 tanto a esta restricción en Google Cloud como a Firebase (ver "Huella SHA-1 de depuración registrada" arriba).

### Inicio de sesión con Google en Android: `signInWithProvider` bloqueado, sustituido por el SDK nativo

**Qué fallaba.** `signInWithProvider` (el flujo por pestaña de Chrome/Custom Tabs de `firebase_auth` para proveedores OAuth en plataformas nativas) recibía un 403 de `identitytoolkit.googleapis.com`: `"Requests from this Android client application <empty> are blocked"`. Descartado un problema de configuración: huella SHA-1, nombre de paquete, APIs habilitadas y `google-services.json` (`oauth_client` de tipo 1 y 3) estaban correctos, y el correo y contraseña funcionaban con la misma configuración.

**La solución.** `NativeGoogleCredential` (`lib/infrastructure/auth/native_google_credential.dart`, ver docs/design.md para el detalle completo) usa el SDK nativo de `google_sign_in` (añadido a `pubspec.yaml`, `^6.3.0` — el único paquete nuevo de este cambio) para abrir el selector de cuenta y obtener un `idToken`, que `GoogleAuthProvider.credential`/`signInWithCredential` validan — sin pasar por `identitytoolkit` vía una pestaña de Chrome. Solo en Android (y el resto de plataformas nativas); la web sigue con `signInWithPopup`/`reauthenticateWithPopup`, sin cambios. Cubre tanto el inicio de sesión como la reautenticación antes de borrar la cuenta (`reauthenticateWithGoogle`), que tenía el mismo problema.

**Minimización: nada se registra en logs.** Ni el `idToken`/`accessToken` ni ningún dato de la cuenta de Google (correo, nombre, foto) pasan por ningún `print`/`debugPrint` — mismo principio que el resto de la autenticación.

**Cancelar el selector no es un error.** Se traduce a un mensaje neutro ("Se canceló el inicio de sesión con Google."), nunca al mensaje de error genérico ni a texto crudo de la plataforma.

**Nombre de paquete por renombrar.** El `applicationId` sigue siendo el que pone Flutter por defecto al crear el proyecto, `com.example.accounting_saver` (`android/app/build.gradle.kts`), pendiente de renombrar antes de publicar.

**Avisos de Gradle sobre el plugin de Kotlin.** Al compilar para Android aparecen avisos de Gradle sobre el plugin de Kotlin en los paquetes `firebase_ai`, `firebase_app_check`, `firebase_auth` y `firebase_core`. Vienen de esos paquetes (de cómo declaran su propio soporte de Kotlin), no de código de este proyecto; se resolverán cuando esos paquetes publiquen una versión que lo soporte.

**Desbordamientos de layout, corregidos.** Se detectaron y corrigieron dos desbordamientos específicos de pantallas Android estrechas: uno vertical (el estado vacío de movimientos y de chat no cedía cuando se abría el teclado) y uno horizontal (una fila del resumen mensual y el desplegable de categoría del formulario de movimiento no cedían en pantallas de poco ancho). Corregidos en la rama `fix/android-layout`.

## Claves de cliente de Firebase

Las claves de `lib/firebase_options.dart` y la clave de sitio de reCAPTCHA (App Check en producción web, ver más arriba) son **identificadores públicos por diseño**: en una aplicación web viajan dentro del propio JavaScript que se sirve al navegador, así que no se pueden ocultar — cualquiera que abra las herramientas de desarrollador las ve. No son el mecanismo de seguridad; son la forma en que el cliente se identifica ante Firebase.

La seguridad de los datos y del uso de la IA la dan, en conjunto:

- **Las reglas de Firestore** (`firestore.rules`): cada usuario solo puede leer, crear, editar y borrar sus propios movimientos, y solo con el correo verificado (`isOwner(userId)` + `isVerified()`, ver "Reglas de Firestore" más arriba).
- **Firebase Auth**: identifica quién hace cada petición; las reglas de Firestore se evalúan contra ese `request.auth`, no contra la clave de cliente.
- **App Check, aplicado (*enforced*) en Firebase AI Logic** desde el 11/10/2026 (ver "App Check" más arriba): una petición a Gemini sin un token de App Check válido se rechaza antes de llegar al modelo, aunque quien la haga conozca la clave de cliente. App Check **no** está aplicado en Firestore; ahí la protección son las reglas del punto anterior.
- **La restricción de la clave de navegador por sitios web, en Google Cloud.** Estado comprobado el 11/10/2026 en *Google Cloud Console → APIs y servicios → Credenciales*, para la clave de API del proyecto `accounting-saver`:
  - **Restricciones de aplicación:** "Sitios web", con estos orígenes exactos: `https://accounting-saver.web.app/*`, `https://accounting-saver.firebaseapp.com/*`, `http://localhost:5000/*`, `http://localhost:8080/*`. Una petición con esta clave desde cualquier otro origen es rechazada por Google antes de llegar a Firebase.
  - **Restricciones de API:** "Restringir clave", con la lista por defecto de Firebase (25 APIs): Cloud Datastore, Cloud Firestore, Cloud Logging, Cloud SQL Admin, Cloud Storage for Firebase, FCM Registration, Firebase AI Logic, Firebase App Check, Firebase App Distribution, Firebase App Hosting, Firebase App Testers, Firebase Hosting, Firebase In-App Messaging, Firebase Installations, Firebase Management, Firebase ML, Firebase Phone Number Verification, Firebase Realtime Database Management, Firebase Remote Config, Firebase Remote Config Realtime, Firebase Rules, Firebase SQL Connect, Identity Toolkit, ML Kit y Token Service. Incluye todas las que de verdad usa la app (Identity Toolkit, Cloud Firestore, Firebase AI Logic, Firebase App Check, Firebase Installations, Token Service y Firebase Hosting); no se ha recortado esta lista por defecto, para no arriesgar que falte una API que la app necesite y algo deje de funcionar.
  - **Por qué `localhost:5000` y `localhost:8080`, no cualquier puerto.** La lista de orígenes de arriba es exacta, no un patrón abierto a cualquier puerto de `localhost`: ejecutar la app en local **tiene que ser** con `flutter run ... --web-port=5000` (ver README, "Instalación y ejecución") o, servida con Docker, en el puerto 8080 (el que ya fija `docker-compose.yml`/`Dockerfile`, ver "Docker" más abajo); cualquier otro puerto de `localhost` no está en la lista y la clave sería rechazada por Google antes de llegar a Firebase.
- **La clave real de la API de Gemini nunca sale del servidor.** El cliente nunca tiene ni usa una clave de la API de Gemini: llama a Firebase AI Logic con la configuración de cliente de arriba (identificación de proyecto, no autenticación de la llamada a Gemini) y es Firebase, en su infraestructura, quien habla con la API de Gemini con sus propias credenciales de servidor.
- **Plan Spark: un abuso agotaría cuota gratuita, no generaría cargos.** El proyecto está en el plan Spark de Firebase (sin facturación vinculada, ver CLAUDE.md), así que alguien que abusara de estas claves públicas (dentro de los orígenes y las APIs permitidas) agotaría la cuota gratuita compartida del proyecto —dejando la IA o el resto de servicios sin disponibilidad para todos los usuarios—, pero no podría generar un cargo económico: no hay una cuenta de facturación que cobrar.

**Riesgos conocidos, no resueltos:**

- **La restricción por sitios web se puede falsificar desde un script.** La cabecera `Referer`/origen que Google comprueba la envía el propio cliente; quien llame a la API directamente (no desde un navegador, por ejemplo con `curl` o un script) puede falsificarla. La restricción frena el uso casual desde un sitio no autorizado, no a quien se moleste en imitar el origen.
- **El registro abierto de cuentas por la API de Auth sigue pendiente de decisión** (ver "Límites conocidos" más abajo): nada en estas restricciones impide crear cuentas en masa por correo y contraseña mientras el proveedor esté habilitado.

## Escaneo de secretos (gitleaks)

Escaneo manual con [gitleaks](https://github.com/gitleaks/gitleaks) sobre todo el historial del repositorio, ejecutado el 11/10/2026, sin ningún hallazgo aparte de las dos claves de cliente de Firebase descritas arriba (`lib/firebase_options.dart`), aceptadas explícitamente en `.gitleaksignore` con un comentario que explica por qué son públicas por diseño. No está integrado en el CI (`.github/workflows/ci.yml` no tiene ningún job de gitleaks); es una comprobación manual.

Para repetirlo con Docker (no requiere instalar gitleaks en la máquina):

```bash
docker run --rm -v "$PWD:/repo" ghcr.io/gitleaks/gitleaks:latest detect --source /repo -v
```

## Datos demo

`LoadDemoData` escribe en la colección del propio usuario autenticado, en un `WriteBatch` cuyos documentos cumplen las mismas reglas que las escrituras individuales.

## Entrada de datos

- Los importes se validan con `parseEurosToCents` (formato y límite) antes de crear la transacción.
- Las descripciones se recortan con `trim()` y se limitan a 200 caracteres en el formulario, en el dominio y en las reglas.

## Validación de la salida de Gemini (entrada en lenguaje natural)

No nos fiamos de que el modelo solo devuelva lo que le hemos pedido. Hay tres capas, cada una independiente de las demás:

1. **El esquema no obliga a inventar.** `amountCents`, `date`, `description` y `category` son `nullable` en el `responseSchema`, y hay un campo `understood` (booleano) aparte. Antes de este cambio, el esquema exigía esos cuatro campos siempre, así que un texto sin importe (`"asdf"`) obligaba al modelo a inventarse uno (devolvía 1 céntimo). El prompt le pide explícitamente que, si no hay un importe claro, devuelva `understood: false` y deje el resto sin indicar, y que nunca invente ni deduzca un importe, un concepto o una categoría que no estén en el texto.
2. **El caso de uso no se fía solo de `understood`.** `ParseNaturalLanguageTransaction` rechaza igual si `understood` es `false`, o si es `true` pero falta cualquiera de los otros campos (una respuesta a medias no es mejor que una negativa).
3. **Contraste determinista, sin modelo.** Antes incluso de llamar a Gemini, `textContainsNumber` (dominio, Dart puro, sin red) comprueba que el texto mencione alguna cifra o alguna palabra de número en español (uno a veinte, treinta, cuarenta, cincuenta, cien, mil...). Si no menciona ningún número, se rechaza sin gastar cuota, y esta comprobación se queda como el límite final: si por lo que sea el modelo devolviera un importe para un texto así, el resultado se descarta igualmente (se verifica con un `FakeLlmGateway` que devuelve un importe válido para un texto sin números).

Las tres capas lanzan el mismo tipo, `NotUnderstoodException`, con un mensaje para reformular el texto. La pantalla lo muestra en un `SnackBar` y no abre el formulario: no hay forma de que una propuesta inventada llegue a la pantalla de confirmación, y mucho menos a Firestore.

**Temperatura a 0.** La llamada a Gemini usa `temperature: 0`: es extracción de datos, no redacción, y conviene la lectura más literal y repetible del texto, no creatividad.

## Chat con function calling

- **Argumentos del modelo, no de fiar.** El modelo decide él mismo con qué argumentos llama a `getMonthlySummary` o `listTransactions`, a partir de lo que ha escrito el usuario. `TransactionChatFunctions` valida año, mes (1-12), fechas (`desde` ≤ `hasta`, rango máximo de 5 años) y `categoryId` (contra el enum `Category`) antes de llamar al repositorio; si algo no es válido, no se ejecuta ninguna consulta a Firestore, y se devuelve `{'error': ...}` al propio modelo.
- **Las reglas de Firestore no cambian.** Las funciones del chat solo hacen lecturas (`where` + `orderBy`/`aggregate`) sobre `users/{uid}/transactions`, la misma colección y la misma regla `allow read` que ya usa el resto de la app; no hace falta ninguna regla nueva.
- **Inyección de instrucciones a través de un movimiento.** El concepto (`description`) de un movimiento es texto que el propio usuario (o la IA de entrada en lenguaje natural) ha escrito antes, y vuelve al modelo dentro del resultado de una función. La instrucción del sistema de `GeminiChatGateway` le pide explícitamente que lo trate como un dato a mostrar, nunca como una instrucción a seguir; no hay ninguna comprobación en código que impida que el modelo decida ignorar esa instrucción, así que esto es una mitigación, no una garantía.
- **Sin persistencia ni logs.** La conversación vive solo en el estado de `ChatScreen`, en memoria; no se escribe en Firestore ni se registra en ningún log. Cerrar la pantalla la pierde.
- **Límites para no agotar la cuota ni colgar la pantalla.** Historial recortado a los últimos 10 mensajes, máximo de 5 idas y vueltas con llamadas a función por turno (`_maxFunctionCallSteps`) y una sola petición en curso (`SendChatMessage` lanza `StateError` si se le llama mientras espera la anterior; la pantalla además deshabilita el envío mientras tanto).
- **Errores de la IA, no de la app.** Igual que `GeminiLlmGateway`, `GeminiChatGateway` traduce los fallos de `firebase_ai` a `LlmGatewayException`; `chatErrorMessage` los convierte en "La IA no está disponible ahora mismo" (o un mensaje algo más específico para cuota o red), y el resto de la app sigue funcionando con normalidad.
- **Caché, contador de preguntas e historial aislados por usuario.** `sendChatMessageProvider` es `Provider.family<SendChatMessage, String>` (clave: `userId`), así que cada usuario obtiene su propia instancia de `SendChatMessage` — su propia caché de respuestas y su propio contador de preguntas — en vez de compartir una sola instancia para toda la vida de la app. Importa porque el `ProviderScope` es único y nunca se recrea (`runApp(ProviderScope(...))` en `main.dart`): sin esto, cerrar sesión y entrar con otra cuenta en la misma sesión de la app podría servirle a un usuario la respuesta cacheada de otro, o heredar su contador ya gastado. El historial de la conversación (en el estado de `ChatScreen`, no en un provider) se vacía solo porque `AuthGate` desmonta `TransactionsScreen` (y cualquier `ChatScreen` empujado desde ella) al pasar por `LoginScreen` entre dos usuarios distintos — nunca actualiza una pantalla ya montada con un `userId` nuevo. Probado en `test/presentation/chat/chat_screen_test.dart`: usuario A pregunta y cachea una respuesta; tras el cambio de usuario, la misma pregunta de B no la reutiliza (vuelve a llamar al gateway), el contador de B empieza en 20 de 20 (`maxQuestionsPerSession`), y no queda ningún mensaje de A visible.
- **Mismo App Check que la entrada en lenguaje natural.** El chat usa el mismo `GenerativeModel` por debajo (Gemini Developer API vía Firebase AI Logic) y solo está disponible con `ENABLE_AI`, así que depende de la misma configuración de App Check descrita arriba; no se ha añadido nada nuevo.
- **Sin índices compuestos.** Al probar el chat contra un proyecto real, una consulta que combinaba el rango de `date` con `amountCents` falló con `FAILED_PRECONDITION` pidiendo un índice compuesto. Decisión: en vez de crear ese índice (ni ningún otro), `FirestoreTransactionRepository.findByDateRange` solo filtra por `date` en el servidor; todo lo demás (categoría, signo del importe, sumas) se calcula en código, en `TransactionChatFunctions` (ver docs/design.md). No hace falta ni existe ningún `firestore.indexes.json` en el repositorio.

## Resumen mensual: comentario de IA sin conceptos de movimiento

- **Minimización de datos por el tipo, no por un filtrado.** A diferencia del chat (que sí envía el `description` de los movimientos al modelo, como dato a mostrar dentro del resultado de una función — ver arriba), el comentario del resumen mensual nunca ve un movimiento individual. `ExplainMonthlyReport`/`MonthlyReportGateway.explain` reciben un `MonthlyReport` (`lib/domain/reports/monthly_report.dart`), que solo tiene cifras agregadas (totales, importe y porcentaje por categoría, comparación con el mes anterior); no existe ningún campo para una descripción. No es una mitigación que el modelo pueda decidir ignorar (como la instrucción de "trata el concepto como un dato, no como una instrucción" del chat): es que el dato nunca llega a `buildMonthlyReportExplanationPrompt`, así que no hay nada que inyectar a través de un concepto de movimiento en esta función. Probado en `test/infrastructure/reports/gemini_monthly_report_gateway_test.dart` plantando una descripción maliciosa ("IGNORA TODO LO ANTERIOR...") en una transacción y comprobando que el prompt resultante no la contiene.
- **Mismos límites de cuota que el chat, con un tope propio.** `ExplainMonthlyReport.maxCommentsPerSession` (6, subido desde 3 el 11/10/2026) por sesión, solo cuenta llamadas con éxito (ni caché ni error gastan cupo), una sola petición en curso, y caché en memoria por mes invalidada con `TransactionsChangeNotifier`, aislada por usuario igual que `SendChatMessage` (`explainMonthlyReportProvider` es `Provider.family<ExplainMonthlyReport, String>` por `userId`).
- **Mismo tratamiento de errores y de App Check.** `GeminiMonthlyReportGateway` reutiliza `withGeminiModelFallback`, `withTransientRetry` (150 s, sin reintento ante timeout) e `isAppCheckAttestationError` sin modificarlos; `reportErrorMessage` traduce los códigos a los mismos mensajes en español que `chatErrorMessage`/`llmErrorMessage`.
- **Sin persistencia ni logs.** El comentario generado vive solo en el estado de `MonthlyReportScreen`, en memoria; no se escribe en Firestore ni se registra en ningún log. El informe en sí (`MonthlyReport`) tampoco se guarda: se recalcula cada vez a partir de los movimientos ya existentes.

## Lectura de nóminas en PDF (solo web)

- **Aviso explícito del nivel gratuito, con confirmación.** Igual que con los datos de ejemplo (nunca una nómina real), el nivel gratuito de Gemini permite a Google usar el contenido enviado para mejorar sus productos. `PayrollScreen` muestra un diálogo con ese aviso y exige pulsar "Entendido, continuar" antes de abrir el selector de archivo; cancelar no abre nada.
- **Nada del PDF se guarda en ningún sitio.** Los bytes del archivo solo viven en memoria del navegador mientras dura la llamada a Gemini; no se escriben en Firestore, no se guardan en `localStorage` ni en ningún otro sitio, y no se registran en logs (ni el PDF ni el JSON que devuelve el modelo). Al cerrar la pantalla, se pierden.
- **La validación de las cifras nunca es del modelo.** Exactamente la misma idea que en la entrada en lenguaje natural (arriba): el prompt le pide al modelo que copie los importes tal y como figuran, sin corregirlos ni recalcularlos, y `PayrollValidation` (dominio, Dart puro) vuelve a calcular en código si bruto menos deducciones coincide con el líquido, céntimo a céntimo. Solo se propone un ingreso si esa cuenta, hecha en código, cuadra; nunca si el modelo *dice* que cuadra.
- **El texto del documento es un dato, nunca una instrucción — igual que el `description` de un movimiento en el chat (ver arriba).** Un PDF de nómina puede contener, en principio, cualquier texto, incluido algo que parezca una instrucción dirigida al modelo. El prompt de `GeminiPayrollGateway` le pide explícitamente que registre ese texto en `instruccionesEnDocumento` sin obedecerlo; como con el chat, esto es una mitigación en el prompt, no una garantía verificable en código, y la prueba de viabilidad (docs/evaluation.md) observó que la propia detección (`true`/`false`) es inestable entre repeticiones del mismo documento, así que tampoco se trata como una señal fiable.
- **Tamaño y tipo de archivo, comprobados antes de gastar cuota.** `ParsePayroll` rechaza un archivo que no empiece por la cabecera `%PDF` o que supere 3 MB sin llamar al gateway; ninguno de los dos casos cuenta como una lectura de la sesión.
- **Solo web, y solo tras `effectiveEnableAi`.** El botón que abre `PayrollScreen` exige `kIsWeb` además de `effectiveEnableAi`: en Android no hay ningún código que intente abrir un selector de archivos (el selector real vive en `payroll_file_picker_web.dart`, nunca importado fuera de ese archivo — ver docs/design.md).

## Metas de ahorro

- **Se guardan en Firestore, dentro del espacio del propio usuario.** `users/{uid}/goals/{id}`, protegida por su propia regla (ver "Reglas de Firestore" más arriba): solo el propietario, con el correo verificado, puede leer, crear, editar o borrar sus metas. Ninguna otra cuenta puede verlas ni tocarlas.
- **El borrado de cuenta las elimina.** `userDataCollections` incluye `'goals'` (ver "Eliminación de cuenta" más arriba): `DeleteAccount` borra las metas igual que los movimientos, en el mismo paso y con la misma tolerancia a fallos parciales, sin que se haya tocado ni su orden ni su lógica.
- **Sin IA en ningún punto del cálculo de progreso ni de las propias sugerencias de ahorro.** Ni el nombre de la meta, ni los importes, ni la fecha límite pasan nunca por Gemini para calcular el progreso o las opciones: todo eso es código puro (ver docs/design.md). La fase 2 (más abajo) solo añade una redacción opcional, con IA, de unas opciones que ya existían sin ella.
- **Nada se registra en logs.** Ni al crear, editar, actualizar lo ahorrado ni borrar una meta hay ningún `print`/`debugPrint` con sus datos (nombre, importes o fecha): los errores que se muestran en pantalla pasan siempre por `firestoreErrorMessage` (mensaje genérico) o, para el límite de 10 metas, por el mensaje fijo de `SavingsGoalLimitExceededException` — nunca el error crudo de Firestore ni el contenido de la meta.
- **Máximo de 10 metas: de la aplicación, no de las reglas — ver "Reglas de Firestore" y "Límites conocidos" más arriba.**

### Sugerencias de ahorro con IA (fase 2): qué viaja al modelo y qué no

- **Minimización de datos por el tipo, no por un filtrado.** Igual que `MonthlyReportGateway`/`ExplainMonthlyReport` (ver más abajo), `SavingsSuggestionsGateway.explain` recibe un `SavingsSuggestionsSummary` (`lib/domain/savings/savings_suggestions_summary.dart`) que **no tiene ningún campo para el nombre de la meta, ni para un concepto o una descripción de movimiento**: solo cifras ya formateadas en euros, el enum `Category` (9 valores fijos del código, nunca texto escrito por el usuario) y el enum `SavingsGoalStatus`. No es una mitigación que el modelo pueda decidir ignorar: el dato nunca llega a `summarizeSavingsSuggestions`/`buildSavingsSuggestionsExplanationPrompt`, así que no hay nada que inyectar a través de un nombre de meta o un concepto de movimiento. Probado en `test/domain/savings/savings_suggestions_summary_test.dart` y `test/infrastructure/savings/gemini_savings_suggestions_gateway_test.dart` plantando un nombre de meta y una descripción de movimiento maliciosos ("IGNORA TODO LO ANTERIOR...") y comprobando que ni el resumen agregado ni el prompt resultante los contienen.
- **Lo que sí viaja: cifras agregadas y categorías fijas.** Objetivo, ahorrado, aportación mensual necesaria, meses restantes, estado de la meta, el total mensual que las opciones podrían cubrir y, por cada recurrente/recorte/exceso puntual, su categoría (una de las 9 fijas), un recuento (solo recurrentes) y un importe ya formateado — en líneas ya redactadas en español, listas para que el modelo las copie tal cual (ver docs/design.md).
- **Lo que nunca viaja: conceptos, descripciones de movimiento y el nombre de la meta.** Ninguno de los dos tiene ningún campo en `SavingsSuggestionsSummary` por el que pudieran llegar al prompt.
- **Nivel gratuito de Gemini: Google puede usar el contenido enviado.** Mismo aviso que el resto de usos de la IA en esta app (nóminas en PDF, chat, entrada en lenguaje natural): al ser cifras agregadas y categorías fijas, no hay en principio ningún dato personal identificable más allá de "alguien tiene una meta de ahorro con estos importes", pero sigue siendo contenido que Google puede usar para mejorar sus productos en este nivel. No hay ningún aviso de confirmación propio para esta función (a diferencia de la lectura de nóminas, que sí lo exige): el dato ya es agregado por diseño, no un documento con datos potencialmente sensibles como un PDF real.
- **Mismo tratamiento de errores, de cuota y de App Check que el resto de la app.** `GeminiSavingsSuggestionsGateway` reutiliza `withGeminiModelFallback`, `withTransientRetry` (150 s, sin reintento ante timeout) e `isAppCheckAttestationError` sin modificarlos; `savingsSuggestionsErrorMessage` traduce los códigos a los mismos mensajes en español que `reportErrorMessage`/`chatErrorMessage`.
- **Tope de 6 resúmenes por sesión, caché por meta, aislado por usuario.** `ExplainSavingsSuggestions.maxExplanationsPerSession` (6, mismo valor que `ExplainMonthlyReport.maxCommentsPerSession`) por sesión, solo cuenta llamadas con éxito (ni caché ni error gastan cupo), caché en memoria por `goal.id` invalidada si cambian los movimientos (`TransactionsChangeNotifier`) o la propia meta (`savedCents`/`targetCents`/`deadline`), y `explainSavingsSuggestionsProvider` es `Provider.family<ExplainSavingsSuggestions, String>` por `userId` (mismo patrón que `explainMonthlyReportProvider`/`sendChatMessageProvider`): cerrar sesión y entrar con otra cuenta no hereda ni el texto cacheado ni el cupo ya gastado.
- **Sin persistencia ni logs.** El texto generado vive solo en el estado de `SavingsSuggestionsSheet`, en memoria; no se escribe en Firestore ni se registra en ningún log. Las propias opciones de ahorro (`SavingsSuggestionsResult`) tampoco se guardan: se recalculan cada vez que se abre la hoja.
- **No juzga la meta ni da ánimo o presión.** La instrucción de sistema prohíbe explícitamente opinar sobre si la meta es alcanzable o decir frases como "vas bien" o "tienes que apretar": solo describe las opciones y sus importes, nunca el desempeño del usuario.

## Docker

- **Ningún secreto en la imagen.** `.dockerignore` excluye explícitamente `android/app/google-services.json` y `app_check_debug_token.txt`, además de `.git`, `firestore-tests/`, `test/` y los directorios de build/caché: nada de eso llega al contexto de `docker build`, así que no puede acabar en una capa de la imagen. Los dos `ARG` de IA (`ENABLE_AI`, `RECAPTCHA_SITE_KEY`) son cadenas vacías por defecto en el `Dockerfile` y en `docker-compose.yml`; un valor real solo se pasa en el comando de quien construye la imagen (`--build-arg`), nunca se escribe en el repositorio.
- **Pensada para ejecutarse sin IA.** La clave de reCAPTCHA Enterprise que protege App Check en producción solo admite los dominios registrados para ella (normalmente los de Firebase Hosting); servir la imagen en `localhost` u otro dominio con `ENABLE_AI=true` no pasaría App Check, aunque la interfaz de IA se mostrara. El despliegue real sigue siendo Firebase Hosting (ver README.md, "Ejecución con Docker").
- **Cabeceras, sin romper los flujos de Firebase.** `docker/nginx.conf` añade `X-Content-Type-Options`, `Referrer-Policy` y `X-Frame-Options`, pero no `Cross-Origin-Opener-Policy` ni `Cross-Origin-Embedder-Policy` (las dos rompen el popup de Google Sign-In, que depende de comunicación entre ventanas de distinto origen) ni ninguna `Content-Security-Policy` (sin probarla a fondo contra todos los orígenes de Google que usa la app, rompería algo en silencio; detalle de qué orígenes harían falta en docs/design.md, "Docker").
- **Verificación real de lo que entra en la imagen.** Las dos imágenes base (`debian:bookworm-20261005-slim`, `nginxinc/nginx-unprivileged:1.30.5-alpine`) y el `sha256` del SDK de Flutter que se descarga dentro del build se comprobaron de verdad (`docker pull`, y el manifiesto oficial de Google), no se dieron por buenos sin mirar — detalle completo en docs/design.md, "Docker".

## Pendiente

- **Pendiente de decisión antes de la entrega (26/10):** registro con email y contraseña. Opciones:
  1. Dejarlo abierto y documentarlo como límite conocido (ya descrito arriba).
  2. Cerrar el alta en la consola de Firebase (desactivar el proveedor de email/contraseña para nuevos usuarios o deshabilitar el registro), comprobando antes que el inicio de sesión sigue funcionando.
- Tests automatizados de las reglas (ahora se verifican manualmente contra el emulador).
- Revisión de dependencias antes de la entrega.
- Exigir correo verificado en las reglas de Firestore.
- **App Check en producción para Android.** Resuelto para web (reCAPTCHA Enterprise / Fraud Defense, ver "App Check" más arriba). Para Android sigue pendiente: mientras no se configure, un release de Android no activa App Check y oculta la IA (`chooseAppCheckConfig`, ver "Android" más arriba), en vez de intentarlo y fallar. Para activarla de verdad haría falta registrar la huella SHA-256 de la build de release en Firebase Console, vincular la app en Play Console para que `AndroidPlayIntegrityProvider` funcione, y que `chooseAppCheckConfig` deje de ocultar la IA en release Android.