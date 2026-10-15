import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads billing dates without inferring payment confirmation from renewalAt.
class SchoolBillingDates {
  final DateTime? nextDueAt;
  final DateTime? lastPaidAt;
  final DateTime? initialRenewalAt;

  const SchoolBillingDates._({
    required this.nextDueAt,
    required this.lastPaidAt,
    required this.initialRenewalAt,
  });

  factory SchoolBillingDates.fromMap(Map<String, dynamic> data) {
    DateTime? date(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      return null;
    }

    return SchoolBillingDates._(
      nextDueAt: date(data['billingNextDueAt']),
      lastPaidAt: date(data['billingLastPaidAt']),
      initialRenewalAt: date(data['renewalAt']),
    );
  }

  /// The confirmed billing schedule takes precedence over the initial estimate.
  DateTime? get renewalAt => nextDueAt ?? initialRenewalAt;
}
