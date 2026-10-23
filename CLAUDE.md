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
Gemini siempre detrás de una interfaz de dominio (LlmGateway, ChatGateway,
MonthlyReportGateway, PayrollGateway, SavingsSuggestionsGateway). Tests con fakes.

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
Hecho: MVP completo (login email/Google, movimientos manuales, lenguaje natural, chat con
function calling, resumen mensual) y todos los extras (nóminas en PDF, previsión de fin de mes,
búsqueda y filtros, gastos inusuales, metas de ahorro, sugerencias de ahorro con y sin IA, tema
oscuro, icono propio, ayuda contextual, Docker con nginx y CI en GitHub Actions); incluye el
rediseño visual y los arreglos de autenticación/arranque en Android y web (Google Sign-In nativo,
bug de `GoogleSignIn` en web) y el refactor de los archivos más grandes, ya fusionado en main
(`chore/split-large-files`, PR #56) — detalle de todo ello en docs/design.md y docs/security.md.
708 tests.
Pendiente de verdad: renombrar `applicationId` (sigue en `com.example.accounting_saver`), App
Check de producción en Android (Play Integrity sin vincular en Play Console), añadir
`firestore-tests/` al CI, y ajustar `_checkMonthAttribution` (ver docs/evaluation.md). El resto
de riesgos/límites ya documentados en docs/design.md/docs/security.md se asumen como están.
Código congelado para la entrega salvo bugs bloqueantes.