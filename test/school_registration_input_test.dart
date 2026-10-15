import 'package:edupro/data/dominican_locations.dart';
import 'package:edupro/utils/school_form_formatters.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catálogo cubre las demarcaciones y municipios sin duplicados', () {
    expect(dominicanMunicipalitiesByProvince.length, 32);
    expect(
      dominicanMunicipalitiesByProvince.values.fold<int>(
        0,
        (count, municipalities) => count + municipalities.length,
      ),
      158,
    );
    for (final municipalities in dominicanMunicipalitiesByProvince.values) {
      expect(municipalities.toSet().length, municipalities.length);
    }
    expect(
      dominicanMunicipalitiesByProvince['Santo Domingo'],
      contains('Boca Chica'),
    );
    expect(dominicanMunicipalitiesByProvince['Distrito Nacional'], [
      'Santo Domingo de Guzmán',
    ]);
    expect(
      dominicanMunicipalitiesByProvince['Azua'],
      isNot(contains('Boca Chica')),
    );
  });

  test('capitaliza palabras pegadas y conserva siglas', () {
    const formatter = SchoolNameCapitalizationFormatter();
    final entered = TextEditingValue(
      text: 'colegio san josé (MINERD)',
      selection: const TextSelection.collapsed(offset: 24),
    );
    final result = formatter.formatEditUpdate(TextEditingValue.empty, entered);
    expect(result.text, 'Colegio San José (MINERD)');
    expect(result.selection.extentOffset, entered.selection.extentOffset);
  });

  test('formatea teléfonos dominicanos consecutivos y valida extensión', () {
    expect(SchoolPhoneFormatter.format('8095551234'), '(809) 555-1234');
    expect(SchoolPhoneFormatter.format('+18095551234'), '+1 (809) 555-1234');
    expect(SchoolPhoneFormatter.validate('8095551234'), isNull);
    expect(SchoolPhoneFormatter.validate('80955512'), isNotNull);
  });

  test('mantiene el cursor al insertar en medio de un teléfono', () {
    const formatter = SchoolPhoneFormatter();
    final result = formatter.formatEditUpdate(
      const TextEditingValue(text: '(809) 555-1234'),
      const TextEditingValue(
        text: '(809) 6555-1234',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    expect(result.selection.extentOffset, lessThan(result.text.length));
  });
}
