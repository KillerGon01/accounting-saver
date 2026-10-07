# Análisis

## Problema

Un asistente financiero personal que permita registrar movimientos de forma manual o en lenguaje natural, consultar el resumen mensual y preguntar sobre los propios datos, sin coste económico.

## Alcance del MVP y estado

| Funcionalidad | Estado | Notas |
|---|---|---|
| Login con email/contraseña | Hecho | `FirebaseAuthRepository`, pantalla `LoginScreen`. |
| Registro con email/contraseña | Hecho | Mismo `LoginScreen` en modo alternable "Crear cuenta". Entra directamente al crear la cuenta. |
| Verificación de correo tras el registro | Hecho | `VerifyEmailScreen` bloquea la app hasta verificar. Google no requiere verificación. |
| Recuperación de contraseña | Hecho | Enlace "¿Has olvidado la contraseña?" con `sendPasswordResetEmail`. Mensaje neutro para no revelar si el correo existe. |
| Login con Google | Hecho | Mismo repositorio de autenticación. |
| Movimientos manuales: alta, edición, borrado | Hecho | Formulario compartido, borrado con confirmación. |
| Listado mensual con navegación entre meses | Hecho | Stream de Firestore por mes, orden descendente. |
| Resumen numérico del mes (ingresos, gastos, balance) | Hecho | Cabecera de la pantalla de movimientos, calculada en dominio. |
| Datos de demostración | Hecho | `LoadDemoData`, no duplica si ya existen. |
| Perfil de usuario (datos de cuenta) | Hecho | `ProfileScreen`, acceso desde un icono de la barra superior. |
| Resumen de actividad del histórico | Hecho | Consultas agregadas (`count` y `sum`); no lee todos los movimientos. |
| Eliminar cuenta | Hecho | Reautenticación, borrado de movimientos en lotes y borrado de la cuenta de Auth. |
| Entrada en lenguaje natural (JSON estructurado y validado) | Hecho | `LlmGateway`/`GeminiLlmGateway`, caso de uso `ParseNaturalLanguageTransaction`, campo en la pantalla de movimientos tras `ENABLE_AI`. |
| Chat con function calling sobre Firestore | Pendiente | |
| Resumen mensual con IA | Pendiente | |

Fuera de alcance: importación CSV, foto de ticket, presupuestos y multidivisa.

## Restricciones

- **Coste cero:** plan Spark de Firebase, sin Cloud Functions ni facturación. Gemini se usa en su nivel gratuito a través de Firebase AI Logic, llamado desde el cliente.
- **Plataformas:** web (prioritaria) y Android, con diseño responsive desde el principio.
- **Dinero en enteros:** todos los importes se guardan y calculan en céntimos (`int`). Nunca `double`.
- **Dominio puro:** la capa de dominio no importa Flutter ni Firebase.

## Requisitos de la pantalla de movimientos

| Requisito | Decisión |
|---|---|
| Lista del mes con navegación | Stream de Firestore filtrado por mes, orden descendente por fecha. |
| Resumen con ingresos, gastos y balance | Cálculo en dominio (`MonthlySummary`) en céntimos, no en el widget. |
| Estados cargando, error y vacío | Un `AsyncValue` por estado, con mensaje en español. |
| Alta y edición con el mismo formulario | `TransactionFormScreen` recibe un `Transaction?` opcional. |
| Importe en euros sin `double` | Parseo de cadena a céntimos con expresión regular (`parseEurosToCents`). |
| Límite del importe | 1.000.000 € en valor absoluto, definido una sola vez (`maxAbsoluteAmountCents`). |
| Validación clara | Importe > 0 y dentro del límite, concepto no vacío y máximo 200 caracteres, categoría obligatoria. |
| Borrado con confirmación | Diálogo previo al `DeleteTransaction`. |
| Datos de ejemplo sin duplicar | `LoadDemoData` comprueba si ya existen movimientos `demo` antes de escribir. |
| Responsive | Columna única con ancho máximo de 720 px (listado) y 560 px (formulario). |

## Requisitos de la entrada en lenguaje natural

| Requisito | Decisión |
|---|---|
| Activación | Oculta por defecto; visible solo si `const bool.fromEnvironment('ENABLE_AI')` es verdadero (`--dart-define=ENABLE_AI=true`). |
| Backend de IA | Gemini Developer API a través de Firebase AI Logic (`FirebaseAI.googleAI()`), no Vertex AI, para mantenerse en el nivel gratuito sin facturación. |
| Salida del modelo | JSON estructurado con `responseSchema` (`Schema.object`), no texto libre: importe en céntimos, fecha ISO, concepto y categoría (`Schema.enumString` con los valores de `Category`). |
| Resultado tipado | `LlmGateway.extractTransaction` devuelve `RawParsedTransaction` (sin validar); `ParseNaturalLanguageTransaction` lo convierte en `ParsedTransaction` (validado) o lanza una excepción. |
| Validación | Importe distinto de cero y dentro de `maxAbsoluteAmountCents` (constructor de `ParsedTransaction`, igual que `Transaction`); categoría existente en el enum y fecha razonable (±1 día de margen y máximo 5 años atrás), comprobadas en el caso de uso. |
| El modelo no puede inventar | El esquema permite `understood: false` en vez de obligar a rellenar los demás campos; si el texto no describe un importe claro, el caso de uso rechaza con `NotUnderstoodException` en vez de proponer un movimiento inventado. |
| Contraste determinista | Antes de llamar a Gemini, `textContainsNumber` (Dart puro, sin red) comprueba que el texto mencione alguna cifra o alguna palabra de número en español; si no, se rechaza sin gastar cuota, y el resultado se descarta igual aunque el modelo devolviera un importe. |
| Nada se guarda sin confirmar | El caso de uso solo devuelve la propuesta; `TransactionFormScreen` la recibe como `initialDraft` y el usuario confirma o edita antes de guardar. |
| Origen del movimiento | Al guardar una propuesta de IA sin editar el origen, se usa `TransactionSource.naturalLanguage`. |
| Errores de cuota o de red | `GeminiLlmGateway` los traduce a `LlmGatewayException` con mensaje en español; la pantalla los muestra en un `SnackBar`. |
| Longitud de entrada | Máximo 300 caracteres en el campo de texto. |
| Privacidad | El texto del usuario no se registra en logs. |

## Requisitos de autenticación

| Requisito | Decisión |
|---|---|
| Registro e inicio de sesión en la misma pantalla | Modo alternable en `LoginScreen`, sin ruta nueva. |
| Validación de correo | Formato básico con expresión regular, recortando espacios antes de enviar. |
| Contraseña al crear cuenta | Mínimo 8 caracteres y confirmación que coincida. |
| Contraseña al iniciar sesión | Solo obligatoria; no se aplica el mínimo para no bloquear cuentas antiguas. |
| Errores de Firebase | `FirebaseAuthRepository` traduce `FirebaseAuthException` a `AuthException` (dominio). La presentación elige el mensaje en español por código. |
| Credenciales incorrectas | Mismo mensaje para `invalid-credential`, `wrong-password` y `user-not-found`, sin revelar si el correo tiene cuenta. |
| Códigos no contemplados | Mensaje genérico. |
| Evitar envíos repetidos | Botón deshabilitado y spinner mientras se procesa. |
| Verificación del correo | Se envía al registrarse (`SignUpWithEmailAndPassword`). Si el envío falla, la cuenta se crea igualmente y la pantalla de verificación permite reenviar. |
| Quién debe verificar | `AppUser.needsEmailVerification`: proveedor `password` y `emailVerified` a false. Los usuarios de Google entran directamente. |
| Puerta de acceso | `AuthGate` muestra `VerifyEmailScreen` en lugar de los movimientos mientras el correo no esté verificado. |
| Comprobar la verificación | "Ya lo he verificado" recarga el usuario (`reloadUser`) e invalida `authStateChangesProvider` si ya está verificado. |
| Reenvío | Espera de 60 segundos con contador visible. La espera empieza al abrir la pantalla, porque el correo acaba de enviarse al registrarse. |
| Correo no recibido | La pantalla indica que revise la carpeta de spam. |
| Salida | "Cerrar sesión / usar otro correo" para cambiar de cuenta. |

## Requisitos de perfil y eliminación de cuenta

| Requisito | Decisión |
|---|---|
| Datos de cuenta | Correo, nombre (si existe), proveedor, correo verificado, fecha de creación y último acceso. Vienen de Firebase Auth a través de `AppUser` y se presentan como `UserProfile`. |
| Resumen de actividad | Número de movimientos, primer y último movimiento, recuento por origen (demo, manual, lenguaje natural) e ingresos y gastos totales en céntimos, formateados en euros. |
| Coste del resumen | `count()` y `sum()` agregados de Firestore, más dos lecturas de un documento para las fechas extremas. No se descarga el histórico. |
| Cerrar sesión | Desde el perfil, vuelve a la pantalla de login. |
| Confirmación de borrado | Diálogo que explica que se borran la cuenta y todos los movimientos, que no se puede deshacer, y que exige escribir el correo exacto para habilitar el botón. |
| Orden del borrado | (1) reautenticar, (2) borrar movimientos, (3) borrar la cuenta de Auth, (4) volver al login. |
| Reautenticación | Con contraseña si el proveedor es correo y contraseña; con el popup de Google si es Google. Si falla o se cancela, no se borra nada. |
| Borrado de movimientos | Lotes de 400 como máximo, en bucle hasta vaciar la colección. Reintentable: si se interrumpe, volver a ejecutarlo termina el trabajo. |
| Bloqueo durante el borrado | La pantalla se bloquea con un indicador de progreso hasta que termina o falla. |
| Fallo a mitad | El mensaje indica la etapa: si fallan los movimientos, la cuenta sigue intacta; si falla la cuenta, los movimientos ya están borrados. En ambos casos se puede reintentar. |
| Datos de otras colecciones | Una única lista (`userDataCollections`) define qué colecciones se borran. Añadir una colección con datos del usuario exige añadirla ahí. |

## Fuera de alcance de esta fase

- Formato de miles en la entrada del importe (`1.234,56`).
- Localización completa de Material (selector de fecha en inglés hasta añadir `flutter_localizations`).
- Atomicidad entre comprobar y escribir los datos demo (dos cargas simultáneas desde dispositivos distintos podrían duplicarlos).
