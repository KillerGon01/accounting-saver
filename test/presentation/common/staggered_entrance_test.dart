import 'package:accounting_saver/presentation/common/staggered_entrance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child, {bool disableAnimations = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('aparece tras su retraso (opacidad 0 al montar, 1 tras el tiempo)', (tester) async {
    await _pump(tester, const StaggeredEntrance(index: 1, child: Text('tarjeta')));

    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0);

    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
    expect(find.text('tarjeta'), findsOneWidget);
  });

  testWidgets('con disableAnimations, visible desde el primer frame', (tester) async {
    await _pump(
      tester,
      const StaggeredEntrance(index: 3, child: Text('tarjeta')),
      disableAnimations: true,
    );

    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
  });

  testWidgets('el retraso tiene un tope: el índice 8 y el 20 tardan lo mismo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: const [
              StaggeredEntrance(index: StaggeredEntrance.maxStaggeredIndex, child: Text('en el tope')),
              StaggeredEntrance(index: 20, child: Text('por encima del tope')),
            ],
          ),
        ),
      ),
    );

    // Justo tras el retraso del tope (320 ms = 40 ms × 8): si el índice
    // 20 esperase más que el tope (800 ms), a esta altura solo habría
    // aparecido el primero.
    await tester.pump(const Duration(milliseconds: 325));

    expect(
      tester.widget<AnimatedOpacity>(find.ancestor(of: find.text('en el tope'), matching: find.byType(AnimatedOpacity))).opacity,
      1,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(find.ancestor(of: find.text('por encima del tope'), matching: find.byType(AnimatedOpacity)))
          .opacity,
      1,
    );

    await tester.pumpAndSettle();
  });

  testWidgets('el temporizador se cancela si el widget se destruye antes de disparar', (tester) async {
    await _pump(tester, const StaggeredEntrance(index: 5, child: Text('tarjeta')));

    // Se quita del árbol antes de que cumpla su retraso (200 ms): si el
    // temporizador no se cancelara en `dispose`, `flutter_test` falla la
    // prueba al final con "A Timer is still pending" en vez de con esta
    // aserción.
    await _pump(tester, const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('tarjeta'), findsNothing);
  });
}
