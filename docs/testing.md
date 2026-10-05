# Pruebas

## Estrategia

- **Dominio y aplicación:** tests unitarios con `FakeTransactionRepository` (en `test/fakes/`). No se usan mocks: el fake implementa la interfaz completa y permite comprobar el estado resultante.
- **Infraestructura:** pendiente. Requiere Firestore emulado o `fake_cloud_firestore`, y ninguno está añadido.
- **Presentación:** solo hay un widget test de la pantalla de login. Los widgets de movimientos no tienen tests automatizados todavía.

## Comandos

```bash
flutter analyze
flutter test
```

Ejecutar ambos antes de cada PR.

## Cobertura actual

| Archivo | Qué prueba |
|---|---|
| `test/domain/transactions/amount_parser_test.dart` | Coma y punto decimal, un decimal, espacios, cero, formatos inválidos, desbordamiento y límite del importe. |
| `test/domain/transactions/transaction_test.dart` | Creación válida, importe cero, límite del importe, descripción vacía, `copyWith`. |
| `test/domain/transactions/monthly_summary_test.dart` | Resumen con el fake: solo el mes pedido, mes vacío, balance negativo. Usa los casos de uso de aplicación para preparar los datos. |
| `test/application/transactions/transaction_use_cases_test.dart` | Alta, edición, borrado y listado por mes, incluidos los límites de mes y el cambio de año. |
| `test/application/transactions/load_demo_data_test.dart` | 60 movimientos, fechas repartidas, recurrencias fijas, nómina en día 1 o 28, sin fechas futuras, sin duplicados, aislamiento por usuario. |
| `test/widget_test.dart` | Login cuando no hay usuario. |

## Casos de borde del límite del importe

El límite es 1.000.000 € en valor absoluto (`maxAbsoluteAmountCents`, 100.000.000 céntimos).

- Parser: `1000000` y `1000000,00` se aceptan; `999999,99` se acepta; `1000000,01` y `1000001` se rechazan; `1000000000` se rechaza por longitud.
- `Transaction`: `100000000` y `-100000000` se aceptan; `100000001` y `-100000001` lanzan `ArgumentError`.

## Pendiente

- Tests de `FirestoreTransactionRepository` con emulador o `fake_cloud_firestore`.
- Tests automatizados de las reglas de Firestore. Las reglas se han comprobado a mano contra el emulador local, pero no hay test en el repositorio.
- Widget tests del listado (estados cargando, error y vacío), del formulario (validación) y del diálogo de borrado.
