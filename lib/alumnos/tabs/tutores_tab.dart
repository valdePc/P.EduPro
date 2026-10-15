import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TutoresTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;

  const TutoresTab({
    super.key,
    required this.estRef,
  });

  static const Color _blue = Color(0xFF0D47A1);
  static const Color _orange = Color(0xFFFFA000);

  String _text(dynamic value) => (value ?? '').toString().trim();

  String _fallback(String value, {String empty = 'No registrado'}) {
    return value.isEmpty ? empty : value;
  }

  Future<void> _openUri(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }

  String _digits(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.startsWith('00')) return '+${cleaned.substring(2)}';
    return cleaned;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: estRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _StateCard(
                icon: Icons.error_outline_rounded,
                title: 'No se pudo cargar la informacion',
                subtitle: '${snapshot.error}',
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!.data() ?? const <String, dynamic>{};
        final tutor = (data['tutor'] is Map<String, dynamic>)
            ? data['tutor'] as Map<String, dynamic>
            : <String, dynamic>{};
        final emergencia = (data['emergencia'] is Map<String, dynamic>)
            ? data['emergencia'] as Map<String, dynamic>
            : <String, dynamic>{};

        final tutorNombre = _text(tutor['nombre']);
        final tutorParentesco = _text(tutor['parentesco']);
        final tutorTelefono = _text(tutor['telefono']);
        final tutorWhatsapp = _text(tutor['whatsapp']);
        final tutorEmail = _text(tutor['email']);
        final direccion = _text(data['direccion']);
        final nota = _text(data['observaciones']);
        final emergenciaNombre = _text(emergencia['nombre']);
        final emergenciaTelefono = _text(emergencia['telefono']);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(10),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(0x14FFA000),
                    child: Icon(
                      Icons.family_restroom_rounded,
                      color: _orange,
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tutores y contactos',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Informacion del tutor principal y datos de contacto registrados al momento de crear el alumno.',
                          style: TextStyle(height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _SectionCard(
              title: 'Tutor principal',
              icon: Icons.person_rounded,
              children: [
                _InfoRow(
                  label: 'Nombre',
                  value: _fallback(tutorNombre),
                ),
                _InfoRow(
                  label: 'Parentesco',
                  value: _fallback(tutorParentesco),
                ),
              ],
            ),
            _SectionCard(
              title: 'Contacto',
              icon: Icons.phone_in_talk_rounded,
              children: [
                _InfoRow(
                  label: 'Telefono',
                  value: _fallback(tutorTelefono),
                  actions: tutorTelefono.isEmpty
                      ? const []
                      : [
                          _InfoAction(
                            label: 'Llamar',
                            icon: Icons.call_rounded,
                            onTap: () => _openUri('tel:${_digits(tutorTelefono)}'),
                          ),
                        ],
                ),
                _InfoRow(
                  label: 'WhatsApp',
                  value: _fallback(tutorWhatsapp),
                  actions: tutorWhatsapp.isEmpty
                      ? const []
                      : [
                          _InfoAction(
                            label: 'WhatsApp',
                            icon: Icons.chat_rounded,
                            onTap: () => _openUri(
                              'https://wa.me/${_digits(tutorWhatsapp).replaceAll('+', '')}',
                            ),
                          ),
                        ],
                ),
                _InfoRow(
                  label: 'Correo electronico',
                  value: _fallback(tutorEmail),
                  actions: tutorEmail.isEmpty
                      ? const []
                      : [
                          _InfoAction(
                            label: 'Correo',
                            icon: Icons.mail_rounded,
                            onTap: () => _openUri('mailto:$tutorEmail'),
                          ),
                        ],
                ),
                _InfoRow(
                  label: 'Direccion',
                  value: _fallback(direccion),
                  multiline: true,
                ),
              ],
            ),
            _SectionCard(
              title: 'Contacto de emergencia',
              icon: Icons.emergency_rounded,
              children: [
                _InfoRow(
                  label: 'Nombre',
                  value: _fallback(emergenciaNombre),
                ),
                _InfoRow(
                  label: 'Telefono',
                  value: _fallback(emergenciaTelefono),
                  actions: emergenciaTelefono.isEmpty
                      ? const []
                      : [
                          _InfoAction(
                            label: 'Llamar',
                            icon: Icons.call_rounded,
                            onTap: () =>
                                _openUri('tel:${_digits(emergenciaTelefono)}'),
                          ),
                        ],
                ),
              ],
            ),
            _SectionCard(
              title: 'Nota',
              icon: Icons.sticky_note_2_rounded,
              children: [
                _InfoRow(
                  label: 'Observaciones',
                  value: _fallback(nota),
                  multiline: true,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0x140D47A1),
                child: Icon(icon, size: 18, color: TutoresTab._blue),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;
  final List<_InfoAction> actions;

  const _InfoRow({
    required this.label,
    required this.value,
    this.multiline = false,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              height: multiline ? 1.4 : 1.2,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions
                  .map(
                    (action) => OutlinedButton.icon(
                      onPressed: action.onTap,
                      icon: Icon(action.icon, size: 16),
                      label: Text(action.label),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TutoresTab._blue,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _InfoAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _StateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: Colors.grey.shade700),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, height: 1.35),
          ),
        ],
      ),
    );
  }
}
