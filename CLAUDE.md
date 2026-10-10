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
demo, resumen mensual con gráficos) tras `ENABLE_AI`, con protección de cuota de Gemini
(fallback de modelo, timeout de 90 s sin reintento, reintento único ante 503, topes de 8
preguntas/3 comentarios, caché, aislamiento por usuario) y App Check de producción en web
(reCAPTCHA Enterprise); detalles en docs/design.md, docs/testing.md y docs/security.md. Nuevo:
resumen mensual (`MonthlyReport`/`BuildMonthlyReport`/`ExplainMonthlyReport`, en
`lib/domain|application/reports/`) con gasto por categoría, comparación con el mes anterior
(`null` si no hay datos), aviso de mes en curso/informe truncado (también en el prompt de la
IA, que nunca recibe conceptos de movimiento, solo cifras agregadas) y refresco automático al
cambiar los movimientos (`transactionsVersionProvider`, nuevo). `thinkingConfig` sigue sin
aplicarse (riesgo sin forma de probarlo contra Gemini real en este entorno).
Pendiente: flutter_localizations, decisión sobre registro abierto, App Check de producción en
Android, revisión visual en navegador (resumen mensual incluido), confirmar `thinkingConfig`.
Siguiente: esa revisión visual y decidir los pendientes de seguridad antes de la entrega (26/10).