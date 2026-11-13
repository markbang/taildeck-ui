import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'native/storage.dart';

/// Ports that answer TLS, used for both the scan and the gateway label.
const httpsPorts = {443, 5001, 8006, 8443, 9443, 10000};

/// The ports Taildeck's Android app probes on a node.
const commonPorts = [
  80, 443, 81, 2283, 3000, 3001, 5000, 5001, 5050, 5244, 5678, 6080, 7878,
  8000, 8006, 8080, 8081, 8088, 8096, 8123, 8181, 8384, 8443, 8888, 8989,
  9000, 9090, 9091, 9443, 10000, 19999, 32400,
];

/// One saved service; [url] is the tailnet URL (`http://nas:5001/`) and the
/// node is kept separately because it is the gateway's Host key.
class Service {
  const Service({
    required this.id,
    required this.node,
    required this.name,
    required this.url,
  });

  factory Service.fromJson(Map<String, dynamic> json) => Service(
    id: json['id'] as String? ?? '',
    node: json['node'] as String? ?? '',
    name: json['name'] as String? ?? '',
    url: json['url'] as String? ?? '',
  );

  final String id;
  final String node;
  final String name;
  final String url;

  Map<String, dynamic> toJson() => {
    'id': id,
    'node': node,
    'name': name,
    'url': url,
  };

  Uri? get uri => Uri.tryParse(url);

  String get scheme => uri?.scheme ?? 'http';

  int get port => uri?.port ?? 0;

  bool get secure => scheme == 'https' || httpsPorts.contains(port);

  /// `nas:5001`, plus the path when it is not the root.
  String get address {
    final path = uri?.path ?? '';
    return '$node:$port${path.isEmpty || path == '/' ? '' : path}';
  }

  Color get tint => _tints[name.hashCode.abs() % _tints.length];

  static const _tints = [
    Color(0xFFF08C2E),
    Color(0xFF4E8CFF),
    Color(0xFF5C6BC0),
    Color(0xFFA855F7),
    Color(0xFF38BDF8),
    Color(0xFF4FB28A),
  ];
}

/// Saved services, persisted as `services.json` in the app support dir. Web
/// has no storage handle and keeps the demo list in memory.
class ServiceStore extends ChangeNotifier {
  ServiceStore._(this._storage, List<Service> items) : _items = [...items];

  factory ServiceStore.open() {
    final storage = openBackendStorage();
    return ServiceStore._(storage, storage == null ? demoServices : const []);
  }

  final BackendStorage? _storage;
  List<Service> _items;
  bool _loaded = false;

  List<Service> get all => List.unmodifiable(_items);

  bool get loaded => _loaded;

  List<Service> forNode(String node) => [
    for (final service in _items)
      if (service.node == node) service,
  ];

  /// Nodes with services, alphabetically.
  List<String> get nodes {
    final names = {for (final service in _items) service.node}.toList()..sort();
    return names;
  }

  Future<void> load() async {
    final storage = _storage;
    if (storage == null) {
      _loaded = true;
      notifyListeners();
      return;
    }
    try {
      final raw = await storage.readServicesJson();
      if (raw != null && raw.trim().isNotEmpty) _items = _parse(raw);
    } on Object catch (error) {
      debugPrint('taildeck: could not read services: $error');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> upsert(Service service) async {
    final index = _items.indexWhere((item) => item.id == service.id);
    if (index >= 0) {
      _items[index] = service;
    } else {
      _items.add(service);
    }
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _items = [
      for (final service in _items)
        if (service.id != id) service,
    ];
    notifyListeners();
    await _save();
  }

  /// A fresh id without pulling in a uuid package.
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';

  static List<Service> _parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map<String, dynamic>) Service.fromJson(item),
    ];
  }

  Future<void> _save() async {
    final storage = _storage;
    if (storage == null) return;
    try {
      await storage.writeServicesJson(
        jsonEncode([for (final service in _items) service.toJson()]),
      );
    } on Object catch (error) {
      debugPrint('taildeck: could not save services: $error');
    }
  }
}

class ServicesScope extends InheritedNotifier<ServiceStore> {
  const ServicesScope({
    super.key,
    required ServiceStore store,
    required super.child,
  }) : super(notifier: store);

  static ServiceStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ServicesScope>();
    assert(scope != null, 'ServicesScope missing above this widget');
    return scope!.notifier!;
  }
}

/// Loopback URL a browser can open for [service]; null when the gateway is
/// not running (port 0), which the caller explains inline.
String? gatewayUrl(Service service, int gatewayPort) {
  final uri = service.uri;
  if (gatewayPort <= 0 || uri == null || uri.host.isEmpty || service.port <= 0) {
    return null;
  }
  final label =
      '${uri.host.toLowerCase()}-${service.port}${service.secure ? 's' : ''}';
  return Uri(
    scheme: 'http',
    host: '$label.localhost',
    port: gatewayPort,
    path: uri.path.isEmpty ? '/' : uri.path,
    query: uri.hasQuery ? uri.query : null,
  ).toString();
}

/// The tailnet URL for a draft; the port has already been validated.
String serviceUrl({
  required String node,
  required String scheme,
  required int port,
  required String path,
}) {
  final trimmed = path.trim();
  final resolved = trimmed.isEmpty
      ? '/'
      : trimmed.startsWith('/')
      ? trimmed
      : '/$trimmed';
  return '$scheme://$node:$port$resolved';
}

/// Shown in the web preview, which has no persistence.
const demoServices = <Service>[
  Service(
    id: 'demo-grafana',
    node: 'devbox',
    name: 'Grafana',
    url: 'http://devbox:3000/',
  ),
  Service(
    id: 'demo-code',
    node: 'devbox',
    name: 'code-server',
    url: 'http://devbox:8080/',
  ),
  Service(
    id: 'demo-dsm',
    node: 'nas',
    name: 'Synology DSM',
    url: 'https://nas:5001/',
  ),
  Service(
    id: 'demo-jellyfin',
    node: 'nas',
    name: 'Jellyfin',
    url: 'http://nas:8096/',
  ),
  Service(
    id: 'demo-hass',
    node: 'pi-k3s',
    name: 'Home Assistant',
    url: 'http://pi-k3s:8123/',
  ),
];
