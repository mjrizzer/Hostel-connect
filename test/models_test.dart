import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_connect/core/models.dart';

void main() {
  test('hostel weekday rolls over at midnight in Kolkata', () {
    final time = hostelNow(DateTime.utc(2026, 10, 21, 18, 31));
    expect(dateKey(time), '2026-10-22');
    expect(weekdays[time.weekday - 1], 'Thursday');
  });
  test('correct building display label', () {
    expect(buildingName('KENNEDY'), 'Kennedy');
    expect(buildingName('HS1'), 'HS1');
  });
}
