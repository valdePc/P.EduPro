// Fallback para no-Web (Android/iOS/desktop). No usa js_util.
String unboxWebError(Object e) => e.toString();
String unboxWebStack(Object e) => '';