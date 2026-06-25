import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_gps_codex/main.dart';

void main() {
  testWidgets('GPS tracker home renders main controls', (tester) async {
    await tester.pumpWidget(const GpsTrackerApp());

    expect(find.text('Seguimiento GPS'), findsOneWidget);
    expect(find.text('Primer plano'), findsOneWidget);
    expect(find.text('Segundo plano'), findsOneWidget);
    expect(find.text('Ultima ubicacion'), findsOneWidget);
    expect(find.text('Historial de seguimiento'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Seguir con GPS'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Limpiar registros y contadores'),
      findsOneWidget,
    );
  });
}
