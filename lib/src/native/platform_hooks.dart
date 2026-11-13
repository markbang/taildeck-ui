/// Which network adapter the native node uses on this host.
///
/// Android 11+ blocks Go's netlink access, so interfaces, the default
/// interface and DNS lookups come from Java (see PlatformBridge.kt) through
/// `td_set_platform_cb`; every other host keeps Go's stdlib.
library;

import 'platform_hooks_stub.dart'
    if (dart.library.io) 'platform_hooks_io.dart' as impl;

/// [name] is the `td_start` platform value (`host` or `go`); [warning] says
/// why the Android hooks are unavailable.
typedef PlatformMode = ({String name, String? warning});

Future<PlatformMode> resolvePlatformMode() => impl.resolve();
