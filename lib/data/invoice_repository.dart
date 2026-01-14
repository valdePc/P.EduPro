// lib/data/invoice_repository.dart
import 'package:edupro/models/invoice.dart';

class InvoiceRepository {
  // Repositorio en memoria
  static final List<Invoice> invoices = [];

  static void add(Invoice inv) => invoices.add(inv);
  static void remove(Invoice inv) => invoices.remove(inv);
  static void clear() => invoices.clear();
}
