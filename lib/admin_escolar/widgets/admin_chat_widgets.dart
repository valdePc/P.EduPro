import 'package:flutter/material.dart';

abstract final class AdminChatColors {
  static const blue = Color(0xFF1A237E);
  static const ink = Color(0xFF17243A);
  static const muted = Color(0xFF5C687A);
  static const page = Color(0xFFF4F6FB);
  static const border = Color(0xFFE5EAF2);
}

class AdminChatHero extends StatelessWidget {
  final String schoolName;

  const AdminChatHero({super.key, required this.schoolName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AdminChatColors.blue, Color(0xFF3949AB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.forum_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Comunicación escolar',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Comparte avisos con el equipo o conversa con cada docente.',
                  style: TextStyle(
                    color: Color(0xFFE5E9FF),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                if (schoolName.isNotEmpty) ...[
                  const SizedBox(height: 13),
                  Text(
                    schoolName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminChatConversationTile extends StatelessWidget {
  final String title;
  final Widget subtitle;
  final bool isGroup;
  final VoidCallback onTap;

  const AdminChatConversationTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final initials =
        title
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .take(2)
            .map((part) => part.characters.first.toUpperCase())
            .join();
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AdminChatColors.border),
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
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      isGroup
                          ? const Color(0xFFFFF3DA)
                          : const Color(0xFFECEFFC),
                  borderRadius: BorderRadius.circular(15),
                ),
                child:
                    isGroup
                        ? const Icon(
                          Icons.groups_rounded,
                          color: Color(0xFF8A5A00),
                          size: 25,
                        )
                        : Text(
                          initials,
                          style: const TextStyle(
                            color: AdminChatColors.blue,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdminChatColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    DefaultTextStyle(
                      style: const TextStyle(
                        color: AdminChatColors.muted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      child: subtitle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: AdminChatColors.blue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminChatEmptyState extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;

  const AdminChatEmptyState({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.chat_bubble_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFECEFFC),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: AdminChatColors.blue, size: 27),
          ),
          const SizedBox(height: 13),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AdminChatColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AdminChatColors.muted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminChatMessageBubble extends StatelessWidget {
  final bool isMe;
  final String sender;
  final String timeLabel;
  final Widget child;

  const AdminChatMessageBubble({
    super.key,
    required this.isMe,
    required this.child,
    this.sender = '',
    this.timeLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            (constraints.maxWidth * 0.86).clamp(0.0, 560.0).toDouble();
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: isMe ? AdminChatColors.blue : Colors.white,
              border: isMe ? null : Border.all(color: AdminChatColors.border),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 5),
                bottomRight: Radius.circular(isMe ? 5 : 18),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMe && sender.isNotEmpty) ...[
                  Text(
                    sender,
                    style: const TextStyle(
                      color: AdminChatColors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
                child,
                if (timeLabel.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    timeLabel,
                    style: TextStyle(
                      color:
                          isMe
                              ? const Color(0xFFDDE2FF)
                              : AdminChatColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class AdminChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final Future<void> Function() onImage;
  final Future<void> Function() onFile;

  const AdminChatComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onImage,
    required this.onFile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AdminChatColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          PopupMenuButton<String>(
            enabled: !sending,
            tooltip: 'Adjuntar imagen o archivo',
            icon: const Icon(Icons.add_rounded, color: AdminChatColors.blue),
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              backgroundColor: const Color(0xFFF0F2FA),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onSelected: (value) async {
              if (value == 'image') {
                await onImage();
              } else if (value == 'file') {
                await onFile();
              }
            },
            itemBuilder:
                (_) => const [
                  PopupMenuItem(
                    value: 'image',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.image_outlined),
                      title: Text('Imagen'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'file',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.attach_file_rounded),
                      title: Text('Archivo'),
                    ),
                  ),
                ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: sending,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              style: const TextStyle(
                color: AdminChatColors.ink,
                fontSize: 15,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje…',
                hintStyle: const TextStyle(color: AdminChatColors.muted),
                filled: true,
                fillColor: const Color(0xFFF8F9FC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AdminChatColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AdminChatColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AdminChatColors.blue,
                    width: 1.4,
                  ),
                ),
              ),
              onSubmitted: (_) {
                if (!sending && controller.text.trim().isNotEmpty) onSend();
              },
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder:
                (context, value, _) => IconButton.filled(
                  tooltip: sending ? 'Enviando mensaje' : 'Enviar mensaje',
                  onPressed:
                      sending || value.text.trim().isEmpty ? null : onSend,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    backgroundColor: AdminChatColors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon:
                      sending
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.send_rounded, size: 22),
                ),
          ),
        ],
      ),
    );
  }
}
