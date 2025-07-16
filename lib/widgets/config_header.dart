import 'package:flutter/material.dart';

/// Banda azul fija para escritorio
class ConfigHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const ConfigHeader({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height,
      color: Colors.blue.shade700,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(60);
}
