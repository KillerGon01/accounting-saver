# Pruebas

## Estrategia

- **Dominio y aplicación:** tests unitarios con `FakeTransactionRepository` (en `test/fakes/`). No se usan mocks: el fake implementa la interfaz completa y permite comprobar el estado resultante.
- **Infraestructura:** pendiente. Requiere Firestore emulado o `fake_cloud_firestore`, y ninguno está añadido.
- **Presentación:** widget tests de la pantalla de login y de la pantalla de movimientos. Los tests de la pantalla de movimientos usan `FakeTransactionRepository` mediante `transactionRepositoryProvider.overrideWithValue`.

## Comandos

```bash
flutter analyze
flutter test
```

Ejecutar ambos antes de cada PR.

## Cobertura actual

| Archivo | Qué prueba |
|---|---|
| `test/domain/transactions/amount_parser_test.dart` | Coma y punto decimal, un decimal, espacios, cero, formatos inválidos, desbordamiento y límite del importe. |
| `test/domain/transactions/transaction_test.dart` | Creación válida, importe cero, límite del importe, descripción vacía, `copyWith`. |
| `test/domain/transactions/monthly_summary_test.dart` | Resumen con el fake: solo el mes pedido, mes vacío, balance negativo. Usa los casos de uso de aplicación para preparar los datos. |
| `test/application/transactions/transaction_use_cases_test.dart` | Alta, edición, borrado y listado por mes, incluidos los límites de mes y el cambio de año. |
| `test/application/transactions/load_demo_data_test.dart` | 60 movimientos, fechas repartidas, recurrencias fijas, nómina en día 1 o 28, sin fechas futuras, sin duplicados, aislamiento por usuario. |
| `test/presentation/transactions/day_groups_test.dart` | Agrupación por día conservando el orden; lista vacía. |
| `test/presentation/transactions/transactions_screen_test.dart` | Estado vacío con botón de datos de ejemplo; cabecera de día, importes de movimientos y resumen, tooltips de navegación y de cerrar sesión. |
| `test/widget_test.dart` | `AuthGate`: login sin usuario, verificación para correo sin verificar, entrada directa con correo verificado o con Google, y "Ya lo he verificado" cambia de pantalla. |
| `test/presentation/auth/login_screen_test.dart` | Modo de inicio de sesión y de registro, validaciones, mensajes de error en español, estado de carga, recuperación de contraseña, envío del correo de verificación y mostrar u ocultar la contraseña. |
| `test/presentation/auth/verify_email_screen_test.dart` | Correo mostrado y aviso de spam, espera de 60 s para reenviar, límite de envíos en español, aviso si sigue sin verificar y cierre de sesión. |
| `test/domain/auth/user_profile_test.dart` | Proveedor de `UserProfile` a partir de `providerIds`, fechas conservadas y `needsEmailVerification`. |
| `test/domain/transactions/activity_summary_test.dart` | Resumen en memoria: cero movimientos, recuentos por origen, ingresos y gastos separados, fechas extremas. |
| `test/application/auth/delete_account_test.dart` | Borrado exitoso, reautenticación fallida (no borra nada), Google sin contraseña, contraseña vacía, fallo a mitad del borrado con reintento y fallo al borrar la cuenta con reintento. |
| `test/presentation/profile/profile_screen_test.dart` | Datos de cuenta y resumen, confirmación con correo exacto, reautenticación fallida, borrado completo y reintento tras fallo de la cuenta. |
| `test/domain/transactions/parsed_transaction_test.dart` | Creación válida, importe cero, límite del importe, descripción vacía o demasiado larga; `categoryFromName` con nombre válido e inexistente. |
| `test/domain/transactions/number_detection_test.dart` | `textContainsNumber`: dígitos, palabras de número en español, mayúsculas y acentos, y texto sin ningún número (`asdf`, `hola`, vacío, `bar ayer`). |
| `test/application/transactions/parse_natural_language_transaction_test.dart` | Con `FakeLlmGateway`: propuesta correcta, importe con palabras ("doce euros"), `understood: false`, contraste determinista (el gateway devuelve un importe para un texto sin números y se rechaza igual), "hola", texto vacío, "bar ayer", `understood: true` con un campo que falta, categoría inválida, importe por encima del límite, respuesta malformada, error de cuota, fecha futura y fecha demasiado antigua. |

Total: 116 tests (`flutter test`).

## Entrada en lenguaje natural

`FakeLlmGateway` (en `test/fakes/`) se configura con `FakeLlmGateway.returning(...)` para devolver un `RawParsedTransaction` fijo, o `FakeLlmGateway.throwing(...)` para simular un error del gateway (por ejemplo `LlmGatewayException('quota-exceeded')`). Así se prueba `ParseNaturalLanguageTransaction` sin llamar a Gemini.

El contraste determinista (`textContainsNumber`) se prueba dos veces: aislado, en `number_detection_test.dart`, y dentro del caso de uso, configurando el fake para que devuelva un importe válido ante un texto sin ningún número — y comprobando que se rechaza igual, porque esa comprobación no depende de lo que diga el gateway.

No hay test de `GeminiLlmGateway` ni del campo de la pantalla de movimientos: requieren un proyecto de Firebase con AI Logic habilitado y no se han ejecutado contra el servicio real en esta sesión.

## Casos de borde del límite del importe

El límite es 1.000.000 € en valor absoluto (`maxAbsoluteAmountCents`, 100.000.000 céntimos).

- Parser: `1000000` y `1000000,00` se aceptan; `999999,99` se acepta; `1000000,01` y `1000001` se rechazan; `1000000000` se rechaza por longitud.
- `Transaction`: `100000000` y `-100000000` se aceptan; `100000001` y `-100000001` lanzan `ArgumentError`.

## Pendiente

- Tests de `FirestoreTransactionRepository` con emulador o `fake_cloud_firestore`. Incluye `getActivitySummary` con sus agregados (`count` y `sum`), que hoy solo se verifica leyendo el código.
- Tests de `FirestoreUserDataRepository` (borrado en lotes de 400 contra el emulador) y de `FirebaseAuthRepository` (reautenticación y `delete`). Sin emulador no se pueden probar.
- Tests automatizados de las reglas de Firestore. Las reglas se han comprobado a mano contra el emulador local, pero no hay test en el repositorio.
- Widget tests del estado de carga y del estado de error del listado.
- Widget tests del formulario (validación) y del diálogo de borrado.
- Tests de `GeminiLlmGateway` y del campo "Añadir con lenguaje natural": requieren un proyecto con Firebase AI Logic habilitado.
