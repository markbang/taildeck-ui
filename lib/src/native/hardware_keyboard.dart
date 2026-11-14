/// Whether a physical keyboard is attached, as the platform reports it. Null
/// when the platform cannot tell (desktop, Web, iOS).
library;

import 'hardware_keyboard_stub.dart'
    if (dart.library.io) 'hardware_keyboard_io.dart'
    as impl;

Future<bool?> physicalKeyboardAttached() => impl.attached();
