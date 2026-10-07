# Diseño

## Arquitectura

Clean Architecture con cuatro capas. Las dependencias apuntan hacia el dominio.

```
lib/
  domain/            Dart puro: entidades, interfaces de repositorio, reglas (sin Flutter ni Firebase)
  application/       Casos de uso que orquestan el dominio
  infrastructure/    Implementaciones: Firestore, Firebase Auth, Gemini
  presentation/      Widgets y providers de Riverpod
```

Gemini vive siempre detrás de la interfaz `LlmGateway`, para poder sustituirlo en tests con un fake.

## Modelo de datos

Colección `users/{uid}/transactions/{id}`:

| Campo | Tipo | Notas |
|---|---|---|
| `amountCents` | int | Negativo = gasto. Nunca cero. |
| `date` | Timestamp | Día del movimiento (12:00 en datos demo). |
| `description` | string | 1 a 200 caracteres. |
| `categoryId` | string | Nombre del enum `Category`. |
| `source` | string | `manual`, `naturalLanguage` o `demo`. |
| `createdAt` | Timestamp | Fecha de alta. |

Las categorías son fijas y viven en código (`Category`).

## Decisiones clave

**Importes en céntimos.** `parseEurosToCents` convierte la cadena introducida (coma o punto decimal, hasta dos decimales) a `int` sin pasar por `double`. Límite de 1.000.000 € en valor absoluto (`maxAbsoluteAmountCents`, definido una sola vez en el dominio y usado por el parser, por `Transaction` y por las reglas).

**Resumen en dominio.** `MonthlySummary` vive en `lib/domain/transactions/monthly_summary.dart`. `MonthlySummary.fromTransactions` recorre la lista del mes y separa ingresos y gastos en céntimos; el gasto se guarda como magnitud positiva. La pantalla usa el mismo stream que el listado, así que solo hay un listener de Firestore por mes.

**Filtrado por mes en Firestore.** El rango `[inicio de mes, inicio del mes siguiente)` se consulta con `where` sobre `date` y `orderBy` descendente. Requiere índice simple sobre `date`, que Firestore crea automáticamente.

**ID generado por el repositorio.** `TransactionRepository.newId` usa el ID automático de Firestore, así el dominio no conoce Firebase y no hace falta un paquete de UUID.

**Datos demo con comprobación previa.** `LoadDemoData` consulta `source == demo` (limit 1) antes de escribir. Las escrituras se hacen en un `WriteBatch`. La UI deshabilita el botón mientras carga.

**Datos demo recurrentes.** Netflix, Spotify, Gimnasio y el alquiler caen en el mismo día y con el mismo importe cada mes, para poder detectar gastos recurrentes más adelante. Nómina en día 1 o 28. El resto se reparte al azar con semilla fija, así los datos son reproducibles.

**Formato propio, sin `intl`.** Decisión: los importes (`1.234,56 €`), fechas (`dd/MM/yyyy`) y nombres de mes en español se formatean en `lib/presentation/transactions/formatters.dart`. Motivo: `intl` añadiría una dependencia para cuatro formatos fijos, y el proyecto evita dependencias innecesarias. Si más adelante hace falta localizar la app, se revisará esta decisión.

## Tema visual

Todo el tema vive en `lib/presentation/theme/app_theme.dart`:

- `AppTheme.light()` y `AppTheme.dark()` generan un `ThemeData` Material 3 a partir de `ColorScheme.fromSeed` con la semilla `#00695C`. `main.dart` usa `themeMode: ThemeMode.system`, así que el modo lo decide el sistema.
- `AppSpacing` define los espaciados (4, 8, 16, 24 y 32 px) que usan las pantallas.
- Los ajustes de componentes (AppBar sin elevación, tarjetas sin sombra con esquinas de 16 px, campos con borde redondeado) se definen una sola vez en el tema.
- `FinanceColors` es una `ThemeExtension` con los colores de ingreso y de gasto. El de gasto es `colorScheme.error`; el de ingreso tiene un tono distinto en modo claro y en modo oscuro. Las pantallas lo leen con `Theme.of(context).extension<FinanceColors>()`, así que no hay colores de ingreso o gasto fijados en los widgets.

## Estilo por categoría

`lib/presentation/transactions/category_style.dart` añade a `Category` un icono (`icon`) y un color (`color`) mediante una extensión. Vive en presentación porque es una decisión visual: el dominio no conoce iconos ni colores. El mismo icono y color se usan en el avatar de cada movimiento y en el desplegable del formulario.

## Interfaz

- Columna única, con el listado limitado a 720 px de ancho y el formulario a 560 px, centrados en pantallas grandes. No hay un punto de corte explícito para móvil: el contenido se adapta por el ancho máximo.
- Cabecera de la pantalla: navegación entre meses y, debajo, una tarjeta de resumen con el balance del mes en grande y los ingresos y gastos debajo.
- Lista agrupada por día (`groupByDay` en `day_groups.dart`), con una cabecera de fecha por grupo (por ejemplo, `Lunes, 5 de octubre`). Cada fila muestra el icono de la categoría, la descripción, la categoría, el importe alineado a la derecha y el botón de borrado. `groupByDay` asume la lista ya ordenada por fecha descendente, que es lo que devuelve el stream.
- Estado vacío con icono, explicación y botón de datos de ejemplo.
- Acciones de la barra superior, todas con tooltip: cargar datos de ejemplo y cerrar sesión. Botón flotante para añadir.
- Tocar un movimiento abre el formulario de edición; el icono de papelera pide confirmación.
- Acceso al perfil con un icono de cuenta en la barra superior. El perfil se abre como ruta nueva y, al cerrar sesión o borrar la cuenta, se vuelve a la raíz con `popUntil`.

## Perfil y eliminación de cuenta

**Capas.** `AppUser` (dominio) guarda lo que dice Firebase: proveedores, verificación y fechas de creación y último acceso. `UserProfile` (dominio) lo traduce a un proveedor `SignInProvider` que la presentación puede mostrar sin conocer los identificadores de Firebase (`password`, `google.com`). `ActivitySummary` (dominio) es el resumen; `ActivitySummary.fromTransactions` lo calcula en memoria y lo usa el fake, mientras que Firestore lo calcula con agregados.

**Resumen con agregados.** `FirestoreTransactionRepository.getActivitySummary` hace:

| Dato | Consulta |
|---|---|
| Total | `count()` |
| Demo, manual, lenguaje natural | `where('source', ==)` + `count()` |
| Ingresos y gastos | `where('amountCents', > 0)` y `< 0` + `aggregate(sum('amountCents'))` |
| Primer y último movimiento | `orderBy('date')` y `orderBy('date', desc)` con `limit(1)` |

Todas son consultas de un único campo, así que no necesitan índices compuestos. `getSum` devuelve `double`; como los importes son enteros de céntimos, el redondeo recupera el valor exacto mientras la suma sea menor que 2^53 céntimos. La versión de `cloud_firestore` que usa el proyecto soporta estas agregaciones, así que no se añade ningún paquete.

**Dónde se borran los datos.** La especificación pedía `deleteAllForUser` en `TransactionRepository`. Se ha puesto en un puerto propio, `UserDataRepository`, por una razón: la lista de colecciones que se borran tiene que estar en un solo sitio, y con un método por repositorio esa lista quedaría repartida. `FirestoreUserDataRepository` recorre `userDataCollections`, y el comentario de esa constante exige añadir ahí cualquier colección nueva con datos del usuario.

**Orden y fallos.** `DeleteAccount` (aplicación) hace, en este orden: reautenticar, borrar datos, borrar la cuenta. Un fallo en el primer paso no toca nada. Un fallo en los dos siguientes lanza `AccountDeletionException` con la etapa (`userData` o `account`), para que la pantalla explique qué ha quedado hecho. Reintentar es seguro porque el borrado de datos es idempotente: vuelve a leer lo que queda.

**Reautenticación.** Correo y contraseña usa `reauthenticateWithCredential`. Google usa `reauthenticateWithPopup` en web y `reauthenticateWithProvider` en móvil, igual que el inicio de sesión. `FirebaseAuth` exige una reautenticación reciente para `user.delete()`, así que el borrado siempre se precede de ella.

**Confirmación.** El diálogo compara el texto con el correo sin recortar ni normalizar, y con correo y contraseña exige además una contraseña no vacía. El botón solo se habilita si se cumplen las dos condiciones.

## Entrada en lenguaje natural

**Dos tipos para dos momentos.** `RawParsedTransaction` (dominio) es lo que devuelve `LlmGateway.extractTransaction`: el importe, la fecha, el concepto y la categoría *como texto*, sin validar. `ParsedTransaction` es la propuesta ya validada (mismas reglas que `Transaction`: importe distinto de cero y dentro de `maxAbsoluteAmountCents`, concepto de 1 a 200 caracteres) con la categoría resuelta al enum `Category`. Separar los dos tipos evita que una categoría inventada por el modelo ("otros_gastos", por ejemplo) se confunda con un valor real del enum, y deja claro en qué punto se hace cada validación.

**El caso de uso no guarda nada.** `ParseNaturalLanguageTransaction` llama al gateway, convierte el nombre de categoría con `categoryFromName` (en `category.dart`) y comprueba que la fecha es razonable (no más de un día en el futuro, para absorber un desajuste de zona horaria, ni más de 5 años en el pasado) antes de construir el `ParsedTransaction`. Si la categoría no existe o la fecha no es razonable, lanza `ArgumentError`, igual que hace `Transaction` con sus propias validaciones. Guardar el movimiento sigue siendo responsabilidad exclusiva de `AddTransaction`, llamado desde el formulario tras confirmar.

**Gemini Developer API, no Vertex AI.** `GeminiLlmGateway` usa `FirebaseAI.googleAI()` (backend Gemini Developer API) en vez de `FirebaseAI.vertexAI()`, porque el primero tiene un nivel de uso gratuito sin necesidad de vincular una cuenta de facturación; Vertex AI exige el plan Blaze. El modelo exacto vive en una única constante, `geminiModelName` (`lib/infrastructure/transactions/gemini_llm_gateway.dart`), comprobada contra la documentación oficial de modelos de Firebase AI Logic.

**Salida estructurada, no texto libre.** El `GenerativeModel` se configura con `responseMimeType: 'application/json'` y un `responseSchema` (`Schema.object`) con los cuatro campos esperados; la categoría usa `Schema.enumString` con los nombres del enum `Category`, para que el modelo elija entre los valores válidos en vez de inventar uno. Aun así, la respuesta se vuelve a validar al convertirla a dominio, porque un esquema no garantiza que el modelo lo respete al cien por cien.

**Se probó y se descartó bajar el nivel de "pensamiento".** `gemini-3.8-flash` piensa en nivel `medium` por defecto. Se probó `thinkingConfig: ThinkingConfig.withThinkingLevel(ThinkingLevel.low)` (`minimal` no está soportado en este modelo —la API responde `400 INVALID_ARGUMENT`— solo existe en `gemini-3.6-flash` y `gemini-3.5-flash-lite`) para reducir la latencia de 15-20 s. Se revirtió por dos motivos, comprobados al probarlo: no se notó ninguna mejora de velocidad (el cuello de botella no es el razonamiento, sino el propio viaje de ida y vuelta a Gemini), y sí empeoró la corrección — con `low` llegó a interpretar "un 2% de 1000" como un importe de 2, no de 20. La documentación de Gemini ya avisa de esto: pide el nivel por defecto o superior para tareas con cálculo. Se mantiene el nivel por defecto, sin fijar `thinkingConfig`.

**El prompt resuelve los cálculos, no solo los extrae.** Como la frase puede describir un cálculo en vez de dar el importe final ("un 2% de la nómina de 1000"), el prompt pide explícitamente al modelo que resuelva la cuenta antes de devolver el importe, con un ejemplo numérico. Esto ayuda independientemente del nivel de pensamiento, pero no lo sustituye: por eso se mantiene el nivel por defecto.

**El esquema permite decir "no entendido" en vez de obligar a inventar.** Con el esquema inicial, los cuatro campos (`amountCents`, `date`, `description`, `category`) eran obligatorios, así que un texto sin importe como `"asdf"` forzaba al modelo a rellenarlos de todas formas (devolvía 1 céntimo). Ahora el esquema tiene un campo `understood` (booleano, obligatorio) y los otros cuatro son `nullable` y opcionales; el prompt pide explícitamente que, si no hay un importe claro, se devuelva `understood: false` con el resto en `null`, y que nunca se invente un importe, un concepto o una categoría. `RawParsedTransaction` (dominio) refleja esto con campos anulables; `ParseNaturalLanguageTransaction` rechaza con `NotUnderstoodException` tanto si `understood` es `false` como si es `true` pero falta cualquier otro campo.

**Contraste determinista antes de llamar al modelo.** Ni el esquema ni el prompt son una garantía: nada impide que el modelo, aun así, se invente un importe para un texto sin ningún número. `textContainsNumber` (`lib/domain/transactions/number_detection.dart`, Dart puro, sin red) comprueba que el texto mencione alguna cifra o alguna palabra de número en español antes de llamar a Gemini. Si no la menciona, se rechaza sin gastar cuota; y aunque el gateway devolviera igualmente un importe, el resultado ya se ha descartado antes de pedírselo. Es el límite final, independiente de lo bien o mal que se comporte el modelo.

**Arranque en frío de la primera petición.** La primera llamada a Gemini de toda la sesión suele ser más lenta que las siguientes, porque suma el canje del token de App Check a la latencia propia de la primera conexión al modelo. `main.dart` adelanta la parte que no cuesta cuota: tras `activate()`, pide un token de App Check en segundo plano (`unawaited`, con el error ignorado si falla) para que ya esté en caché cuando el usuario escriba su primer texto. Esto no recorta la latencia de Gemini en sí (que es la parte que domina el tiempo total y no tiene un atajo barato sin perder corrección), solo evita sumarle el canje del token encima. No se precalienta Gemini: eso consumiría cuota gratuita en cada arranque de la app, incluso para quien no usa la IA.

**Errores de la IA, no de la app.** `GeminiLlmGateway` traduce las excepciones de `firebase_ai` (`QuotaExceeded`, cualquier otra `FirebaseAIException`, fallos de red o de parseo del JSON) a `LlmGatewayException` con un código (`quota-exceeded`, `service-error`, `network-error`, `malformed-response`) y un mensaje en español, igual que `AuthException` hace con Firebase Auth. La presentación traduce el código a texto con `llmErrorMessage` (análogo a `authErrorMessage`).

**Prellenar sin editar.** `TransactionFormScreen` acepta un `ParsedTransaction? initialDraft` además del `Transaction? transaction` que ya tenía para editar. Un borrador de IA rellena los mismos campos que una edición, pero sigue tratándose como alta nueva (`AddTransaction`, no `UpdateTransaction`) y, si se guarda sin cambiar el origen, usa `TransactionSource.naturalLanguage`.

**Activación y límites.** El campo "Añadir con lenguaje natural" solo aparece si `const bool.fromEnvironment('ENABLE_AI')` es verdadero, para no mostrar una función que requiere configuración adicional en Firebase (Firebase AI Logic habilitado) a quien no la ha activado. El texto de entrada está limitado a 300 caracteres, y nunca se registra en logs.
