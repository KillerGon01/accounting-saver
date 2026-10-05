# Seguridad

## Autenticación

- Email/contraseña y Google mediante `firebase_auth`.
- La pantalla principal solo se muestra con sesión iniciada (`AuthGate` en `main.dart`).
- No hay secretos en el repositorio. `google-services.json` está en `.gitignore`.

## Reglas de Firestore (`firestore.rules`)

Cada usuario solo puede leer y borrar sus propios movimientos. Crear o editar exige que el documento tenga exactamente los campos que escribe `FirestoreTransactionRepository`, con los tipos y valores válidos:

| Campo | Condición |
|---|---|
| (conjunto de campos) | Exactamente `amountCents`, `date`, `description`, `categoryId`, `source`, `createdAt`. Ni más ni menos. |
| `amountCents` | `int`, distinto de 0, entre -100.000.000 y 100.000.000 céntimos. |
| `description` | `string` de 1 a 200 caracteres. |
| `categoryId` | Uno de los nombres de `Category`. |
| `source` | Uno de los nombres de `TransactionSource`. |
| `date`, `createdAt` | `timestamp`. |

Las reglas se han comprobado a mano contra el emulador local de Firestore: el límite exacto se acepta, un céntimo por encima se rechaza, y también se rechazan cada campo inválido, los campos extra y la escritura en la cuenta de otro usuario.

## Límites conocidos

- **Registro abierto.** La aplicación tiene el caso de uso `SignUpWithEmailAndPassword`, aunque la pantalla de login no lo expone. Firebase Auth acepta altas por correo y contraseña mientras el proveedor esté habilitado, y la configuración web de Firebase es pública. Cualquiera con esa configuración podría crear cuentas en masa y consumir la cuota gratuita de Firestore. No he comprobado la configuración del proyecto en la consola de Firebase.
- **Sin App Check.** El proyecto no incluye App Check ni ninguna otra comprobación de que las peticiones provienen de la aplicación. No hay nada implementado que resuelva el punto anterior.
- **Sin límite de frecuencia.** Las reglas no limitan cuántos documentos puede escribir un usuario autenticado. Sin Cloud Functions, la única protección de cuota es la que aplique Firebase.
- **Lista de valores fijos.** Las categorías y fuentes válidas están escritas en `firestore.rules`. Si se añade un valor al enum en Dart, hay que añadirlo también en las reglas.
- **La verificación de correo solo se aplica en la interfaz.** La app muestra
  `VerifyEmailScreen` a los usuarios de correo y contraseña con el correo sin
  verificar, pero Firestore no lo exige. Alguien que llame directamente a la API
  de Firebase con una cuenta no verificada podría seguir leyendo y escribiendo en
  su propio espacio. Mejora pendiente: exigir
  `request.auth.token.email_verified == true` en las reglas (la app tendría que
  refrescar el token tras verificar).

## Configuración de Firebase en el cliente

La configuración web de Firebase (`firebase_options.dart`) identifica el proyecto y no es un secreto. La protección de datos depende de las reglas anteriores, no de ocultar esa configuración.

## Datos demo

`LoadDemoData` escribe en la colección del propio usuario autenticado, en un `WriteBatch` cuyos documentos cumplen las mismas reglas que las escrituras individuales.

## Entrada de datos

- Los importes se validan con `parseEurosToCents` (formato y límite) antes de crear la transacción.
- Las descripciones se recortan con `trim()` y se limitan a 200 caracteres en el formulario, en el dominio y en las reglas.

## Pendiente

- **Pendiente de decisión antes de la entrega (26/10):** registro con email y contraseña. Opciones:
  1. Dejarlo abierto y documentarlo como límite conocido (ya descrito arriba).
  2. Cerrar el alta en la consola de Firebase (desactivar el proveedor de email/contraseña para nuevos usuarios o deshabilitar el registro), comprobando antes que el inicio de sesión sigue funcionando.
- Tests automatizados de las reglas (ahora se verifican manualmente contra el emulador).
- Revisión de dependencias antes de la entrega.
- Exigir correo verificado en las reglas de Firestore.