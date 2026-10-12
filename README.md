# accounting-saver

[![CI](https://github.com/KillerGon01/accounting-saver/actions/workflows/ci.yml/badge.svg)](https://github.com/KillerGon01/accounting-saver/actions/workflows/ci.yml)

Asistente financiero personal con IA (Gemini), hecho con Flutter y Firebase. Trabajo final del Máster de Desarrollo con IA (Big School).

**Demo desplegada:** <https://accounting-saver.web.app/>

## Índice

1. [Descripción y objetivo](#descripción-y-objetivo)
2. [Funcionalidades](#funcionalidades)
3. [Stack y arquitectura](#stack-y-arquitectura)
4. [Uso de la IA y garantías](#uso-de-la-ia-y-garantías)
5. [Límites conocidos de la IA (nivel gratuito)](#límites-conocidos-de-la-ia-nivel-gratuito)
6. [Seguridad](#seguridad)
7. [Instalación y ejecución](#instalación-y-ejecución)
8. [Ejecución con Docker](#ejecución-con-docker)
9. [Integración continua](#integración-continua)
10. [Pruebas](#pruebas)
11. [Estructura del repositorio](#estructura-del-repositorio)
12. [Credenciales de prueba](#credenciales-de-prueba)
13. [Convención de commits y ramas](#convención-de-commits-y-ramas)
14. [Limitaciones conocidas y mejoras futuras](#limitaciones-conocidas-y-mejoras-futuras)
15. [Licencia](#licencia)

## Descripción y objetivo

Un asistente financiero personal que permite registrar movimientos (de forma manual o en lenguaje natural), consultar un resumen mensual y preguntar sobre los propios datos mediante un chat, todo sin coste económico (plan Spark de Firebase, Gemini en su nivel gratuito).

## Funcionalidades

- **Autenticación**: registro e inicio de sesión con correo y contraseña (con verificación de correo obligatoria antes de usar la app) e inicio de sesión con Google.
- **Movimientos**: alta, edición y borrado (con confirmación), listado mensual con navegación entre meses y resumen de ingresos/gastos/balance del mes.
- **Entrada en lenguaje natural**: describes un movimiento en una frase ("comí por 12 euros ayer") y la IA propone importe, fecha, concepto y categoría; la propuesta se muestra en el formulario de alta para confirmar o editar antes de guardar — nunca se guarda nada sin esa confirmación.
- **Chat financiero de solo lectura**: preguntas sobre tus propios movimientos ("¿cuánto gasté en octubre?", "¿en qué categoría gasto más?", "¿he gastado más que el mes pasado?", "¿qué gastos recurrentes tengo?") resueltas con *function calling* sobre Firestore.
- **Resumen mensual**: informe calculado en código (ingresos, gastos, balance, gasto por categoría con gráfico de barras, comparación con el mes anterior) y, aparte, un comentario opcional de la IA sobre ese mismo informe.
- **Perfil y borrado de cuenta**: datos de la cuenta, resumen de actividad (movimientos totales, por origen, ingresos/gastos acumulados) y eliminación completa de la cuenta y sus datos, con confirmación escribiendo el correo.
- **Datos de ejemplo**: carga un conjunto de movimientos ficticios de los últimos 3 meses para probar la app sin introducir datos a mano.

Detalle completo de requisitos y decisiones en `docs/analysis.md`.

## Stack y arquitectura

- **Flutter** (web prioritaria, Android también objetivo) con **Riverpod** para estado y providers.
- **Firebase**: Auth (email/contraseña y Google), Firestore (datos del usuario), Hosting (despliegue de la web), AI Logic (Gemini) y App Check.
- **Clean Architecture**, cuatro capas, dependencias siempre hacia el dominio:

```
lib/
  domain/            Dart puro: entidades, interfaces de repositorio, reglas (sin Flutter ni Firebase)
  application/       Casos de uso que orquestan el dominio
  infrastructure/    Implementaciones: Firestore, Firebase Auth, Gemini
  presentation/      Widgets y providers de Riverpod
```

- **Dinero en céntimos** (`int`), nunca `double`, en todo el proyecto (parseo, validación, cálculo y Firestore). Límite de 1.000.000 € en valor absoluto.
- **Categorías fijas en código** (enum `Category`: `supermercado`, `restaurantes`, `transporte`, `suscripciones`, `ocio`, `salud`, `hogar`, `nomina`, `otros`), repetidas en `firestore.rules` para validarlas también en el servidor.
- Gemini vive siempre detrás de una interfaz (`LlmGateway`, `ChatGateway`, `MonthlyReportGateway`), nunca se llama directamente desde la aplicación o la presentación, para poder sustituirlo por un fake en los tests.

Detalle completo (modelo de datos, decisiones de diseño por pantalla, formato de importes, tema visual...) en `docs/design.md`.

## Uso de la IA y garantías

Tres usos de Gemini, cada uno detrás de su propio puerto de dominio con su implementación en `lib/infrastructure/`:

| Puerto (dominio) | Implementación | Para qué |
|---|---|---|
| `LlmGateway` | `GeminiLlmGateway` | Entrada en lenguaje natural → `RawParsedTransaction` |
| `ChatGateway` | `GeminiChatGateway` | Chat con *function calling* |
| `MonthlyReportGateway` | `GeminiMonthlyReportGateway` | Comentario del resumen mensual |

Garantías, todas verificables en el código y en los tests:

- **La salida del modelo se valida siempre.** La entrada en lenguaje natural usa un `responseSchema` (JSON estructurado, no texto libre) y, aun así, se vuelve a validar al convertirla a dominio (importe, categoría existente, fecha razonable); si el texto no tiene un importe claro, se rechaza antes de llegar a la pantalla de confirmación.
- **Todo cálculo se hace en código; el modelo solo redacta lo que ya viene calculado.** Las funciones del chat que suman o comparan importes (`getMonthlySummary`, `getCategoryBreakdown`, `compareMonths`, `recurringExpenses`) no dejan ningún cálculo en manos de Gemini: usan el mismo caso de uso que calcula el resumen mensual (`BuildMonthlyReport`) y una función pura de comparación (`compareCategoryBreakdowns`).
- **Líneas de texto ya redactadas, listas para copiar.** `getCategoryBreakdown` y `compareMonths` devuelven, además de los datos estructurados, el ranking y la comparación ya escritos en texto plano (`rankingLines`, `comparisonLines`, `categoryComparisonLines`, por ejemplo `"1. Hogar: 938,90 € (62,2 %)"`); la instrucción de sistema le exige al modelo copiarlos tal cual, sin reescribirlos ni recalcularlos.
- **Los resultados de las funciones son datos, no instrucciones ni verdades absolutas.** El campo `description` de cada movimiento se trata como texto a mostrar, nunca como una orden a seguir; los argumentos que pide el modelo (año, mes, fechas, categoría) se validan antes de tocar Firestore, y si algo no es válido no se ejecuta ninguna consulta.
- **El comentario del resumen mensual solo ve agregados.** `buildMonthlyReportExplanationPrompt` recibe un `MonthlyReport` (totales, gasto por categoría, comparación) que no tiene ningún campo para una descripción de movimiento individual: no es un filtrado que pueda fallar, es que el dato nunca llega a esa función.
- **El chat es de solo lectura.** Las funciones que puede pedir el modelo (`getMonthlySummary`, `getCategoryBreakdown`, `compareMonths`, `listTransactions`, `recurringExpenses`) solo leen Firestore; no existe ninguna función de escritura expuesta al modelo.
- **Aislamiento por usuario.** La caché de respuestas, el contador de preguntas/comentarios por sesión y el historial del chat están aislados por `userId` (`Provider.family`), para que cerrar sesión y entrar con otra cuenta en la misma app no herede nada del usuario anterior.
- **Sin conversaciones guardadas.** El historial del chat y el comentario del resumen viven solo en el estado de la pantalla, en memoria; no se escriben en Firestore ni se registran en ningún log.

Detalle completo (incluido el hallazgo de que el chat llegó a dar cifras distintas al resumen antes de este diseño) en `docs/design.md`.

## Límites conocidos de la IA (nivel gratuito)

- **Modelos**: `geminiModelFallbacks` (`lib/infrastructure/common/gemini_model_fallback.dart`) es la única lista a editar, en este orden: **`gemini-3.5-flash-lite`** (principal) con respaldo en **`gemini-3.8-flash`**. Si el primero devuelve cuota agotada o un modelo ya no disponible, se pasa automáticamente al siguiente. Los `gemini-2.5-*` que estaban antes en esta lista se retiraron porque ya no están disponibles para proyectos nuevos.
- **Cupos y latencia observados el 11/10/2026** (una foto de un día concreto, no una garantía de Google — pueden cambiar sin aviso). Los cupos son del proyecto entero, compartidos por todos los usuarios de la app, no por usuario:

  | Modelo | Cupo gratuito observado | Latencia observada (una pregunta) |
  |---|---|---|
  | `gemini-3.5-flash-lite` | 15 peticiones/min, 500/día | entre menos de 7 s y ~20 s según el momento del día (medido el 11/10/2026) |
  | `gemini-3.8-flash` | 5 peticiones/min, 20/día | de varios minutos ese día |

  **La latencia varía de un día a otro**: el 10/10/2026, con `gemini-3.8-flash`, se observaron respuestas válidas en 84 s y en 108 s, muy por encima de lo habitual; de ahí que el timeout esté fijado en 150 s y no en un valor menor.
- **Tope de preguntas y comentarios por sesión**: `SendChatMessage.maxQuestionsPerSession` = 20 preguntas del chat; `ExplainMonthlyReport.maxCommentsPerSession` = 6 comentarios del resumen mensual. Solo cuenta una llamada que termina con éxito (ni una respuesta cacheada ni un error gastan cupo).
- **Caché en memoria**: la última respuesta a cada pregunta (normalizada) y el último comentario por mes se cachean mientras los movimientos no cambien, para no repetir una llamada a Gemini si se repite la misma pregunta o se reabre el mismo mes.
- **Timeout**: 150 segundos por petición a Gemini, sin reintento (un timeout no garantiza que la petición original haya fallado en el servidor). Ante un error transitorio del servidor (503), sí hay un reintento único con el mismo modelo.
- **El nivel gratuito de Gemini permite a Google usar el contenido enviado para mejorar sus productos.** Por eso la demo pública solo debe usarse con los datos de ejemplo (ficticios) que carga la propia app, nunca con datos reales.

Detalle completo (incluida la investigación del 404 "modelo retirado" y por qué se detecta por texto, no por código de estado) en `docs/design.md`.

## Seguridad

- **Reglas de Firestore con correo verificado.** Cada usuario solo puede leer, crear, editar y borrar sus propios movimientos, y solo si su correo está verificado (`request.auth.token.email_verified == true`), comprobado también en el servidor, no solo en la interfaz. Los campos, tipos y valores de cada movimiento se validan igualmente en las reglas (`firestore.rules`).
- **App Check con reCAPTCHA Enterprise (Fraud Defense)** en producción web, obligatorio para llamar a Gemini desde noviembre de 2026. En desarrollo se usa el proveedor de depuración. App Check está aplicado (*enforced*) en Firebase AI Logic desde el 11/10/2026; **no** está aplicado en Firestore, cuya protección son las reglas descritas arriba.
- **Las claves de cliente de Firebase son públicas por diseño.** `lib/firebase_options.dart` (configuración de cliente) y la clave de sitio de reCAPTCHA no son secretos que haya que ocultar: la protección de los datos viene de las reglas de Firestore, Auth y App Check, no de esconder esas claves. La clave de reCAPTCHA Enterprise, además, solo admite los dominios que se le hayan registrado explícitamente (normalmente los de Firebase Hosting) — en eso consiste su restricción por sitio web. La clave de navegador de Firebase está igualmente restringida en Google Cloud, por sitios web (solo los dominios de Hosting y `localhost:5000`/`localhost:8080`) y por API (lista por defecto de Firebase, 25 APIs); la clave de API de Android, por nombre de paquete y por la huella SHA-1 de la clave de firma. Detalle completo en `docs/security.md`.
- **Escaneo de secretos con gitleaks.** Escaneo manual con Docker sobre todo el historial, ejecutado el 11/10/2026, sin hallazgos aparte de las dos claves de cliente aceptadas (`.gitleaksignore`, ver arriba); no está en el CI.

  ```bash
  docker run --rm -v "$PWD:/repo" ghcr.io/gitleaks/gitleaks:latest detect --source /repo -v
  ```
- **Coste cero.** Plan Spark de Firebase (sin Cloud Functions, sin facturación) y Gemini en su nivel gratuito a través de Firebase AI Logic.

Detalle completo (reautenticación y borrado de cuenta, detección de errores de Gemini y de App Check por texto, límites conocidos, pendientes) en `docs/security.md`.

## Instalación y ejecución

**Requisitos**: Flutter 3.47.6 (canal `stable`, la misma versión que usa el CI), y un proyecto de Firebase si quieres apuntar al tuyo propio en vez de usar la configuración ya incluida.

**Clonado:**

```bash
git clone https://github.com/KillerGon01/accounting-saver
cd accounting-saver
flutter pub get
```

`lib/firebase_options.dart` ya está en el repositorio (es la configuración pública de cliente de Firebase, no un secreto) y apunta al proyecto `accounting-saver`, así que no hace falta ejecutar `flutterfire configure` para ejecutar la app contra ese proyecto. Usar un proyecto de Firebase propio exige ejecutar `flutterfire configure` para regenerar ese archivo, y además habilitar en ese proyecto Auth (correo/contraseña y Google), Firestore (con `firestore.rules`), Hosting, AI Logic y App Check, y registrar tu propia clave de reCAPTCHA; no está soportado como vía de corrección de este trabajo.

**En web, el puerto 5000 es obligatorio, no una recomendación, con o sin IA.** La clave de cliente de Firebase está restringida en Google Cloud a una lista cerrada de orígenes, y en local solo admite `http://localhost:5000` (con Docker, el puerto es el 8080, ver "Ejecución con Docker" más abajo); con cualquier otro puerto, la petición a Firebase (Auth, Firestore, o Gemini si `ENABLE_AI` está activo) se rechaza antes de llegar al servidor y nada funciona, ni siquiera iniciar sesión. Detalle completo en `docs/security.md`.

**Ejecución en local, sin IA** (por defecto; no requiere configurar Firebase AI Logic ni App Check):

```bash
flutter run -d chrome --web-port=5000
```

**Ejecución en local, con IA activada** (entrada en lenguaje natural y chat):

```bash
flutter run --dart-define=ENABLE_AI=true -d chrome --web-port=5000
```

Usa además siempre el mismo navegador: el token de depuración de App Check se genera y se guarda en su almacenamiento local, así que cambiar de navegador exige registrar un token nuevo. App Check se activa con el proveedor de depuración; el primer arranque imprime un token en la consola del navegador o en el log de Android que hay que registrar en *Firebase Console → App Check → Manage debug tokens*.

**Solo quien administra el proyecto de Firebase puede registrar ese token de depuración**: ese registro se hace en la consola de Firebase del proyecto, con permisos de administrador. Para cualquier otra persona, la IA en local no va a funcionar; para probarla, usa la web desplegada (<https://accounting-saver.web.app/>), que ya tiene App Check de producción configurado. Sin IA, todo lo demás (movimientos, resumen mensual, perfil, datos de ejemplo) funciona en local sin ninguna restricción de este tipo (ver `docs/security.md`).

**Build de producción para web:**

```bash
flutter build web --release \
  --dart-define=ENABLE_AI=true \
  --dart-define=RECAPTCHA_SITE_KEY=<clave-de-sitio-de-reCAPTCHA-Enterprise>
```

Sin el segundo `--dart-define` (o vacío), la build compila igual pero la IA queda oculta automáticamente, igual que con `ENABLE_AI=false`.

**Despliegue** (Firebase Hosting, el despliegue oficial de la app):

```bash
firebase deploy --only hosting
```

**Tests de las reglas de Firestore contra el emulador** (`firestore-tests/`, carpeta aparte, con su propio `package.json`; requiere Node, npm, Java y el CLI de `firebase` instalados):

```bash
cd firestore-tests
npm install
npm run test:emulator
```

## Ejecución con Docker

```bash
docker compose up --build
```

Sirve la app en `http://localhost:8080`. Para bajarlo: `docker compose down`. También se puede construir y ejecutar directamente:

```bash
docker build -t accounting-saver-web .
docker run --rm -p 8080:8080 accounting-saver-web
```

**Esta imagen está pensada para ejecutarse sin IA.** La clave de sitio de reCAPTCHA Enterprise que protege App Check en producción solo admite los dominios registrados para ella — normalmente los de Firebase Hosting. Si se construye la imagen con `ENABLE_AI=true` y esa clave, y se sirve en `http://localhost:8080` (o cualquier otro dominio no registrado), App Check rechazará el token y la IA no funcionará, aunque la interfaz se muestre. El despliegue oficial sigue siendo Firebase Hosting; Docker es una forma reproducible de servir el mismo `build/web` en cualquier otro sitio, sin la IA.

Detalle completo (por qué no se usa una imagen de Docker con Flutter ya hecha, verificación de checksums, configuración de nginx) en `docs/design.md`.

## Integración continua

`.github/workflows/ci.yml`, en cada pull request hacia `main` y en cada push a `main`, con Flutter 3.47.6 fijado y sin ningún secreto:

- **`analyze_and_test`**: `flutter analyze` (falla con cualquier aviso) y `flutter test`.
- **`build_web`**: `flutter build web --release`, sin ningún `--dart-define` de IA (comprueba solo que la web compila).

Los dos jobs ejecutan sin `continue-on-error` (confirmado en el YAML), así que un fallo en cualquiera de los dos marca la ejecución del workflow como fallida. `main` está protegido por un *ruleset* (PR obligatoria y checks `analyze_and_test` y `build_web`); en repositorios públicos se aplica sin coste, en privados requiere un plan de pago, así que entra en vigor al hacer público el repositorio.

## Pruebas

384 tests (`flutter test`), cubriendo dominio, aplicación y presentación con fakes (sin mocks): parseo e importe de movimientos, casos de uso de alta/edición/borrado, datos de ejemplo, autenticación y verificación de correo, perfil y borrado de cuenta, entrada en lenguaje natural (validación del esquema, contraste determinista de que el texto mencione un número, casos de error), chat (validación de argumentos de cada función, desglose por categoría y comparación de meses consistentes con el resumen mensual, aislamiento por usuario), fallback y reintento de Gemini (cuota agotada, modelo no encontrado, timeouts, 503 transitorio), mensajes de error traducidos a español sin filtrar texto interno, el resumen mensual con su gráfico y su comentario de IA, y la lógica (generación de casos y criterio de acierto) de la evaluación del chat contra Gemini real (`test/eval/`, ver docs/evaluation.md).

```bash
flutter analyze
flutter test
```

Detalle completo, archivo por archivo, en `docs/testing.md`. Aparte, `firestore-tests/` (Node, no `flutter test`) prueba `firestore.rules` contra el emulador real — ver `docs/security.md`.

### Evaluación de calidad del chat contra Gemini real

`lib/eval_main.dart` es una **herramienta de evaluación local, para documentar el TFM — no es parte de la app**: no se publica, no se incluye en el Dockerfile ni en ningún build de producción, y no la ejecuta ni `flutter test` ni el CI (los dos solo conocen `lib/main.dart`). Hace ~30 preguntas al gateway de Gemini y al ejecutor de funciones del chat reales (sin pasar por la pantalla de chat) contra una cuenta de evaluación dedicada (nunca la de "Credenciales de prueba"), con importes esperados calculados en código, nunca a mano. Metodología, criterio de acierto y cómo ejecutarla en `docs/evaluation.md`.

## Estructura del repositorio

```
lib/
  domain/            Entidades, interfaces de repositorio/gateway y reglas puras (auth, chat, reports, transactions, user_data, common)
  application/       Casos de uso (auth, chat, reports, transactions)
  infrastructure/    Firestore, Firebase Auth, Gemini (auth, chat, reports, transactions, user_data, common)
  presentation/      Pantallas y providers de Riverpod (auth, chat, profile, reports, theme, transactions, common)
  eval/              Evaluación de calidad del chat contra Gemini real (ver docs/evaluation.md)
  eval_main.dart     Punto de entrada de esa evaluación; local, no se despliega (ver arriba)
test/                Tests unitarios y de widgets, con fakes en test/fakes/ (incluye test/eval/)
firestore-tests/     Tests de firestore.rules contra el emulador (Node, independiente del proyecto Flutter)
docs/                analysis.md, design.md, testing.md, security.md, evaluation.md
docker/              Configuración de nginx para la imagen de Docker
.github/workflows/   Integración continua (ci.yml)
firestore.rules       Reglas de seguridad de Firestore
firebase.json          Configuración de Firebase (Firestore, Hosting)
Dockerfile, docker-compose.yml   Imagen para servir la web sin IA
```

## Credenciales de prueba

Cuenta de prueba para la corrección, con datos ficticios (cargados con la opción de datos de ejemplo de la propia app):

- Usuario: `[COMPLETAR: usuario]`
- Contraseña: `[COMPLETAR: contraseña]`

## Convención de commits y ramas

- Commits: `[ADDED|CHANGED|REMOVED] Resumen corto`, en inglés.
- Una rama por funcionalidad (`feature/...`), con *pull request* hacia `main`. No se commitea directamente en `main`.

## Limitaciones conocidas y mejoras futuras

- **Android funciona en modo debug, no en release.** Probado en un móvil físico el 11/10/2026: inicio de sesión con correo y con Google, movimientos, resumen mensual, entrada en lenguaje natural y chat, todo con el token de depuración de App Check registrado por el administrador del proyecto. En una build de **release** no hay ningún proveedor de App Check de producción configurado (Play Integrity exige vincular la app en Play Console), así que el APK de release se entrega sin IA: queda oculta automáticamente (`chooseAppCheckConfig` en `lib/app_check_config.dart`), igual que si `ENABLE_AI` fuera `false`, en vez de mostrarla y dejarla fallar. El nombre de paquete sigue siendo el que pone Flutter por defecto (`com.example.accounting_saver`), pendiente de renombrar antes de publicar. Detalle completo en `docs/security.md` → "Android" y `docs/design.md` → "Android".

  El APK de depuración con la IA activada se genera con:

  ```bash
  flutter build apk --debug --dart-define=ENABLE_AI=true
  ```

  La IA solo funciona en el móvil donde está registrado el token de depuración de App Check de esa instalación (ver "Seguridad" más arriba); este APK no se distribuye.
- **Detección de errores de Gemini y de App Check por texto, no por código de estado.** El paquete `firebase_ai` no expone el código HTTP ni el `status` del error como un campo propio para un modelo no encontrado, un 503 transitorio o un 403 de App Check; se reconocen buscando frases concretas en el mensaje de la excepción. Si Google cambia ese texto, la detección deja de funcionar silenciosamente (el fallo pasaría a tratarse como un error genérico, sin reintento, pero sin romper nada más ni filtrar información interna).
- **Registro abierto.** La aplicación permite crear cuentas por correo y contraseña sin ninguna restricción adicional; pendiente de decidir si se deja así (documentado como límite conocido) o se cierra desde la consola de Firebase.
- **`thinkingConfig` de Gemini sin confirmar** para los modelos de respaldo del fallback: existe en el paquete, pero no se ha podido probar contra el backend real en este entorno.
- Localización completa de Material (`flutter_localizations`) pendiente.
- CI opcional para `firestore-tests/` (hoy se ejecuta a mano contra el emulador, no en GitHub Actions).

Detalle completo de cada límite y de las decisiones ya tomadas en `docs/security.md` y `docs/design.md`.

## Licencia

MIT. Ver [`LICENSE`](LICENSE).
