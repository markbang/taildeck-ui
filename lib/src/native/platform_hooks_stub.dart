/// Web and other hosts without dart:io: no Android hooks to install.
Future<({String name, String? warning})> resolve() async =>
    (name: 'go', warning: null);
