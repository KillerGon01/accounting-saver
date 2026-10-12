import 'package:accounting_saver/infrastructure/chat/gemini_chat_gateway.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_clock.dart';

void main() {
  group('functionResponsesContent', () {
    test('no usa el rol "function" (el backend ya no lo acepta)', () {
      final content = functionResponsesContent([
        FunctionResponse('getMonthlySummary', {'incomeCents': 1000}),
      ]);

      expect(content.role, isNot('function'));
    });

    test('conserva el nombre y el mapa de resultado de cada función', () {
      final content = functionResponsesContent([
        FunctionResponse('getMonthlySummary', {'incomeCents': 1000, 'expenseCents': 500}),
      ]);

      final part = content.parts.single as FunctionResponse;
      expect(part.name, 'getMonthlySummary');
      expect(part.response, {'incomeCents': 1000, 'expenseCents': 500});
    });

    test('agrupa varias respuestas en un único Content, en el mismo orden', () {
      final content = functionResponsesContent([
        FunctionResponse('getMonthlySummary', {'incomeCents': 1000}),
        FunctionResponse('listTransactions', {'transactions': []}),
      ]);

      expect(content.parts, hasLength(2));
      final names = content.parts.map((p) => (p as FunctionResponse).name).toList();
      expect(names, ['getMonthlySummary', 'listTransactions']);
    });

    test('usa un rol válido para el backend (uno de los que acepta: user)', () {
      final content = functionResponsesContent([
        FunctionResponse('getMonthlySummary', {'incomeCents': 1000}),
      ]);

      expect(content.role, 'user');
    });
  });

  group('buildChatSystemInstruction', () {
    test('resuelve este mes y el mes pasado a partir del reloj', () {
      final instruction = buildChatSystemInstruction(FakeClock(DateTime(2026, 10, 8)));

      expect(instruction, contains('Hoy es jueves, 8 de octubre de 2026.'));
      expect(instruction, contains('Este mes es octubre de 2026 (year=2026, month=10).'));
      expect(instruction, contains('El mes pasado es septiembre de 2026 (year=2026, month=9).'));
      expect(instruction, contains('Este año es 2026.'));
    });

    test('el mes pasado cruza al año anterior en enero', () {
      final instruction = buildChatSystemInstruction(FakeClock(DateTime(2027, 1, 15)));

      expect(instruction, contains('Este mes es enero de 2027 (year=2027, month=1).'));
      expect(instruction, contains('El mes pasado es diciembre de 2026 (year=2026, month=12).'));
      expect(instruction, contains('Este año es 2027.'));
    });

    test('nunca pregunta por el mes o el año: pide usar los valores resueltos', () {
      final instruction = buildChatSystemInstruction(FakeClock(DateTime(2026, 10, 8)));

      expect(instruction, contains('nunca preguntes al usuario por el año o el mes'));
      expect(instruction, contains('llama siempre a la función adecuada'));
    });

    test(
      'distingue CANTIDAD de LISTADO: "qué ingresos/gastos tengo" no es lo mismo que '
      '"cuánto he gastado/ingresado", aunque las dos usen la misma palabra',
      () {
        final instruction = buildChatSystemInstruction(FakeClock(DateTime(2026, 10, 8)));

        expect(instruction, contains('CANTIDAD'));
        expect(instruction, contains('LISTADO'));
        expect(instruction, contains('qué ingresos tengo'));
        expect(
          instruction,
          contains('Las palabras "ingresos" o\n"gastos" no deciden esto por sí solas'),
        );
        expect(instruction, contains('Para una cantidad usa getMonthlySummary'));
        expect(instruction, contains('para un listado usa listTransactions'));
      },
    );

    test(
      'avisa de que listTransactions no filtra por tipo: el modelo debe elegir él '
      'qué líneas de transactionLines mostrar',
      () {
        final instruction = buildChatSystemInstruction(FakeClock(DateTime(2026, 10, 8)));

        expect(instruction, contains('esa\nfunción no filtra por tipo de movimiento'));
      },
    );
  });

  group('chatFunctionDeclarations', () {
    FunctionDeclaration declarationFor(String name) =>
        chatFunctionDeclarations().firstWhere((d) => d.name == name);

    test('getMonthlySummary se describe para preguntas de cantidad, no de listado', () {
      final description = declarationFor('getMonthlySummary').description;

      expect(description, contains('CANTIDAD'));
      expect(description, contains('No la uses si el usuario pide ver los movimientos uno por'));
      expect(description, contains('qué ingresos tengo'));
      expect(description, contains('listTransactions'));
    });

    test(
      'listTransactions se describe para preguntas de listado, incluidas '
      '"qué ingresos/gastos tengo", y avisa de que no filtra por tipo',
      () {
        final description = declarationFor('listTransactions').description;

        expect(description, contains('LISTADO'));
        expect(description, contains('qué '
            'ingresos tengo en octubre'));
        expect(description, contains('No filtra por ingreso/gasto (no existe ese'));
        expect(description, contains('"(ingreso)"'));
        expect(description, contains('"(gasto)"'));
      },
    );

    test('declara las cinco funciones del chat, cada una una sola vez', () {
      final names = chatFunctionDeclarations().map((d) => d.name).toList();

      expect(names.toSet().length, names.length);
      expect(names.toSet(), {
        'getMonthlySummary',
        'getCategoryBreakdown',
        'compareMonths',
        'listTransactions',
        'recurringExpenses',
      });
    });
  });
}
