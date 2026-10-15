/// Presentation metadata only. It never grants school access.
class SchoolAdministratorDetails {
  final bool assigned;
  final String name;
  final String email;

  const SchoolAdministratorDetails._(this.assigned, this.name, this.email);

  factory SchoolAdministratorDetails.fromMap(Map<String, dynamic> data) {
    String text(String key) =>
        data[key] is String ? (data[key] as String).trim() : '';
    final email = text('adminEmail');
    final name = text('adminName');
    final assigned =
        data['adminAssigned'] is bool
            ? data['adminAssigned'] as bool
            : email.isNotEmpty || (name.isNotEmpty && name != 'No asignado');
    return SchoolAdministratorDetails._(
      assigned,
      assigned
          ? (name.isEmpty || name == 'No asignado'
              ? 'Administrador asignado'
              : name)
          : 'No asignado',
      email,
    );
  }

  String get emailLabel =>
      email.isNotEmpty
          ? email
          : assigned
          ? 'Correo no registrado'
          : 'Sin asignar';
}
