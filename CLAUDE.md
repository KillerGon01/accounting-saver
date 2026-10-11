# accounting-saver

TFM del Máster de Desarrollo con IA (Big School). Entrega: 26/10/2026.
Asistente financiero personal con IA (Gemini). Flutter + Firebase.

## Restricciones
- Coste cero: plan Spark de Firebase, sin Cloud Functions, sin facturación.
- Gemini vía Firebase AI Logic (nivel gratuito), llamado desde el cliente.
- Plataformas: web (prioritaria) y Android. Diseño responsive desde el principio.
- Respóndeme siempre en castellano (España).

## Arquitectura (Clean Architecture)
lib/domain (Dart puro, sin Firebase ni Flutter), lib/application (casos de uso),
lib/infrastructure (Firestore, Gemini, Auth), lib/presentation (Riverpod).
Gemini siempre detrás de la interfaz LlmGateway. Tests con fakes.

## Alcance MVP
Login (email/contraseña y Google), movimientos manuales, entrada en lenguaje
natural (JSON estructurado y validado), datos de demostración, chat con
function calling sobre Firestore, resumen mensual.
Fuera: CSV, foto de ticket (extra), presupuestos, multidivisa.

## Datos
users/{uid}/transactions/{id}: amountCents (int, negativo = gasto), date,
description, categoryId, source, createdAt. Categorías fijas en código.

## Convenciones
- Commits: "[ADDED|CHANGED|REMOVED] Resumen corto" (texto en inglés).
- google-services.json está en .gitignore.
- Sin secretos en el repo. Reglas de Firestore: cada usuario solo lee lo suyo.
- Pendiente: Dockerizar la web (nginx), CI con GitHub Actions y Husky.
- Una rama por funcionalidad (feature/...), PR hacia main. No commitear directamente en main.
- Al terminar cada tarea, actualiza la sección "Estado" de este archivo:
  qué se ha hecho y cuál es el siguiente paso. Mantenla en 4-5 líneas.
  Muéstrame el cambio, pero no hagas commit.
- Documentar el proceso en docs/ (analysis, design, testing, security). Al cerrar
    cada funcionalidad, actualizar el documento que corresponda.

## Estado
Hecho: MVP completo (login, movimientos, lenguaje natural, chat con function calling, datos
demo, resumen mensual con gráficos) tras `ENABLE_AI`, con protección de cuota de Gemini, App
Check de producción en web, CI y Docker para la web; detalles en docs/design.md, docs/testing.md
y docs/security.md. Nuevo: dos desbordamientos de layout en Android con pantallas pequeñas. (1)
Vertical con el teclado abierto: el estado vacío de movimientos y el de chat (`Center > Column`
de tamaño fijo bajo un `Expanded`) no cedían cuando el `Scaffold` encogía el `body`
(`resizeToAvoidBottomInset`); ahora van en `LayoutBuilder + SingleChildScrollView +
ConstrainedBox(minHeight: ...)`. (2) Horizontal en el resumen mensual: la fila "Comparación con
el mes anterior" + "(parcial, mes en curso)" no cedía (ahora `Wrap`); y el desplegable de
categoría del formulario de movimiento desbordaba porque su `Row` (icono + etiqueta) no tenía
`isExpanded: true` en el `DropdownButtonFormField` (sin él, el `Row` interno de cada item se
mide con ancho no acotado y ni `Expanded` ni `Flexible` son válidos ahí). Tests nuevos: teclado
simulado (`viewInsets.bottom`) para los estados vacíos, y `textScaler` 1.3 con texto largo para
resumen mensual, chat, formulario, login y registro, ambos a 360x640 y 407x904.
Pendiente: flutter_localizations, decisión sobre registro abierto, App Check de producción en
Android, revisión visual en navegador, confirmar `thinkingConfig`, CI opcional para
`firestore-tests/`.
Siguiente: esa revisión visual y decidir los pendientes de seguridad antes de la entrega (26/10).