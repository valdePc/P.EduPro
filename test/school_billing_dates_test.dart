import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edupro/models/school_billing_dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'payment confirmation replaces the initial renewal in the displayed date',
    () {
      final initial = DateTime(2026, 10, 8);
      final paid = DateTime(2026, 10, 20);
      final due = DateTime(2026, 11, 20);
      final school = <String, dynamic>{
        'renewalAt': Timestamp.fromDate(initial),
      };
      expect(SchoolBillingDates.fromMap(school).renewalAt, initial);

      // These are the two fields changed by the payment confirmation transaction.
      school.addAll({
        'billingLastPaidAt': Timestamp.fromDate(paid),
        'billingNextDueAt': Timestamp.fromDate(due),
      });
      final updated = SchoolBillingDates.fromMap(school);
      expect(updated.renewalAt, due);
      expect(updated.renewalAt, updated.nextDueAt);
      expect(updated.lastPaidAt, paid);
      expect(school['renewalAt'], Timestamp.fromDate(initial));
    },
  );

  test(
    'renewal estimates and submitted reports are not confirmed payments',
    () {
      final initial = DateTime(2026, 10, 8);
      final legacy = SchoolBillingDates.fromMap({
        'renewalAt': Timestamp.fromDate(initial),
        'lastPaymentAt': Timestamp.fromDate(DateTime(2026, 9, 20)),
      });
      expect(legacy.renewalAt, initial);
      expect(legacy.nextDueAt, isNull);
      expect(legacy.lastPaidAt, isNull);
      final missing = SchoolBillingDates.fromMap({});
      expect(missing.renewalAt, isNull);
      expect(missing.lastPaidAt, isNull);
    },
  );

  test(
    'dates from Firestore, callable catalogs and DateTime have the same result',
    () {
      final due = DateTime(2026, 11, 20);
      final paid = DateTime(2026, 10, 20);
      for (final value in [
        Timestamp.fromDate(due),
        due,
        due.millisecondsSinceEpoch,
      ]) {
        final dates = SchoolBillingDates.fromMap({
          'billingNextDueAt': value,
          'billingLastPaidAt': paid,
          'renewalAt': Timestamp.fromDate(DateTime(2026, 10, 8)),
        });
        expect(dates.renewalAt, due);
        expect(dates.lastPaidAt, paid);
      }
    },
  );

  test('invalid or absent date values do not invent confirmation dates', () {
    final dates = SchoolBillingDates.fromMap({
      'billingNextDueAt': 'invalid',
      'billingLastPaidAt': false,
      'renewalAt': null,
    });
    expect(dates.nextDueAt, isNull);
    expect(dates.lastPaidAt, isNull);
    expect(dates.renewalAt, isNull);
  });
}
