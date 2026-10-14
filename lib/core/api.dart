import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'offline.dart';

/// Backend base URL. Override with `--dart-define=API_URL=http://192.168.1.10:5050/api` on a real device.
/// Defaults: Android emulator reaches the host at 10.0.2.2, the iOS simulator at localhost.
final String apiUrl = const String.fromEnvironment('API_URL').isNotEmpty
    ? const String.fromEnvironment('API_URL')
    : 'http://${Platform.isAndroid ? '10.0.2.2' : 'localhost'}:5050/api';

/// An error with the same Arabic messages as the web app. [serverMessage] is the backend's English
/// message, used by screens that map specific failures (e.g. "previous debt", "already in use").
class ApiException implements Exception {
  ApiException(this.status, this.message, [this.serverMessage = '']);
  final int status; // 0 = no connection
  final String message;
  final String serverMessage;
  @override
  String toString() => message;
}

String _messageFor(int status, String path) {
  if (status == 401 && path == '/auth/login')
    return 'اسم الدخول أو كلمة المرور غير صحيحة.';
  if (status == 403 && path == '/auth/login')
    return 'هذا الحساب موقوف. تواصل مع الإدارة.';
  return switch (status) {
    401 => 'انتهت الجلسة. سجّل الدخول مرة أخرى.',
    403 => 'ليس لديك صلاحية لتنفيذ هذا الإجراء.',
    404 => 'العنصر المطلوب غير موجود.',
    _ => 'حدث خطأ غير متوقع. حاول مرة أخرى.',
  };
}

/// Arabic message for any error thrown by an API call; [fallback] replaces the generic one (e.g. for 400s).
String errorMessage(Object error, [String? fallback]) {
  if (error is ApiException &&
      (fallback == null || const {0, 401, 403, 404}.contains(error.status))) {
    return error.message;
  }
  return fallback ?? 'حدث خطأ غير متوقع. حاول مرة أخرى.';
}

/// Why the server rejected a request saved offline, in Arabic.
String _rejectReason(ApiException e) {
  final m = e.serverMessage;
  if (m.contains("exceeds the customer's debt"))
    return 'المبلغ أكبر من مديونية العميل الحالية.';
  if (m.toLowerCase().contains('visit')) return 'حالة الزيارة اتغيرت.';
  if (e.status == 403 || e.status == 404) return e.message;
  return 'السيرفر رفض العملية.';
}

/// Thin JSON client: adds the token, unwraps `{ success, data }`, and reports 401s.
/// With a [store]: GETs fall back to the last cached response when the server can't be reached,
/// and [postOrQueue] saves a request to send later.
class Api {
  Api({
    required this.token,
    required this.onUnauthorized,
    this.store,
    this.userId,
    String? baseUrl,
  }) : _base = baseUrl ?? apiUrl;

  final String? Function() token;
  final void Function() onUnauthorized;
  final OfflineStore? store;
  final String? Function()? userId;
  final String _base;

  /// Null and empty query values are dropped.
  Future<dynamic> get(String path, [Map<String, Object?> query = const {}]) =>
      _get(path, query, whole: false);

  /// One page of a list: the whole body, `{ data: [...], meta: { page, limit, total, sum? } }`.
  Future<Map<String, dynamic>> getPage(
    String path,
    Map<String, Object?> query, {
    required int page,
    required int limit,
  }) async =>
      await _get(path, {...query, 'page': page, 'limit': limit}, whole: true)
          as Map<String, dynamic>;

  Future<dynamic> _get(
    String path,
    Map<String, Object?> query, {
    required bool whole,
  }) async {
    final key = cacheKey(path, query);
    try {
      final data = await _send('GET', path, query: query, whole: whole);
      await store?.save(key, data);
      return data;
    } on ApiException catch (e) {
      final cached = e.status == 0 ? await store?.read(key) : null;
      if (cached == null) rethrow;
      return cached.data;
    }
  }

  String cacheKey(String path, [Map<String, Object?> query = const {}]) =>
      _uri(path, query).toString();

  /// POST, or — when the server can't be reached — saved and sent later by [syncQueue]. Returns null when saved.
  /// [patchCache] updates cached GETs so screens show the change right away.
  /// ponytail: a request that reached the server but timed out gets sent twice; the backend rejects the copy
  /// (409 for a used receipt number is treated as done, a started visit shows as a failed item to delete).
  Future<dynamic> postOrQueue(
    String path,
    Map<String, dynamic> body, {
    required String label,
    Map<String, dynamic> meta = const {},
    Map<String, dynamic Function(dynamic data)> patchCache = const {},
  }) async {
    try {
      return await post(path, body);
    } on ApiException catch (e) {
      final s = store, uid = userId?.call();
      if (e.status != 0 || s == null || uid == null) rethrow;
      await s.enqueue(
        PendingOp(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          userId: uid,
          path: path,
          body: body,
          label: label,
          meta: meta,
          createdAt: DateTime.now(),
        ),
      );
      for (final p in patchCache.entries) {
        await s.patch(cacheKey(p.key), p.value);
      }
      return null;
    }
  }

  bool _syncing = false;

  /// Sends the saved requests of the logged-in user, oldest first. Stops at the first connection error.
  Future<void> syncQueue() async {
    final s = store, uid = userId?.call();
    if (s == null || uid == null || _syncing) return;
    _syncing = true;
    try {
      for (final op in s.queueOf(uid).where((op) => op.error == null)) {
        try {
          await post(op.path, op.body);
          await s.remove(op.id);
        } on ApiException catch (e) {
          if (e.status == 0 || e.status == 401) break;
          if (e.status == 409) {
            await s.remove(
              op.id,
            ); // same receipt number: it was saved before the connection dropped
          } else {
            await s.setError(op.id, _rejectReason(e));
          }
        }
      }
    } finally {
      _syncing = false;
    }
  }

  Future<dynamic> post(String path, [Object body = const {}]) =>
      _send('POST', path, body: body);
  Future<dynamic> patch(String path, Object body) =>
      _send('PATCH', path, body: body);
  Future<dynamic> put(String path, Object body) =>
      _send('PUT', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Multipart upload (attachments): `fields` + one `file`.
  Future<dynamic> upload(
    String path,
    Map<String, String> fields,
    Uint8List bytes,
    String filename,
  ) {
    final request = http.MultipartRequest('POST', _uri(path))
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    return _run(request, path);
  }

  /// Raw bytes (attachments need the auth header, so they can't be opened as plain URLs).
  Future<({Uint8List bytes, String contentType})> download(String path) async {
    final res = await _response(http.Request('GET', _uri(path)), path);
    return (
      bytes: res.bodyBytes,
      contentType: res.headers['content-type'] ?? '',
    );
  }

  Uri _uri(String path, [Map<String, Object?> query = const {}]) {
    final q = {
      for (final e in query.entries)
        if (e.value != null && '${e.value}'.isNotEmpty) e.key: '${e.value}',
    };
    return Uri.parse(
      '$_base$path',
    ).replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, Object?> query = const {},
    Object? body,
    bool whole = false,
  }) {
    final request = http.Request(method, _uri(path, query))
      ..headers['content-type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    return _run(request, path, whole: whole);
  }

  Future<dynamic> _run(
    http.BaseRequest request,
    String path, {
    bool whole = false,
  }) async {
    final res = await _response(request, path);
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return whole ? json : json['data'];
  }

  Future<http.Response> _response(http.BaseRequest request, String path) async {
    final t = token();
    if (t != null) request.headers['authorization'] = 'Bearer $t';

    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      );
    } catch (_) {
      store?.offline.value = true;
      throw ApiException(
        0,
        'تعذر الاتصال بالخادم. تأكد من الإنترنت وحاول مرة أخرى.',
      );
    }
    if (store?.offline.value ?? false) {
      store!.offline.value = false;
      syncQueue(); // back online: send what was saved meanwhile
    }
    if (res.statusCode == 401 && path != '/auth/login') onUnauthorized();
    if (res.statusCode >= 400) {
      var server = '';
      try {
        server =
            (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['message']
                as String? ??
            '';
      } catch (_) {}
      throw ApiException(
        res.statusCode,
        _messageFor(res.statusCode, path),
        server,
      );
    }
    return res;
  }
}
