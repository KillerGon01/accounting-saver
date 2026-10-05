# Diseño

## Arquitectura

Clean Architecture con cuatro capas. Las dependencias apuntan hacia el dominio.

```
lib/
  domain/            Dart puro: entidades, interfaces de repositorio, reglas (sin Flutter ni Firebase)
  application/       Casos de uso que orquestan el dominio
  infrastructure/    Implementaciones: Firestore, Firebase Auth (y Gemini, pendiente)
  presentation/      Widgets y providers de Riverpod
```

Gemini irá siempre detrás de una interfaz `LlmGateway`, para poder sustituirlo en tests con un fake.

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
