import 'package:edupro/utils/equipo_edupro_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alwaysOpen = <String, dynamic>{
    'enabled': true,
    'allowedWeekdays': [1, 2, 3, 4, 5, 6, 7],
    'startMinute': 0,
    'endMinute': 1439,
  };

  test('24/7 allows every minute of all seven days, including second 59', () {
    // Each supplied instant represents the requested local Dominican minute.
    for (var day = 5; day <= 11; day++) {
      for (var minute = 0; minute < 1440; minute++) {
        for (final second in [0, 59]) {
          final now = DateTime.utc(
            2026,
            10,
            day,
            minute ~/ 60 + 4,
            minute % 60,
            second,
          );
          expect(
            EquipoEduProAccess.isAllowedNow(alwaysOpen, now: now),
            isTrue,
            reason: now.toIso8601String(),
          );
        }
      }
    }
  });

  test('A disabled account remains denied with a 24/7 schedule', () {
    final disabled = <String, dynamic>{...alwaysOpen, 'enabled': false};
    for (var day = 5; day <= 11; day++) {
      for (final minute in [0, 720, 1439]) {
        final now = DateTime.utc(
          2026,
          10,
          day,
          minute ~/ 60 + 4,
          minute % 60,
          59,
        );
        expect(EquipoEduProAccess.isAllowedNow(disabled, now: now), isFalse);
      }
    }
  });

  test('A normal weekday account keeps its day and time restrictions', () {
    const businessHours = <String, dynamic>{
      'enabled': true,
      'allowedWeekdays': [1, 2, 3, 4, 5],
      'startMinute': 8 * 60,
      'endMinute': 18 * 60,
    };
    for (var day = 5; day <= 11; day++) {
      final weekday = DateTime.utc(2026, 10, day).weekday <= DateTime.friday;
      for (final minute in [0, 479, 480, 720, 1080, 1081, 1439]) {
        final now = DateTime.utc(
          2026,
          10,
          day,
          minute ~/ 60 + 4,
          minute % 60,
          59,
        );
        expect(
          EquipoEduProAccess.isAllowedNow(businessHours, now: now),
          weekday && minute >= 480 && minute <= 1080,
          reason: now.toIso8601String(),
        );
      }
    }
  });

  test('An overnight schedule keeps the interval across midnight', () {
    final overnight = <String, dynamic>{
      ...alwaysOpen,
      'startMinute': 22 * 60,
      'endMinute': 6 * 60,
    };
    for (final minute in [0, 359, 360, 361, 720, 1319, 1320, 1439]) {
      final now = DateTime.utc(2026, 10, 5, minute ~/ 60 + 4, minute % 60, 59);
      expect(
        EquipoEduProAccess.isAllowedNow(overnight, now: now),
        minute <= 360 || minute >= 1320,
        reason: now.toIso8601String(),
      );
    }
  });
}
