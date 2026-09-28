import '../../core/api.dart';
import '../models/common.dart';
import '../models/inventory.dart';

/// Products, warehouses, stock movements and suppliers.
class InventoryRepository {
  InventoryRepository(this._api);
  final Api _api;

  Future<List<Product>> products({String? search, String? unit, bool? active, bool lowStock = false}) async => toList(
    await _api.get('/products', {'search': search, 'unit': unit, 'active': active, 'lowStock': lowStock ? true : null}),
    Product.fromJson,
  );
  Future<Product> product(String id) async => Product.fromJson(await _api.get('/products/$id') as Json);
  Future<Product> createProduct(Json data) async => Product.fromJson(await _api.post('/products', data) as Json);
  Future<Product> updateProduct(String id, Json data) async =>
      Product.fromJson(await _api.patch('/products/$id', data) as Json);

  Future<List<Warehouse>> warehouses() async => toList(await _api.get('/inventory/warehouses'), Warehouse.fromJson);
  Future<WarehouseDetails> warehouse(String id) async =>
      WarehouseDetails.fromJson(await _api.get('/inventory/warehouses/$id') as Json);
  Future<Warehouse> createWarehouse(String name, String? notes) async =>
      Warehouse.fromJson(await _api.post('/inventory/warehouses', {'name': name, 'notes': notes}) as Json);
  Future<Warehouse> updateWarehouse(String id, Json data) async =>
      Warehouse.fromJson(await _api.patch('/inventory/warehouses/$id', data) as Json);
  Future<MyStock> myStock() async => MyStock.fromJson(await _api.get('/inventory/my-stock') as Json);

  /// type: RECEIVE (needs supplierId + unitCost per item) | ISSUE | RETURN (need repId).
  Future<Movement> move(String warehouseId, String type, Json data) async => Movement.fromJson(
    await _api.post(
          '/inventory/warehouses/$warehouseId/${const {'RECEIVE': 'receive', 'ISSUE': 'issue', 'RETURN': 'return'}[type]}',
          data,
        )
        as Json,
  );
  Future<List<Movement>> movements({String? warehouseId, String? repId, String? type, String? supplierId}) async =>
      toList(
        await _api.get('/inventory/movements', {
          'warehouseId': warehouseId,
          'repId': repId,
          'type': type,
          'supplierId': supplierId,
        }),
        Movement.fromJson,
      );
  Future<Movement> movement(String id) async => Movement.fromJson(await _api.get('/inventory/movements/$id') as Json);

  Future<List<Supplier>> suppliers({String? search, bool? active}) async =>
      toList(await _api.get('/suppliers', {'search': search, 'active': active}), Supplier.fromJson);
  Future<Supplier> supplier(String id) async => Supplier.fromJson(await _api.get('/suppliers/$id') as Json);
  Future<Supplier> createSupplier(Json data) async => Supplier.fromJson(await _api.post('/suppliers', data) as Json);
  Future<Supplier> updateSupplier(String id, Json data) async =>
      Supplier.fromJson(await _api.patch('/suppliers/$id', data) as Json);
}
