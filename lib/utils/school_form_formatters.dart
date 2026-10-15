import 'package:flutter/services.dart';

/// Pone en mayúscula el inicio de cada palabra sin alterar siglas ya escritas.
class SchoolNameCapitalizationFormatter extends TextInputFormatter {
  const SchoolNameCapitalizationFormatter();

  static final _wordStart = RegExp(r'(^|[\s\-(/])([a-záéíóúüñ])');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final formatted = newValue.text.replaceAllMapped(
      _wordStart,
      (match) => '${match.group(1)}${match.group(2)!.toUpperCase()}',
    );
    return newValue.copyWith(text: formatted);
  }
}

/// Formatea teléfonos dominicanos al escribir; conserva el prefijo internacional.
class SchoolPhoneFormatter extends TextInputFormatter {
  const SchoolPhoneFormatter();

  static String format(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    final international = input.trimLeft().startsWith('+');
    if (digits.length <= 10 && !international) return _national(digits);
    if (digits.startsWith('1') &&
        digits.length <= 11 &&
        (international || digits.length > 10)) {
      return '+1 ${_national(digits.substring(1))}'.trimRight();
    }
    // Un número de otro país requiere su propio plan de marcación; no adivinarlo.
    return international ? '+$digits' : digits;
  }

  static String _national(String digits) {
    if (digits.length <= 3) return digits;
    final area = digits.substring(0, 3);
    final rest = digits.substring(3);
    if (rest.length <= 3) return '($area) $rest';
    return '($area) ${rest.substring(0, 3)}-${rest.substring(3)}';
  }

  static String? validate(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10 ||
        (digits.length == 11 && digits.startsWith('1'))) {
      return null;
    }
    if (raw.startsWith('+') && digits.length >= 8 && digits.length <= 15) {
      return null;
    }
    return 'Usa 10 dígitos o +código internacional';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final raw = newValue.text;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 15) return oldValue;
    final beforeCaret = raw.substring(
      0,
      newValue.selection.extentOffset.clamp(0, raw.length),
    );
    final digitPosition = beforeCaret.replaceAll(RegExp(r'\D'), '').length;
    final formatted = format(raw);
    var caret = formatted.length;
    if (digitPosition < digits.length) {
      var count = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (RegExp(r'\d').hasMatch(formatted[i])) count++;
        if (count == digitPosition) {
          caret = i + 1;
          break;
        }
      }
    }
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: caret),
    );
  }
}
