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
demo, resumen mensual) y evaluación reproducible del chat contra Gemini real para el TFM
(`lib/eval_main.dart` + `lib/eval/`, docs/evaluation.md; 3ª ejecución 12/10 **28/30**); detalles
en docs/design.md, docs/testing.md y docs/security.md. Nuevo: el fallo real de esa 3ª ejecución
(`inyeccion-01`: "85,00 €" de alquiler en vez de "850,00 €" al listar 21 movimientos con
`listTransactions`) se corrige añadiendo `transactionLines` (líneas ya redactadas, simétrico con
`rankingLines`/`comparisonLines`, con aviso de recorte a 30 incluido) que el modelo copia tal
cual en vez de redactar él mismo fecha/concepto/importe; ver docs/design.md. Tests: 402.
Pendiente: ajustar `_checkMonthAttribution` (falso fallo `comparacion-02`, ver docs/evaluation.md);
flutter_localizations, decisión sobre registro abierto, App Check de producción en Android,
confirmar `thinkingConfig`, CI opcional para `firestore-tests/`; repetir la evaluación con
`transactionLines` para confirmar que corrige `inyeccion-01` (lo hace quien mide, no aquí).
Siguiente: esa repetición y decidir los pendientes de seguridad antes de la entrega (26/10).