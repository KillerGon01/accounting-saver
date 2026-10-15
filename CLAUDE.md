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
Hecho: todo lo anterior (MVP, nóminas en PDF, previsión de fin de mes, búsqueda y filtros,
gastos inusuales, metas de ahorro, sugerencias de ahorro por meta sin IA) y, nuevo, su fase 2:
redacción con IA opcional de esas mismas sugerencias. `SavingsSuggestionsSummary` (dominio puro,
sin ningún campo de texto libre: solo cifras formateadas en euros, categorías fijas y líneas ya
redactadas listas para copiar) y `SavingsSuggestionsGateway`/`GeminiSavingsSuggestionsGateway`
(mismo patrón de fallback/reintento/timeout/errores que el resto de usos de Gemini) y
`ExplainSavingsSuggestions` (tope de 6 por sesión, caché por meta invalidada por movimientos o
por cambios en la propia meta, aislado por usuario). Botón "Redactar resumen con IA" en la hoja
de sugerencias, visible solo con `effectiveEnableAi`, nunca sustituye la lista. Tests: 517.
Pendiente: lo de antes (ajustar `_checkMonthAttribution`, flutter_localizations, registro
abierto, App Check de producción en Android, `thinkingConfig`, CI para `firestore-tests/`,
repetir la evaluación del chat con `transactionLines`, cuota compartida entre nóminas, chat,
lenguaje natural, resumen mensual y ahora también sugerencias de ahorro) más los riesgos/límites
ya documentados en docs/design.md/docs/security.md (previsión de fin de mes, gastos inusuales,
metas de ahorro, sugerencias de ahorro sin IA y, ahora, su redacción con IA: nivel gratuito de
Gemini, Google puede usar el contenido enviado).
Siguiente: decidir los pendientes de seguridad antes de la entrega (26/10).