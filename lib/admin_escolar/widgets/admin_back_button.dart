import 'package:flutter/material.dart';

/// Returns to the parent section when embedded, or to the previous route.
class AdminBackButton extends StatelessWidget {
  final VoidCallback? onBack;
  final Color? color;

  const AdminBackButton({super.key, this.onBack, this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Regresar',
      icon: Icon(Icons.arrow_back_rounded, color: color),
      onPressed: () {
        final callback = onBack;
        if (callback != null) {
          callback();
        } else {
          Navigator.of(context).maybePop();
        }
      },
    );
  }
}
