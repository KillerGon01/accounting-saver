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
| `test/application/chat/transaction_chat_functions_test.dart` | `getMonthlySummary`, `listTransactions` y `recurringExpenses`: resumen correcto en céntimos, mes/año fuera de rango, argumentos que faltan, filtro por categoría, recorte a 30 movimientos con totales del rango completo (no de lo recortado), `hasta` anterior a `desde`, rango de más de 5 años, categoría inexistente, fecha con formato inválido, función desconocida, varios ingresos y gastos separados por signo en código, aviso con `safetyLimitReached`/`safetyLimitNote` al superar `maxFetchLimit` movimientos leídos, y que el recorte a 30 se aplique después del filtro por categoría (no antes). `recurringExpenses`: detecta un cargo igual en 3 meses distintos, no detecta uno único ni uno con importes distintos entre meses, normaliza mayúsculas y espacios antes de comparar, cuenta dos movimientos del mismo mes como un solo mes, ignora los ingresos, ignora un movimiento fuera del rango de 3 meses, y el resultado siempre incluye el rango analizado (`desde`/`hasta`), con un `note` explícito cuando no hay ninguno. En cada caso inválido se comprueba que no se ha ejecutado ninguna consulta (`repository.transactionsOf` sigue vacío). |
| `test/application/chat/send_chat_message_test.dart` | Con `FakeChatGateway`: devuelve la respuesta del gateway, recorta el historial a los últimos 10 mensajes, no recorta uno ya corto, rechaza una segunda petición mientras la primera está en curso (`StateError`), permite una nueva tras terminar la anterior, libera la guarda incluso si el gateway falla, pasa el nombre y los argumentos de la función pedida al executor. |
| `test/infrastructure/chat/gemini_chat_gateway_test.dart` | `buildChatSystemInstruction` con `FakeClock`: resuelve "este mes" y "el mes pasado" a partir de una fecha fija, el mes pasado cruza al año anterior en enero, y el texto le pide explícitamente al modelo no preguntar por el año o el mes y llamar siempre a la función adecuada. `functionResponsesContent`: el rol no es `'function'` (el que rechaza el backend), es `'user'`, conserva el nombre y el mapa de resultado de cada función, y agrupa varias respuestas en un único `Content` en el mismo orden. |

Total: 153 tests (`flutter test`).

## Entrada en lenguaje natural

`FakeLlmGateway` (en `test/fakes/`) se configura con `FakeLlmGateway.returning(...)` para devolver un `RawParsedTransaction` fijo, o `FakeLlmGateway.throwing(...)` para simular un error del gateway (por ejemplo `LlmGatewayException('quota-exceeded')`). Así se prueba `ParseNaturalLanguageTransaction` sin llamar a Gemini.

El contraste determinista (`textContainsNumber`) se prueba dos veces: aislado, en `number_detection_test.dart`, y dentro del caso de uso, configurando el fake para que devuelva un importe válido ante un texto sin ningún número — y comprobando que se rechaza igual, porque esa comprobación no depende de lo que diga el gateway.

No hay test de `GeminiLlmGateway` ni del campo de la pantalla de movimientos: requieren un proyecto de Firebase con AI Logic habilitado y no se han ejecutado contra el servicio real en esta sesión.

## Chat con function calling

`FakeChatGateway` (en `test/fakes/`) tiene tres constructores: `returning(...)` para una respuesta de texto fija, `callingFunction(nombre, argumentos, respuesta)` para comprobar que `SendChatMessage` pasa el executor correcto (nombre y argumentos) sin depender de Gemini, y `throwing(...)` para simular un fallo del gateway. `TransactionChatFunctions` se prueba directamente contra `FakeTransactionRepository`, sin pasar por ningún gateway.

`FakeTransactionRepository.findByDateRange` reproduce a propósito la misma limitación que `FirestoreTransactionRepository`: solo filtra por fecha y ordena por fecha, sin aceptar categoría. Así los tests de `TransactionChatFunctions` comprueban de verdad que el filtrado por categoría y por signo del importe ocurre en código (en `TransactionChatFunctions`), no en el repositorio — si el fake filtrara también por categoría, esos tests pasarían igual aunque la lógica de aplicación estuviera mal.

No hay test de `GeminiChatGateway` (el bucle de `generateContent` con `functionCalls` reales) ni de `ChatScreen`: igual que con `GeminiLlmGateway`, requieren un proyecto con Firebase AI Logic habilitado y no se han ejecutado contra el servicio real en esta sesión.

**`buildChatSystemInstruction` sí se prueba**, porque es una función libre sin ninguna dependencia de `firebase_ai` ni de red: solo depende de un [`Clock`](../lib/domain/common/clock.dart) (dominio). `FakeClock` (en `test/fakes/`) siempre devuelve la misma fecha fijada en el test, así que `test/infrastructure/chat/gemini_chat_gateway_test.dart` comprueba, sin ningún proyecto de Firebase, que la instrucción de sistema resuelve correctamente "este mes" y "el mes pasado" (incluido el cruce de enero a diciembre del año anterior) y que le pide al modelo no preguntar por el año o el mes y llamar siempre a una función.

**`functionResponsesContent` también se prueba sin Firebase**, aunque sí importa `package:firebase_ai` (para construir un `Content` y un `FunctionResponse` de verdad): no llama a ningún método de red, así que el test solo construye el objeto y comprueba sus campos (`role`, `parts`). Esto fue justo lo que detectó, al usar la app de verdad, que `Content.functionResponses` del paquete fija un rol (`'function'`) que el backend ya no acepta — el test lo deja fijado para que no se repita si alguien vuelve a usar esa función del paquete sin darse cuenta.

## Casos de borde del límite del importe

El límite es 1.000.000 € en valor absoluto (`maxAbsoluteAmountCents`, 100.000.000 céntimos).

- Parser: `1000000` y `1000000,00` se aceptan; `999999,99` se acepta; `1000000,01` y `1000001` se rechazan; `1000000000` se rechaza por longitud.
- `Transaction`: `100000000` y `-100000000` se aceptan; `100000001` y `-100000001` lanzan `ArgumentError`.

## Pendiente

- Tests de `FirestoreTransactionRepository` con emulador o `fake_cloud_firestore`. Incluye `getActivitySummary` con sus agregados (`count` y `sum`) y `findByDateRange`, que hoy solo se verifican leyendo el código (en particular, que `findByDateRange` no dispare ningún `FAILED_PRECONDITION` por índice compuesto, que es justo lo que se eliminó).
- Tests de `FirestoreUserDataRepository` (borrado en lotes de 400 contra el emulador) y de `FirebaseAuthRepository` (reautenticación y `delete`). Sin emulador no se pueden probar.
- Tests automatizados de las reglas de Firestore. Las reglas se han comprobado a mano contra el emulador local, pero no hay test en el repositorio.
- Widget tests del estado de carga y del estado de error del listado.
- Widget tests del formulario (validación) y del diálogo de borrado.
- Tests de `GeminiLlmGateway` y del campo "Añadir con lenguaje natural": requieren un proyecto con Firebase AI Logic habilitado.
- Tests de `GeminiChatGateway` y de `ChatScreen`: igual que arriba, requieren un proyecto con Firebase AI Logic habilitado.
