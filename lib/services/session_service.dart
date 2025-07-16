class SessionService {
  final dynamic prefs;

  SessionService(this.prefs);

  bool get isLoggedIn => prefs.getBool('isLoggedIn') ?? false;

  String get userType => prefs.getString('userType') ?? 'guest';

  String get initialRoute {
    if (!isLoggedIn) return '/login';
    switch (userType) {
      case 'admin':
        return '/admin';
      case 'maestro':
        return '/maestro';
      case 'estudiante':
        return '/estudiante';
      case 'freelancer':
        return '/freelancer';
      default:
        return '/login';
    }
  }
}
