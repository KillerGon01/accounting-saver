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
Hecho: login, perfil con eliminación de cuenta, movimientos responsive, tema Material 3,
reglas con límite de 1.000.000 €, entrada en lenguaje natural con Gemini y chat con function
calling sobre Firestore (`ChatGateway`/`GeminiChatGateway`; funciones `getMonthlySummary`,
`listTransactions` y `recurringExpenses`, esta última con una definición determinista de
"recurrente" en código, sobre los últimos 3 meses completos), todo tras `ENABLE_AI` y con App
Check en modo depuración (ver docs/security.md). Decisiones del chat: sin índices compuestos
en Firestore (`findByDateRange` solo filtra por fecha, el resto en código); fecha de hoy
resuelta en cada petición con un `Clock` inyectable; respuestas de función con un `Content`
de rol `'user'` propio en vez de `Content.functionResponses` del paquete (fija un rol que el
backend rechaza); respuesta siempre en texto plano, sin Markdown (ver docs/design.md).
Pendiente: flutter_localizations, decisión sobre el registro abierto y sobre App Check en
producción (ver docs/security.md), revisión visual en navegador.
Siguiente: revisión visual del chat en navegador y decisión sobre los pendientes de seguridad
antes de la entrega (26/10).