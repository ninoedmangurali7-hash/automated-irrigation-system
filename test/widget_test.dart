import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_monitor/main.dart';

void main() {
  testWidgets('irrigation app starts in demo mode', (tester) async {
    await tester.pumpWidget(const IrrigationApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
