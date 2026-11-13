import 'dart:convert';
import 'dart:typed_data';

/// The key `td_key_ensure` creates; never deleted from the settings page.
const builtinKeyId = 'id_ed25519';

enum SshKeyError { nameInvalid, nameTaken, unavailable, io }

class SshKeyException implements Exception {
  const SshKeyException(this.reason);

  final SshKeyError reason;

  @override
  String toString() => 'ssh key error: ${reason.name}';
}

/// One SSH identity: the built-in ed25519 key or a key the user imported as
/// `ssh/<id>.key`. The passphrase stays with the metadata so `td_ssh_dial` can
/// decrypt the key.
class SshIdentity {
  const SshIdentity({
    required this.id,
    required this.name,
    this.publicKey = '',
    this.passphrase = '',
    this.builtin = false,
  });

  factory SshIdentity.fromJson(Map<String, dynamic> json) => SshIdentity(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    publicKey: json['publicKey'] as String? ?? '',
    passphrase: json['passphrase'] as String? ?? '',
  );

  final String id;
  final String name;
  final String publicKey;
  final String passphrase;
  final bool builtin;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'publicKey': publicKey,
    'passphrase': passphrase,
  };
}

const _reservedIds = {'', '.', '..', builtinKeyId};

/// File stem for [name], so the key path and its metadata agree.
String sshKeyId(String name) {
  final stem = name
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')
      .replaceAll(RegExp(r'^[.-]+'), '');
  return stem.isEmpty ? 'key' : stem;
}

bool isUsableKeyId(String id) => !_reservedIds.contains(id);

/// Rewrites a pasted private key with proper PEM line breaks; pasting often
/// loses them, and Go's PEM parser needs the header on its own line.
String? normalizePrivateKey(String pem) {
  final match = RegExp(
    r'-----BEGIN (OPENSSH PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY|PRIVATE KEY)-----([\s\S]*?)-----END \1-----',
  ).firstMatch(pem.trim());
  if (match == null) return null;
  final label = match.group(1)!;
  final body = match.group(2)!.replaceAll(RegExp(r'\s'), '');
  if (body.isEmpty) return null;
  final lines = <String>[];
  for (var i = 0; i < body.length; i += 70) {
    final end = i + 70 < body.length ? i + 70 : body.length;
    lines.add(body.substring(i, end));
  }
  return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
}

/// The public key line of an OpenSSH private key. `openssh-key-v1` keeps its
/// public half outside the encrypted section, so this also works for
/// passphrase protected keys. Null for formats it cannot read.
String? sshPublicKeyOf(String pem) {
  final match = RegExp(
    r'-----BEGIN OPENSSH PRIVATE KEY-----([\s\S]*?)-----END OPENSSH PRIVATE KEY-----',
  ).firstMatch(pem);
  if (match == null) return null;
  final Uint8List bytes;
  try {
    bytes = base64.decode(match.group(1)!.replaceAll(RegExp(r'\s'), ''));
  } on FormatException {
    return null;
  }
  const magic = 'openssh-key-v1\u0000';
  if (bytes.length < magic.length ||
      String.fromCharCodes(bytes.take(magic.length)) != magic) {
    return null;
  }
  var offset = magic.length;

  Uint8List? readString() {
    if (offset + 4 > bytes.length) return null;
    final length = ByteData.sublistView(bytes).getUint32(offset);
    offset += 4;
    if (offset + length > bytes.length) return null;
    final value = bytes.sublist(offset, offset + length);
    offset += length;
    return value;
  }

  // ciphername, kdfname, kdfoptions, then the unencrypted public key blob.
  if (readString() == null ||
      readString() == null ||
      readString() == null) {
    return null;
  }
  if (offset + 4 > bytes.length) return null;
  offset += 4; // number of keys; KeyPaths-based export has one
  final blob = readString();
  if (blob == null || blob.length < 4) return null;
  final typeLength = ByteData.sublistView(blob).getUint32(0);
  if (typeLength + 4 > blob.length) return null;
  final String type;
  try {
    type = utf8.decode(blob.sublist(4, 4 + typeLength));
  } on FormatException {
    return null;
  }
  return type.isEmpty ? null : '$type ${base64.encode(blob)}';
}
