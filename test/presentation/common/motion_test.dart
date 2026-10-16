import 'package:accounting_saver/presentation/common/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppMotion.of devuelve la duración pedida si las animaciones están activas', (tester) async {
    late Duration result;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              result = AppMotion.of(context, AppMotion.base);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(result, AppMotion.base);
  });

  testWidgets('AppMotion.of devuelve Duration.zero si disableAnimations está activo', (tester) async {
    late Duration result;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              result = AppMotion.of(context, AppMotion.base);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(result, Duration.zero);
  });
}
