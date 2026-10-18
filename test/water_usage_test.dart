import 'package:flutter_test/flutter_test.dart';
import 'package:irrigation_monitor/main.dart';

void main() {
  IrrigationReading reading({
    required double baseline,
    required double automated,
    double fieldA = 40,
    double fieldB = 45,
    double threshold = 35,
  }) =>
      IrrigationReading(
        moisture: fieldA,
        fieldBMoisture: fieldB,
        threshold: threshold,
        pumpOn: false,
        valveAOpen: false,
        valveBOpen: false,
        automaticMode: true,
        waterToday: 10,
        baselineWater: baseline,
        automatedWater: automated,
        updatedAt: DateTime(2026),
      );

  test('reports water saved when automated use is lower', () {
    final result = reading(baseline: 42, automated: 25);

    expect(result.waterSavedPerDay, 17);
    expect(result.waterSavedPercent, 40);
  });

  test('reports negative savings when automated use is higher', () {
    final result = reading(baseline: 30, automated: 36);

    expect(result.waterSavedPerDay, -6);
    expect(result.waterSavedPercent, -20);
  });

  test('avoids dividing by zero when no baseline is recorded', () {
    final result = reading(baseline: 0, automated: 12);

    expect(result.waterSavedPerDay, -12);
    expect(result.waterSavedPercent, isNull);
  });

  test('alerts only for fields that newly cross below the threshold', () {
    final previous = reading(baseline: 42, automated: 25);
    final current = reading(
      baseline: 42,
      automated: 25,
      fieldA: 34,
      fieldB: 30,
    );

    expect(
      newlyDryFields(previous: previous, current: current),
      ['A', 'B'],
    );
  });

  test('does not repeat alerts while a field remains dry', () {
    final previous = reading(
      baseline: 42,
      automated: 25,
      fieldA: 30,
    );
    final current = reading(
      baseline: 42,
      automated: 25,
      fieldA: 29,
    );

    expect(newlyDryFields(previous: previous, current: current), isEmpty);
  });

  test('does not alert on initial readings or threshold edits', () {
    final initial = reading(baseline: 42, automated: 25, fieldA: 30);
    final thresholdChanged = reading(
      baseline: 42,
      automated: 25,
      fieldA: 30,
      threshold: 25,
    );

    expect(newlyDryFields(previous: null, current: initial), isEmpty);
    expect(
      newlyDryFields(previous: initial, current: thresholdChanged),
      isEmpty,
    );
  });
}
