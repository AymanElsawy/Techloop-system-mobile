import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:techloop_mobile/core/api.dart';
import 'package:techloop_mobile/core/offline.dart';

/// A tiny backend that can go down and come back on the same port.
class FakeServer {
  HttpServer? _server;
  int port = 0;
  final posts = <String>[];
  int postStatus = 201;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    port = _server!.port;
    _server!.listen((req) async {
      final body = await utf8.decodeStream(req);
      if (req.method == 'POST') posts.add('${req.uri.path} $body');
      final status = req.method == 'POST' ? postStatus : 200;
      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(status < 400
            ? {'success': true, 'data': {'id': 'c1', 'pendingPayments': 0, 'path': req.uri.path}}
            : {'success': false, 'message': "Amount exceeds the customer's debt (0)"}));
      await req.response.close();
    });
  }

  Future<void> stop() => _server!.close(force: true);
}

void main() {
  late Directory dir;
  late FakeServer server;
  late OfflineStore store;
  late Api api;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('offline_test');
    server = FakeServer();
    await server.start();
    store = await OfflineStore.openAt(dir);
    api = Api(
      token: () => 't',
      onUnauthorized: () {},
      store: store,
      userId: () => 'u1',
      baseUrl: 'http://127.0.0.1:${server.port}/api',
    );
  });

  tearDown(() async {
    await server.stop().catchError((_) {});
    await dir.delete(recursive: true);
  });

  test('GET falls back to the cache when the server is down', () async {
    expect((await api.get('/customers/c1'))['path'], '/api/customers/c1');
    await server.stop();
    expect((await api.get('/customers/c1'))['id'], 'c1');
    expect(store.offline.value, isTrue);
    expect(() => api.get('/never-loaded'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)));
  });

  test('POST offline is queued, patches the cache, and is sent when back online', () async {
    await api.get('/customers/c1');
    await server.stop();

    final result = await api.postOrQueue(
      '/collections',
      {'receiptNumber': 'R1', 'amount': 50},
      label: 'تحصيل R1',
      patchCache: {'/customers/c1': (c) => {...c as Map<String, dynamic>, 'pendingPayments': 50}},
    );
    expect(result, isNull);
    expect(store.queueOf('u1').single.path, '/collections');
    expect(store.queueOf('someone-else'), isEmpty);
    expect((await api.get('/customers/c1'))['pendingPayments'], 50);

    // The queue survives an app restart.
    expect((await OfflineStore.openAt(dir)).queueOf('u1'), hasLength(1));

    await server.start(); // same port
    await api.get('/customers/c1'); // any success flips back online and syncs
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.posts.single, contains('R1'));
    expect(store.queueOf('u1'), isEmpty);
    expect(store.offline.value, isFalse);
  });

  test('rejected items keep a reason; 409 (already saved) is dropped', () async {
    await server.stop();
    await api.postOrQueue('/collections', {'receiptNumber': 'R1'}, label: 'a');
    await api.postOrQueue('/collections', {'receiptNumber': 'R2'}, label: 'b');
    await server.start();

    server.postStatus = 409;
    final first = store.queue.value.first.id;
    await store.setError(store.queue.value.last.id, 'x'); // skip the second for now
    await api.syncQueue();
    expect(store.queue.value.map((o) => o.id), isNot(contains(first)));

    server.postStatus = 400;
    await store.setError(store.queue.value.single.id, null);
    await api.syncQueue();
    expect(store.queue.value.single.error, 'المبلغ أكبر من مديونية العميل الحالية.');
  });
}
