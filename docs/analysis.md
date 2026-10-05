# Análisis

## Problema

Un asistente financiero personal que permita registrar movimientos de forma manual o en lenguaje natural, consultar el resumen mensual y preguntar sobre los propios datos, sin coste económico.

## Alcance del MVP y estado

| Funcionalidad | Estado | Notas |
|---|---|---|
| Login con email/contraseña | Hecho | `FirebaseAuthRepository`, pantalla `LoginScreen`. |
| Login con Google | Hecho | Mismo repositorio de autenticación. |
| Movimientos manuales: alta, edición, borrado | Hecho | Formulario compartido, borrado con confirmación. |
| Listado mensual con navegación entre meses | Hecho | Stream de Firestore por mes, orden descendente. |
| Resumen numérico del mes (ingresos, gastos, balance) | Hecho | Cabecera de la pantalla de movimientos, calculada en dominio. |
| Datos de demostración | Hecho | `LoadDemoData`, no duplica si ya existen. |
| Entrada en lenguaje natural (JSON estructurado y validado) | Pendiente | |
| Chat con function calling sobre Firestore | Pendiente | |
| Resumen mensual con IA | Pendiente | |

Fuera de alcance: importación CSV, foto de ticket, presupuestos y multidivisa.

## Restricciones

- **Coste cero:** plan Spark de Firebase, sin Cloud Functions ni facturación. Gemini se usa en su nivel gratuito a través de Firebase AI Logic, llamado desde el cliente.
- **Plataformas:** web (prioritaria) y Android, con diseño responsive desde el principio.
- **Dinero en enteros:** todos los importes se guardan y calculan en céntimos (`int`). Nunca `double`.
- **Dominio puro:** la capa de dominio no importa Flutter ni Firebase.

## Requisitos de la pantalla de movimientos

| Requisito | Decisión |
|---|---|
| Lista del mes con navegación | Stream de Firestore filtrado por mes, orden descendente por fecha. |
| Resumen con ingresos, gastos y balance | Cálculo en dominio (`MonthlySummary`) en céntimos, no en el widget. |
| Estados cargando, error y vacío | Un `AsyncValue` por estado, con mensaje en español. |
| Alta y edición con el mismo formulario | `TransactionFormScreen` recibe un `Transaction?` opcional. |
| Importe en euros sin `double` | Parseo de cadena a céntimos con expresión regular (`parseEurosToCents`). |
| Límite del importe | 1.000.000 € en valor absoluto, definido una sola vez (`maxAbsoluteAmountCents`). |
| Validación clara | Importe > 0 y dentro del límite, concepto no vacío y máximo 200 caracteres, categoría obligatoria. |
| Borrado con confirmación | Diálogo previo al `DeleteTransaction`. |
| Datos de ejemplo sin duplicar | `LoadDemoData` comprueba si ya existen movimientos `demo` antes de escribir. |
| Responsive | Columna única con ancho máximo de 720 px (listado) y 560 px (formulario). |

## Fuera de alcance de esta fase

- Formato de miles en la entrada del importe (`1.234,56`).
- Localización completa de Material (selector de fecha en inglés hasta añadir `flutter_localizations`).
- Atomicidad entre comprobar y escribir los datos demo (dos cargas simultáneas desde dispositivos distintos podrían duplicarlos).
