# Seguridad

## Autenticación

- Email/contraseña y Google mediante `firebase_auth`.
- La pantalla principal solo se muestra con sesión iniciada (`AuthGate` en `main.dart`).
- No hay secretos en el repositorio. `google-services.json` está en `.gitignore`.

## Reglas de Firestore (`firestore.rules`)

Cada usuario solo puede leer y borrar sus propios movimientos. Crear o editar exige que el documento tenga exactamente los campos que escribe `FirestoreTransactionRepository`, con los tipos y valores válidos:

| Campo | Condición |
|---|---|
| (conjunto de campos) | Exactamente `amountCents`, `date`, `description`, `categoryId`, `source`, `createdAt`. Ni más ni menos. |
| `amountCents` | `int`, distinto de 0, entre -100.000.000 y 100.000.000 céntimos. |
| `description` | `string` de 1 a 200 caracteres. |
| `categoryId` | Uno de los nombres de `Category`. |
| `source` | Uno de los nombres de `TransactionSource`. |
| `date`, `createdAt` | `timestamp`. |

Las reglas se han comprobado a mano contra el emulador local de Firestore: el límite exacto se acepta, un céntimo por encima se rechaza, y también se rechazan cada campo inválido, los campos extra y la escritura en la cuenta de otro usuario.

## Límites conocidos

- **Registro abierto.** La aplicación tiene el caso de uso `SignUpWithEmailAndPassword`, aunque la pantalla de login no lo expone. Firebase Auth acepta altas por correo y contraseña mientras el proveedor esté habilitado, y la configuración web de Firebase es pública. Cualquiera con esa configuración podría crear cuentas en masa y consumir la cuota gratuita de Firestore. No he comprobado la configuración del proyecto en la consola de Firebase.
- **App Check solo para Gemini, no para Firestore.** Se activa únicamente cuando `ENABLE_AI` es verdadero y solo con el proveedor de depuración (ver "App Check" más abajo). Firestore sigue sin ninguna comprobación de que las peticiones provienen de la aplicación; el punto anterior (registro abierto) sigue sin resolverse.
- **Sin límite de frecuencia.** Las reglas no limitan cuántos documentos puede escribir un usuario autenticado. Sin Cloud Functions, la única protección de cuota es la que aplique Firebase.
- **Lista de valores fijos.** Las categorías y fuentes válidas están escritas en `firestore.rules`. Si se añade un valor al enum en Dart, hay que añadirlo también en las reglas.
- **La verificación de correo solo se aplica en la interfaz.** La app muestra
  `VerifyEmailScreen` a los usuarios de correo y contraseña con el correo sin
  verificar, pero Firestore no lo exige. Alguien que llame directamente a la API
  de Firebase con una cuenta no verificada podría seguir leyendo y escribiendo en
  su propio espacio. Mejora pendiente: exigir
  `request.auth.token.email_verified == true` en las reglas (la app tendría que
  refrescar el token tras verificar).

## Eliminación de cuenta

- **Reautenticación obligatoria.** Antes de borrar nada, el usuario vuelve a probar su identidad: contraseña (correo y contraseña) o popup de Google. Si falla o se cancela, no se borra ningún dato.
- **Orden.** Primero los movimientos, después la cuenta de Auth. Así, si la cuenta siguiera existiendo tras un fallo, el usuario puede volver a intentarlo; lo contrario dejaría datos huérfanos sin forma de reintentar desde la app.
- **Cobertura.** `userDataCollections` (en `firestore_user_data_repository.dart`) es la lista de colecciones que se borran. Cualquier colección nueva con datos del usuario debe añadirse ahí. Hoy solo existe `transactions`.
- **Reglas.** El borrado usa la regla `allow delete` de `users/{uid}/transactions` (solo el propio usuario). Las consultas agregadas del resumen usan la regla `allow read` de la misma colección. No hace falta ninguna regla nueva.
- **Sin Cloud Functions.** Todo el borrado lo ejecuta el cliente. Un cierre de la pestaña a mitad deja la cuenta con datos parcialmente borrados; la cuenta sigue existiendo y basta con volver a iniciar sesión y reintentar.
- **Confirmación por correo exacto.** Es una barrera contra clics accidentales, no contra un atacante con sesión iniciada, que ya puede borrar sus datos.
- **Pendiente.** El borrado de movimientos no es atómico: se hace en lotes de 400 y un lote no puede abarcar toda una colección grande. Por eso un fallo a mitad deja datos parciales, que el reintento completa. Una atomicidad total requeriría una Cloud Function que el proyecto no usa por coste.

## App Check (Firebase AI Logic)

Desde noviembre de 2026 Firebase AI Logic exige App Check para llamar a Gemini; sin él, la petición falla con un 401 ("Firebase App Check token is invalid"). El proyecto solo configura el **proveedor de depuración**, pensado para desarrollo local, nunca reCAPTCHA ni ninguna clave de producción.

**Dónde se activa.** `main.dart`, justo después de `Firebase.initializeApp()` y antes de que cualquier pantalla pueda llamar a Gemini, y solo si `enableAi` (`ENABLE_AI` en tiempo de compilación) es verdadero:

```dart
await FirebaseAppCheck.instance.activate(
  providerWeb: WebDebugProvider(),
  providerAndroid: const AndroidDebugProvider(),
);
```

Sin `ENABLE_AI`, App Check no se activa nunca; es coherente con que la interfaz de IA tampoco se muestra.

**Dónde aparece el token de depuración.**

- **Web:** en la consola del navegador (F12 → Console), como `AppCheck debug token: "xxxxxxxx-xxxx-...".`. `WebDebugProvider()` sin `debugToken` hace que el SDK de Firebase lo genere y lo guarde en el almacenamiento local del navegador; se mantiene estable en ese navegador y esa máquina mientras no se borre el almacenamiento del sitio.
- **Android:** en el log de Android (logcat / `flutter run` en la terminal), como `Enter this debug secret into the allow list in the Firebase Console: xxxxxxxx-xxxx-...`. Se genera una vez por instalación y se mantiene mientras no se desinstale la app o se borren sus datos.

**Qué hace falta en la consola de Firebase.** Copiar ese token y registrarlo en *Firebase Console → (icono de engranaje) Project settings → App Check → pestaña Apps → menú de los tres puntos de la app correspondiente (web o Android) → Manage debug tokens → Add debug token*. Hay que registrarlo por separado para la app web y para la app Android, y volver a hacerlo si alguna vez se borra el almacenamiento/los datos que lo guardan (saldría un token nuevo).

**Por qué no hay ningún token en el repositorio.** El token no lo escribe el código: se genera en el dispositivo (navegador o móvil) la primera vez que se activa App Check, y Firebase lo guarda localmente ahí, no en ningún archivo del proyecto. No se ha tocado `web/index.html`: el proveedor de depuración de `firebase_app_check` fija la variable global `FIREBASE_APPCHECK_DEBUG_TOKEN` desde Dart en tiempo de ejecución, dentro del propio paquete, así que no hace falta (ni se debe) añadir ese script a mano. Si en algún momento hiciera falta un token estable para otra cosa (por ejemplo CI), tendría que guardarse en un archivo local fuera de control de versiones; `.gitignore` ya reserva el nombre `app_check_debug_token.txt` para eso, aunque hoy no se usa.

**`useLimitedUseAppCheckTokens`.** No se ha activado. Según la documentación de Firebase AI Logic, es opcional y solo aporta algo si además se activa la protección contra repetición ("replay protection") en App Check, convirtiendo los tokens en un solo uso; aquí no se ha activado esa protección y el proveedor es el de depuración, pensado solo para desarrollo, así que no tiene sentido añadir esa capa todavía. Si más adelante el proyecto pasa a un proveedor de producción (reCAPTCHA) y se activa replay protection, habría que revisar esta decisión.

## Configuración de Firebase en el cliente

La configuración web de Firebase (`firebase_options.dart`) identifica el proyecto y no es un secreto. La protección de datos depende de las reglas anteriores, no de ocultar esa configuración.

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
- **Mismo App Check que la entrada en lenguaje natural.** El chat usa el mismo `GenerativeModel` por debajo (Gemini Developer API vía Firebase AI Logic) y solo está disponible con `ENABLE_AI`, así que depende de la misma configuración de App Check descrita arriba; no se ha añadido nada nuevo.
- **Sin índices compuestos.** Al probar el chat contra un proyecto real, una consulta que combinaba el rango de `date` con `amountCents` falló con `FAILED_PRECONDITION` pidiendo un índice compuesto. Decisión: en vez de crear ese índice (ni ningún otro), `FirestoreTransactionRepository.findByDateRange` solo filtra por `date` en el servidor; todo lo demás (categoría, signo del importe, sumas) se calcula en código, en `TransactionChatFunctions` (ver docs/design.md). No hace falta ni existe ningún `firestore.indexes.json` en el repositorio.

## Pendiente

- **Pendiente de decisión antes de la entrega (26/10):** registro con email y contraseña. Opciones:
  1. Dejarlo abierto y documentarlo como límite conocido (ya descrito arriba).
  2. Cerrar el alta en la consola de Firebase (desactivar el proveedor de email/contraseña para nuevos usuarios o deshabilitar el registro), comprobando antes que el inicio de sesión sigue funcionando.
- Tests automatizados de las reglas (ahora se verifican manualmente contra el emulador).
- Revisión de dependencias antes de la entrega.
- Exigir correo verificado en las reglas de Firestore.
- **App Check en producción.** El proveedor de depuración no vale para una build publicada: antes de distribuir la app con `ENABLE_AI=true` fuera de desarrollo, hay que configurar reCAPTCHA (web) y Play Integrity (Android) en la consola de Firebase y en `main.dart`. Firebase AI Logic exige App Check de todas formas a partir de noviembre de 2026, así que esto no es opcional si la IA se publica.