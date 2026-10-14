import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'api.dart';
import 'offline.dart';

enum UserRole { owner, admin, salesRep, warehouseRep }

class User {
  User.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      role = switch (j['role']) {
        'OWNER' => UserRole.owner,
        'ADMIN' => UserRole.admin,
        'WAREHOUSE_REP' => UserRole.warehouseRep,
        _ => UserRole.salesRep,
      },
      governorates = List<String>.from(j['governorates'] as List? ?? const []),
      mustChangePassword = j['mustChangePassword'] as bool? ?? false;

  final String id;
  final String name;
  final UserRole role;
  final List<String> governorates;

  /// Still on the default password: the app shows ChangePasswordScreen first.
  final bool mustChangePassword;

  bool get isManager => role == UserRole.owner || role == UserRole.admin;

  /// Can view warehouses and issue/return custody: managers and the warehouse rep.
  bool get canOperateWarehouses => isManager || role == UserRole.warehouseRep;
  String get roleLabel => switch (role) {
    UserRole.owner => 'صاحب الشركة',
    UserRole.admin => 'مدير النظام',
    UserRole.salesRep => 'مندوب مبيعات',
    UserRole.warehouseRep => 'مندوب مخزن',
  };
}

/// Logged-in user + token. The token lives in secure storage, never the password.
class Session extends ChangeNotifier {
  Session([this.store]);

  /// Offline cache + queue; null in tests.
  final OfflineStore? store;

  static const _storage = FlutterSecureStorage();
  static const _key = 'accessToken';
  static final _localAuth = LocalAuthentication();

  String? _token;
  User? user;
  bool restoring = true;

  late final api = Api(
    token: () => _token,
    onUnauthorized: logout,
    store: store,
    userId: () => user?.id,
  );

  /// Splash: check a saved token with /auth/me. If the device has a fingerprint
  /// (or other lock screen) set up, require it to unlock; otherwise skip straight
  /// through, same as before.
  Future<void> restore() async {
    try {
      _token = await _storage.read(key: _key);
      if (_token != null && await _unlockWithDeviceAuth()) {
        // Offline: served from the cache, so the rep can keep working.
        user = User.fromJson(await api.get('/auth/me') as Map<String, dynamic>);
      } else if (_token != null) {
        await _clear();
      }
    } on ApiException catch (e) {
      // No connection and nothing cached: show the login screen but keep the token for next time.
      if (e.status == 0) {
        _token = null;
      } else {
        await _clear();
      }
    } catch (_) {
      await _clear();
    }
    restoring = false;
    notifyListeners();
  }

  Future<bool> _unlockWithDeviceAuth() async {
    try {
      if (!await _localAuth.isDeviceSupported() ||
          (await _localAuth.getAvailableBiometrics()).isEmpty) {
        return true; // no fingerprint/face set up on this device: behave as before
      }
      return await _localAuth.authenticate(
        localizedReason: 'افتح التطبيق ببصمتك',
        options: const AuthenticationOptions(
          biometricOnly: false,
        ), // falls back to phone PIN/pattern
      );
    } catch (_) {
      return true; // ponytail: plugin error shouldn't lock the user out
    }
  }

  Future<void> login(String username, String password) async {
    final data =
        await api.post('/auth/login', {
              'username': username,
              'password': password,
            })
            as Map<String, dynamic>;
    _token = data['accessToken'] as String;
    await _setUser(data['user']);
    await _storage.write(key: _key, value: _token);
    notifyListeners();
  }

  /// First-login password change (replaces the default one).
  Future<void> changePassword(String password) async {
    await _setUser(
      await api.post('/auth/change-password', {'password': password}),
    );
    notifyListeners();
  }

  Future<void> _setUser(dynamic json) async {
    user = User.fromJson(json as Map<String, dynamic>);
    await store?.save(
      api.cacheKey('/auth/me'),
      json,
    ); // lets the app open offline
  }

  Future<void> logout() async {
    await _clear();
    notifyListeners();
  }

  /// The offline queue is kept (it's per user and sent after the next login); the cache is not.
  Future<void> _clear() async {
    _token = null;
    user = null;
    await _storage.delete(key: _key);
    await store?.clearCache();
  }
}
