import 'package:flutter/material.dart';
import '../services/session_service.dart';

class AppState extends ChangeNotifier {
  final SessionService session;

  AppState(this.session);

  String get initialRoute => session.initialRoute;
}
