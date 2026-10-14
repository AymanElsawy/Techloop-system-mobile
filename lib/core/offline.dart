import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A request saved while offline, sent when the server is reachable again.
class PendingOp {
  PendingOp({
    required this.id,
    required this.userId,
    required this.path,
    required this.body,
    required this.label,
    this.meta = const {},
    required this.createdAt,
    this.error,
  });

  PendingOp.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      userId = j['userId'] as String,
      path = j['path'] as String,
      body = j['body'] as Map<String, dynamic>,
      label = j['label'] as String,
      meta = j['meta'] as Map<String, dynamic>? ?? const {},
      createdAt = DateTime.parse(j['createdAt'] as String),
      error = j['error'] as String?;

  final String id;
  final String userId; // only sent while this user is logged in
  final String path; // POST
  final Map<String, dynamic> body;
  final String label; // shown in the list, e.g. "تحصيل 150 ج.م. · عيادة النور"
  final Map<String, dynamic> meta; // e.g. collection: customer, amount, method
  final DateTime createdAt;

  /// Set when the server rejected it; the user retries or deletes it.
  final String? error;

  PendingOp withError(String? error) => PendingOp(
    id: id,
    userId: userId,
    path: path,
    body: body,
    label: label,
    meta: meta,
    createdAt: createdAt,
    error: error,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'path': path,
    'body': body,
    'label': label,
    'meta': meta,
    'createdAt': createdAt.toIso8601String(),
    'error': error,
  };
}

/// Offline support on disk: the last response of every GET (served when the server can't be reached)
/// and the queue of requests saved while offline.
class OfflineStore {
  OfflineStore._(this._dir, List<PendingOp> ops) : queue = ValueNotifier(ops);

  static Future<OfflineStore> open() async => openAt(
    Directory('${(await getApplicationSupportDirectory()).path}/offline'),
  );

  @visibleForTesting
  static Future<OfflineStore> openAt(Directory dir) async {
    await Directory('${dir.path}/cache').create(recursive: true);
    var ops = <PendingOp>[];
    try {
      final list =
          jsonDecode(await File('${dir.path}/queue.json').readAsString())
              as List;
      ops = [
        for (final j in list) PendingOp.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {} // no queue yet
    return OfflineStore._(dir, ops);
  }

  final Directory _dir;

  /// True while the last request could not reach the server (screens show cached data).
  final offline = ValueNotifier(false);
  final ValueNotifier<List<PendingOp>> queue;

  // ---------- GET cache ----------

  /// FNV-1a; the key is stored in the file too, so a collision only means a cache miss.
  File _file(String key) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(key)) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return File('${_dir.path}/cache/${h.toRadixString(16)}.json');
  }

  Future<void> save(String key, dynamic data) async {
    try {
      await _file(key).writeAsString(jsonEncode({'key': key, 'data': data}));
    } catch (_) {} // a cache write never breaks the app
  }

  /// The cached data, or null when there is none.
  Future<({dynamic data})?> read(String key) async {
    try {
      final j =
          jsonDecode(await _file(key).readAsString()) as Map<String, dynamic>;
      return j['key'] == key ? (data: j['data']) : null;
    } catch (_) {
      return null;
    }
  }

  /// Updates cached data so screens reflect a queued change (e.g. a started visit).
  Future<void> patch(String key, dynamic Function(dynamic data) update) async {
    final cached = await read(key);
    if (cached != null) await save(key, update(cached.data));
  }

  /// On logout: another user must not see this one's data.
  Future<void> clearCache() async {
    try {
      await Directory('${_dir.path}/cache').delete(recursive: true);
    } catch (_) {}
    await Directory('${_dir.path}/cache').create(recursive: true);
  }

  // ---------- queue ----------

  List<PendingOp> queueOf(String? userId) => [
    for (final op in queue.value)
      if (op.userId == userId) op,
  ];

  Future<void> enqueue(PendingOp op) => _setQueue([...queue.value, op]);
  Future<void> remove(String id) => _setQueue([
    for (final op in queue.value)
      if (op.id != id) op,
  ]);
  Future<void> setError(String id, String? error) => _setQueue([
    for (final op in queue.value) op.id == id ? op.withError(error) : op,
  ]);

  Future<void> _setQueue(List<PendingOp> ops) async {
    queue.value = ops;
    await File(
      '${_dir.path}/queue.json',
    ).writeAsString(jsonEncode([for (final op in ops) op.toJson()]));
  }
}
