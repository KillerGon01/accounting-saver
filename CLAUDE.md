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
Extra implementado (fuera del MVP original): lectura de nóminas en PDF con IA,
solo web, con validación de bruto/deducciones/líquido en código (ver docs/design.md).

## Datos
users/{uid}/transactions/{id}: amountCents (int, negativo = gasto), date,
description, categoryId, source, createdAt. Categorías fijas en código.

## Convenciones
- Commits: "[ADDED|CHANGED|REMOVED] Resumen corto" (texto en inglés).
- google-services.json está en .gitignore.
- Sin secretos en el repo. Reglas de Firestore: cada usuario solo lee lo suyo.
- Hecho: Dockerizar la web (nginx) y CI con GitHub Actions. Mejora futura, no pendiente
  inminente: Husky (hooks de git locales); el CI ya cubre el mismo control (`flutter analyze`,
  `flutter test`) en cada PR, aunque no evita el commit en el equipo de quien lo hace.
- Una rama por funcionalidad (feature/...), PR hacia main. No commitear directamente en main.
- Al terminar cada tarea, actualiza la sección "Estado" de este archivo:
  qué se ha hecho y cuál es el siguiente paso. Mantenla en 4-5 líneas.
  Muéstrame el cambio, pero no hagas commit.
- Documentar el proceso en docs/ (analysis, design, testing, security). Al cerrar
    cada funcionalidad, actualizar el documento que corresponda.

## Estado
Hecho: MVP completo, lectura de nóminas en PDF, previsión de fin de mes, búsqueda y filtros de
movimientos y, nuevo, detección de gastos inusuales en el resumen mensual (sin IA):
`detectUnusualExpenses`/`BuildUnusualExpenses` marcan un gasto del mes en curso como inusual si
supera el doble de la mediana de su categoría en los 3 meses anteriores (mínimo 4 gastos de
histórico), excluyendo recurrentes con la misma regla que `findRecurringExpenses`; mismo patrón de
fallo silencioso que la previsión de fin de mes, con la que no comparte lectura (el resumen del
mes en curso pasa de 4 a 6 consultas por carga, ver docs/design.md). Tests: 499.
Pendiente: lo de antes (ajustar `_checkMonthAttribution`, flutter_localizations, registro
abierto, App Check de producción en Android, `thinkingConfig`, CI para `firestore-tests/`,
repetir la evaluación del chat con `transactionLines`, cuota compartida entre nóminas y chat/
lenguaje natural) más los riesgos de la previsión de fin de mes y los límites de la detección de
gastos inusuales documentados en docs/design.md (sin estacionalidad, pocos datos, solo compara
dentro de la misma categoría).
Siguiente: decidir los pendientes de seguridad antes de la entrega (26/10).