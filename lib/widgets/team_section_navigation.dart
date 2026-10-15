import 'package:flutter/material.dart';

/// Returns to the parent section even when the sidebar replaced its route.
class TeamSectionNavigation {
  static void back(BuildContext context, {String targetRoute = '/panel'}) {
    Navigator.of(context).pushNamedAndRemoveUntil(targetRoute, (_) => false);
  }

  static Widget backButton(
    BuildContext context, {
    String targetRoute = '/panel',
    Color? color,
  }) {
    return IconButton(
      tooltip: 'Volver',
      icon: Icon(Icons.arrow_back, color: color),
      onPressed: () => back(context, targetRoute: targetRoute),
    );
  }
}
