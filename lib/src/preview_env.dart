import 'preview_env_stub.dart' if (dart.library.io) 'preview_env_io.dart' as env;

/// Preview parameters (`?tab=1`, `?ssh=demo`, ...). Web and mobile read the
/// URL; the desktop bundle has none, so `TAILDECK_QUERY=ssh=demo` stands in.
String? previewParam(String name) {
  final value = Uri.base.queryParameters[name];
  if (value != null) return value;
  final raw = env.queryOverride;
  if (raw == null || raw.isEmpty) return null;
  return Uri.splitQueryString(raw)[name];
}
