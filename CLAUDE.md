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
reglas con límite de 1.000.000 €, entrada en lenguaje natural y chat con function calling
sobre Firestore, todo tras `ENABLE_AI`. Protección de la cuota gratuita de Gemini: fallback
de modelo tras un 429 (`gemini-3.8-flash` → `gemini-2.5-flash` → `gemini-2.5-flash-lite`,
1 h de memoria por modelo) y reintento de un solo intento tras 1,5 s ante un 503/`UNAVAILABLE`
transitorio (mismo modelo, sin tocar esa memoria); tope de 8 preguntas por sesión de chat
(solo cuenta una llamada al modelo con éxito, ni caché ni error) con contador visible; caché
en memoria por pregunta invalidada al crear, editar o borrar un movimiento, y también al
cargar o borrar datos de ejemplo (`LoadDemoData`, `DeleteAccount`); caché, contador e
historial del chat aislados por usuario (`sendChatMessageProvider` como `Provider.family` por
`userId`, para que cerrar sesión y entrar con otra cuenta no comparta nada) — todo en
docs/design.md y docs/security.md; propuesta de `thinkingConfig` pendiente de confirmar, sin
aplicar. Datos demo corregidos: solo Alquiler, Gimnasio, Netflix y Spotify quedan fijos
(recurrentes de verdad); el resto varía de importe cada mes a propósito
(`_DemoEntry.monthlyShiftCents`, determinista, sin azar).
Pendiente: flutter_localizations, decisión sobre registro abierto y App Check en producción
(ver docs/security.md), revisión visual en navegador (contador del chat incluido).
Siguiente: esa revisión visual y decidir los pendientes de seguridad antes de la entrega (26/10).