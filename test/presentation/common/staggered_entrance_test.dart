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

    // Right after the capped delay (320 ms = 40 ms × 8): if index 20
    // waited longer than the cap (800 ms), only the first one would
    // have appeared by now.
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

    // Removed from the tree before its delay (200 ms) elapses: if the
    // timer weren't cancelled in `dispose`, `flutter_test` would fail
    // the test at the end with "A Timer is still pending" instead of
    // with this assertion.
    await _pump(tester, const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('tarjeta'), findsNothing);
  });
}
