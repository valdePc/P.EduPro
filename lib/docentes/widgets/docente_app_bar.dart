import 'package:flutter/material.dart';
import 'package:edupro/widgets/app_info_menu.dart';

const Color kDocenteHeaderBlue = Color(0xFF0D47A1);

PreferredSizeWidget buildDocenteBackAppBar(
  BuildContext context, {
  Color arrowColor = Colors.white,
  Color backgroundColor = kDocenteHeaderBlue,
  List<Widget>? actions,
}) {
  final mergedActions = <Widget>[
    ...(actions ?? const []),
    const AppInfoMenuButton(),
  ];

  return AppBar(
    backgroundColor: backgroundColor,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    automaticallyImplyLeading: false,
    leading: IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      icon: Icon(Icons.arrow_back, color: arrowColor),
      onPressed: () => Navigator.of(context).maybePop(),
    ),
    title: const SizedBox.shrink(),
    actions: mergedActions,
  );
}
