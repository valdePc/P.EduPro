import 'package:flutter/material.dart';

abstract final class AdminNotificationColors {
  static const blue = Color(0xFF1A237E);
  static const ink = Color(0xFF17243A);
  static const muted = Color(0xFF536174);
  static const page = Color(0xFFF4F6FB);
  static const border = Color(0xFFE1E7F0);
  static const amberInk = Color(0xFF805000);
}

class AdminNotificationHero extends StatelessWidget {
  final String schoolName;

  const AdminNotificationHero({super.key, required this.schoolName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AdminNotificationColors.blue, Color(0xFF3949AB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Centro de notificaciones',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Envía avisos a tu comunidad escolar y consulta los mensajes enviados.',
            style: TextStyle(
              color: Color(0xFFE9ECFF),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          if (schoolName.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              schoolName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AdminNotificationHistoryCard extends StatelessWidget {
  final String title;
  final String body;
  final String date;
  final String target;
  final String include;
  final int readCount;
  final VoidCallback onTap;

  const AdminNotificationHistoryCard({
    super.key,
    required this.title,
    required this.body,
    required this.date,
    required this.target,
    required this.include,
    required this.readCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AdminNotificationColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEFFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: AdminNotificationColors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? 'Notificación' : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdminNotificationColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                    if (date.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        date,
                        style: const TextStyle(
                          color: AdminNotificationColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      body.isEmpty
                          ? 'Abre la notificación para ver sus detalles.'
                          : body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdminNotificationColors.ink,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _tag(
                          target,
                          AdminNotificationColors.blue,
                          const Color(0xFFEDEFFF),
                        ),
                        if (include.isNotEmpty)
                          _tag(
                            include,
                            AdminNotificationColors.amberInk,
                            const Color(0xFFFFF2D4),
                          ),
                        _tag(
                          'Leídas por $readCount',
                          AdminNotificationColors.muted,
                          const Color(0xFFF0F3F7),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: AdminNotificationColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, Color foreground, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );
  }
}

class AdminNotificationEmptyState extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;

  const AdminNotificationEmptyState({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.notifications_none_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminNotificationColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: AdminNotificationColors.blue, size: 32),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AdminNotificationColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AdminNotificationColors.muted,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminNotificationDeleteDialog extends StatelessWidget {
  const AdminNotificationDeleteDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Eliminar notificación'),
      content: const Text(
        'El aviso dejará de estar disponible para sus destinatarios. ¿Deseas eliminarlo?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Eliminar aviso'),
        ),
      ],
    );
  }
}
