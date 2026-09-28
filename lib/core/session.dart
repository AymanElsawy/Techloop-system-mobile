import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

enum UserRole { owner, admin, salesRep }

class User {
  User.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      role = switch (j['role']) {
        'OWNER' => UserRole.owner,
        'ADMIN' => UserRole.admin,
        _ => UserRole.salesRep,
      },
      governorates = List<String>.from(j['governorates'] as List? ?? const []);

  final String id;
  final String name;
  final UserRole role;
  final List<String> governorates;

  bool get isManager => role != UserRole.salesRep;
  String get roleLabel => switch (role) {
    UserRole.owner => 'صاحب الشركة',
    UserRole.admin => 'مدير النظام',
    UserRole.salesRep => 'مندوب مبيعات',
  };
}

/// Logged-in user + token. The token lives in secure storage, never the password.
class Session extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _key = 'accessToken';

  String? _token;
  User? user;
  bool restoring = true;

  late final api = Api(token: () => _token, onUnauthorized: logout);

  /// Splash: check a saved token with /auth/me.
  Future<void> restore() async {
    try {
      _token = await _storage.read(key: _key);
      if (_token != null) user = User.fromJson(await api.get('/auth/me') as Map<String, dynamic>);
    } catch (_) {
      await _clear();
    }
    restoring = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final data = await api.post('/auth/login', {'email': email, 'password': password}) as Map<String, dynamic>;
    _token = data['accessToken'] as String;
    user = User.fromJson(data['user'] as Map<String, dynamic>);
    await _storage.write(key: _key, value: _token);
    notifyListeners();
  }

  Future<void> logout() async {
    await _clear();
    notifyListeners();
  }

  Future<void> _clear() async {
    _token = null;
    user = null;
    await _storage.delete(key: _key);
  }
}
