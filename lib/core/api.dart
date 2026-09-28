import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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
  if (status == 401 && path == '/auth/login') return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
  if (status == 403 && path == '/auth/login') return 'هذا الحساب موقوف. تواصل مع الإدارة.';
  return switch (status) {
    401 => 'انتهت الجلسة. سجّل الدخول مرة أخرى.',
    403 => 'ليس لديك صلاحية لتنفيذ هذا الإجراء.',
    404 => 'العنصر المطلوب غير موجود.',
    _ => 'حدث خطأ غير متوقع. حاول مرة أخرى.',
  };
}

/// Arabic message for any error thrown by an API call; [fallback] replaces the generic one (e.g. for 400s).
String errorMessage(Object error, [String? fallback]) {
  if (error is ApiException && (fallback == null || const {0, 401, 403, 404}.contains(error.status))) {
    return error.message;
  }
  return fallback ?? 'حدث خطأ غير متوقع. حاول مرة أخرى.';
}

/// Thin JSON client: adds the token, unwraps `{ success, data }`, and reports 401s.
class Api {
  Api({required this.token, required this.onUnauthorized});

  final String? Function() token;
  final void Function() onUnauthorized;

  /// Null and empty query values are dropped.
  Future<dynamic> get(String path, [Map<String, Object?> query = const {}]) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object body = const {}]) => _send('POST', path, body: body);
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);

  /// Multipart upload (attachments): `fields` + one `file`.
  Future<dynamic> upload(String path, Map<String, String> fields, Uint8List bytes, String filename) {
    final request = http.MultipartRequest('POST', _uri(path))
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    return _run(request, path);
  }

  /// Raw bytes (attachments need the auth header, so they can't be opened as plain URLs).
  Future<({Uint8List bytes, String contentType})> download(String path) async {
    final res = await _response(http.Request('GET', _uri(path)), path);
    return (bytes: res.bodyBytes, contentType: res.headers['content-type'] ?? '');
  }

  Uri _uri(String path, [Map<String, Object?> query = const {}]) {
    final q = {
      for (final e in query.entries)
        if (e.value != null && '${e.value}'.isNotEmpty) e.key: '${e.value}',
    };
    return Uri.parse('$apiUrl$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> _send(String method, String path, {Map<String, Object?> query = const {}, Object? body}) {
    final request = http.Request(method, _uri(path, query))..headers['content-type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    return _run(request, path);
  }

  Future<dynamic> _run(http.BaseRequest request, String path) async {
    final res = await _response(request, path);
    return (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['data'];
  }

  Future<http.Response> _response(http.BaseRequest request, String path) async {
    final t = token();
    if (t != null) request.headers['authorization'] = 'Bearer $t';

    final http.Response res;
    try {
      res = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));
    } catch (_) {
      throw ApiException(0, 'تعذر الاتصال بالخادم. تأكد من الإنترنت وحاول مرة أخرى.');
    }
    if (res.statusCode == 401 && path != '/auth/login') onUnauthorized();
    if (res.statusCode >= 400) {
      var server = '';
      try {
        server = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['message'] as String? ?? '';
      } catch (_) {}
      throw ApiException(res.statusCode, _messageFor(res.statusCode, path), server);
    }
    return res;
  }
}
