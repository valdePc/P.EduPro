import 'package:flutter/material.dart';

@immutable
class SchoolPlanValues {
  final String planTier;
  final int adminsLimit;
  final int teachersLimit;
  final int studentsLimit;

  const SchoolPlanValues(
    this.planTier,
    this.adminsLimit,
    this.teachersLimit,
    this.studentsLimit,
  );

  static SchoolPlanValues defaultsFor(String plan) => switch (plan
      .trim()
      .toLowerCase()) {
    'plus' => const SchoolPlanValues('plus', 3, 25, 300),
    'premium' => const SchoolPlanValues('premium', 5, 60, 900),
    'enterprise' => const SchoolPlanValues('enterprise', 10, 150, 3000),
    _ => const SchoolPlanValues('base', 1, 10, 150),
  };
}

/// The text shown in the fields is also the source of the submitted limits.
class SchoolPlanController extends ChangeNotifier {
  final admins = TextEditingController(text: '1');
  final teachers = TextEditingController(text: '10');
  final students = TextEditingController(text: '150');
  String _planTier = 'base';

  String get planTier => _planTier;

  void selectPlan(String plan) {
    final values = SchoolPlanValues.defaultsFor(plan);
    if (values.planTier == _planTier) return;
    _planTier = values.planTier;
    admins.text = '${values.adminsLimit}';
    teachers.text = '${values.teachersLimit}';
    students.text = '${values.studentsLimit}';
    notifyListeners();
  }

  static String? validateLimit(String? text, int maximum) {
    final value = int.tryParse((text ?? '').trim());
    if (value == null || value < 1) return 'Introduce un entero mayor que cero';
    if (value > maximum) return 'Máximo $maximum';
    return null;
  }

  SchoolPlanValues readValues() {
    int read(TextEditingController controller, int maximum) {
      if (validateLimit(controller.text, maximum) != null) {
        throw const FormatException('Revisa los límites del colegio.');
      }
      return int.parse(controller.text.trim());
    }

    return SchoolPlanValues(
      _planTier,
      read(admins, 1000),
      read(teachers, 100000),
      read(students, 1000000),
    );
  }

  @override
  void dispose() {
    admins.dispose();
    teachers.dispose();
    students.dispose();
    super.dispose();
  }
}

class SchoolPlanSelector extends StatelessWidget {
  final SchoolPlanController controller;
  final bool editable;

  const SchoolPlanSelector({
    super.key,
    required this.controller,
    required this.editable,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder:
        (context, _) => DropdownButtonFormField<String>(
          key: ValueKey(controller.planTier),
          initialValue: controller.planTier,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Plan',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'base', child: Text('Base')),
            DropdownMenuItem(value: 'plus', child: Text('Plus')),
            DropdownMenuItem(value: 'premium', child: Text('Premium')),
            DropdownMenuItem(value: 'enterprise', child: Text('Enterprise')),
          ],
          onChanged:
              editable
                  ? (value) {
                    if (value != null) controller.selectPlan(value);
                  }
                  : null,
        ),
  );
}

class SchoolPlanLimitFields extends StatelessWidget {
  final SchoolPlanController controller;
  final bool editable;

  const SchoolPlanLimitFields({
    super.key,
    required this.controller,
    required this.editable,
  });

  Widget _field(
    String key,
    String label,
    TextEditingController text,
    int maximum,
  ) => TextFormField(
    key: ValueKey(key),
    controller: text,
    readOnly: !editable,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: (value) => SchoolPlanController.validateLimit(value, maximum),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: _field(
              'school-admins-limit',
              'Límite admin escolar',
              controller.admins,
              1000,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _field(
              'school-teachers-limit',
              'Límite docentes',
              controller.teachers,
              100000,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _field(
        'school-students-limit',
        'Límite alumnos',
        controller.students,
        1000000,
      ),
    ],
  );
}
