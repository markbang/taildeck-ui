import 'term.dart';

bool get termSupported => false;
bool get termAvailable => false;

NativeTerm? createPlatformTerm({
  required int cols,
  required int rows,
  required int scrollback,
  required int fg,
  required int bg,
  required int cursor,
  String? libraryPath,
}) => null;
