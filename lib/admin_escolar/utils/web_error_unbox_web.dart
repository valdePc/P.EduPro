// Solo para Web. El llamador nativo utiliza web_error_unbox_stub.dart.
import 'dart:js_interop';

extension type _WrappedWebError(JSObject object) implements JSObject {
  external JSAny? get error;
  external JSAny? get stack;
}

@JS('String')
external JSString _jsString(JSAny value);

String? _text(JSAny? value) {
  if (value == null) return null;
  if (value.isA<JSBoxedDartObject>()) {
    return (value as JSBoxedDartObject).toDart.toString();
  }
  return _jsString(value).toDart;
}

String unboxWebError(Object e) {
  try {
    final wrapper = _WrappedWebError(JSObject.fromInteropObject(e));
    return _text(wrapper.error) ?? e.toString();
  } catch (_) {
    return e.toString();
  }
}

String unboxWebStack(Object e) {
  try {
    final wrapper = _WrappedWebError(JSObject.fromInteropObject(e));
    return _text(wrapper.stack) ?? '';
  } catch (_) {
    return '';
  }
}
