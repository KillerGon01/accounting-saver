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

## Interfaz

- Móvil (menos de 600 px): columna única.
- Pantallas grandes: contenido centrado con ancho máximo.
- Cabecera con resumen, navegación entre meses y lista. Acciones: cargar datos de ejemplo y cerrar sesión. Botón flotante para añadir.
- Tocar un movimiento abre el formulario de edición; el icono de papelera pide confirmación.
