'use strict';

const { before, after, test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'demo-accounting-saver';

// El firestore.rules REAL de la raíz del repositorio, no una copia: si
// alguien cambia las reglas y no actualiza esta carpeta, estas pruebas
// siguen leyendo el archivo de verdad.
const RULES_PATH = path.resolve(__dirname, '..', 'firestore.rules');

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

function validTransaction(overrides = {}) {
  return {
    amountCents: -500,
    date: new Date('2026-10-01T00:00:00Z'),
    description: 'Café',
    categoryId: 'restaurantes',
    source: 'manual',
    createdAt: new Date('2026-10-01T00:00:00Z'),
    ...overrides,
  };
}

test('usuario verificado puede leer, escribir y borrar su propio movimiento', async () => {
  const alice = testEnv.authenticatedContext('alice', { email_verified: true });
  const doc = alice.firestore().collection('users/alice/transactions').doc('t1');

  await assertSucceeds(doc.set(validTransaction()));
  await assertSucceeds(doc.get());
  await assertSucceeds(doc.update({ description: 'Café con Marta' }));
  await assertSucceeds(doc.delete());
});

test('usuario sin verificar no puede leer ni escribir, aunque sea el dueño', async () => {
  const bob = testEnv.authenticatedContext('bob', { email_verified: false });
  const doc = bob.firestore().collection('users/bob/transactions').doc('t1');

  await assertFails(doc.set(validTransaction()));
  await assertFails(doc.get());
});

test('otro usuario verificado no puede leer ni escribir los movimientos de alice', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context
      .firestore()
      .collection('users/alice/transactions')
      .doc('seed')
      .set(validTransaction());
  });

  const mallory = testEnv.authenticatedContext('mallory', { email_verified: true });
  const aliceTransactions = mallory.firestore().collection('users/alice/transactions');

  await assertFails(aliceTransactions.doc('seed').get());
  await assertFails(aliceTransactions.doc('nuevo').set(validTransaction()));
});

test('sin sesión no se puede leer ni escribir nada', async () => {
  const anon = testEnv.unauthenticatedContext();
  const doc = anon.firestore().collection('users/alice/transactions').doc('t1');

  await assertFails(doc.get());
  await assertFails(doc.set(validTransaction()));
});

test('campos inválidos o importe fuera de rango se rechazan aunque esté verificado', async () => {
  const alice = testEnv.authenticatedContext('alice', { email_verified: true });
  const transactions = alice.firestore().collection('users/alice/transactions');

  await assertFails(transactions.doc('importe-cero').set(validTransaction({ amountCents: 0 })));
  await assertFails(
    transactions.doc('importe-excesivo').set(validTransaction({ amountCents: 100000001 })),
  );
  await assertFails(
    transactions.doc('importe-decimal').set(validTransaction({ amountCents: 12.5 })),
  );
  await assertFails(
    transactions.doc('categoria-invalida').set(validTransaction({ categoryId: 'no-existe' })),
  );
  await assertFails(transactions.doc('origen-invalido').set(validTransaction({ source: 'otro' })));
  await assertFails(
    transactions.doc('descripcion-vacia').set(validTransaction({ description: '' })),
  );

  const sinDescripcion = validTransaction();
  delete sinDescripcion.description;
  await assertFails(transactions.doc('falta-un-campo').set(sinDescripcion));

  await assertFails(
    transactions.doc('campo-no-previsto').set({ ...validTransaction(), extra: 'no debería estar' }),
  );
});

test('colecciones no previstas se deniegan, dentro y fuera de users/{uid}', async () => {
  const alice = testEnv.authenticatedContext('alice', { email_verified: true });
  const db = alice.firestore();

  await assertFails(db.collection('users/alice/otraColeccion').doc('x').set({ a: 1 }));
  await assertFails(db.collection('coleccionSuelta').doc('x').set({ a: 1 }));
});
