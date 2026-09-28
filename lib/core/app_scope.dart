import 'package:flutter/widgets.dart';

import '../data/repositories/customer_repository.dart';
import '../data/repositories/inventory_repository.dart';
import '../data/repositories/sales_repository.dart';
import '../data/repositories/treasury_repository.dart';
import 'session.dart';

/// Dependency injection without a package: the session and one instance of each repository,
/// reachable from any screen with `context.app`.
class AppScope extends InheritedWidget {
  AppScope({super.key, required this.session, required super.child})
    : customers = CustomerRepository(session.api),
      visits = VisitRepository(session.api),
      sales = SalesRepository(session.api),
      inventory = InventoryRepository(session.api),
      treasury = TreasuryRepository(session.api),
      documents = DocumentRepository(session.api),
      users = UserRepository(session.api);

  final Session session;
  final CustomerRepository customers;
  final VisitRepository visits;
  final SalesRepository sales;
  final InventoryRepository inventory;
  final TreasuryRepository treasury;
  final DocumentRepository documents;
  final UserRepository users;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false; // repositories are stateless
}

extension AppScopeX on BuildContext {
  AppScope get app => getInheritedWidgetOfExactType<AppScope>()!;

  /// The logged-in user (every screen behind the shell has one).
  User get user => app.session.user!;
  bool get isManager => user.isManager;
}
