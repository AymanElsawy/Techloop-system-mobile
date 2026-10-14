import '../../core/api.dart';
import '../models/common.dart';
import '../models/inventory.dart';

/// Products, warehouses, stock movements and suppliers.
class InventoryRepository {
  InventoryRepository(this._api);
  final Api _api;

  Future<List<Product>> products({
    String? search,
    String? unit,
    bool? active,
    bool lowStock = false,
  }) async => toList(
    await _api.get('/products', {
      'search': search,
      'unit': unit,
      'active': active,
      'lowStock': lowStock ? true : null,
    }),
    Product.fromJson,
  );
  Future<PageOf<Product>> productsPage(
    int page, {
    String? search,
    String? unit,
    bool? active,
    bool lowStock = false,
  }) async => PageOf.fromJson(
    await _api.getPage(
      '/products',
      {
        'search': search,
        'unit': unit,
        'active': active,
        'lowStock': lowStock ? true : null,
      },
      page: page,
      limit: pageSize,
    ),
    Product.fromJson,
  );
  Future<Product> product(String id) async =>
      Product.fromJson(await _api.get('/products/$id') as Json);
  Future<Product> createProduct(Json data) async =>
      Product.fromJson(await _api.post('/products', data) as Json);
  Future<Product> updateProduct(String id, Json data) async =>
      Product.fromJson(await _api.patch('/products/$id', data) as Json);
  Future<void> deleteProduct(String id) => _api.delete('/products/$id');

  Future<List<Warehouse>> warehouses() async =>
      toList(await _api.get('/inventory/warehouses'), Warehouse.fromJson);
  Future<WarehouseDetails> warehouse(String id) async =>
      WarehouseDetails.fromJson(
        await _api.get('/inventory/warehouses/$id') as Json,
      );
  Future<Warehouse> createWarehouse(String name, String? notes) async =>
      Warehouse.fromJson(
        await _api.post('/inventory/warehouses', {'name': name, 'notes': notes})
            as Json,
      );
  Future<Warehouse> updateWarehouse(String id, Json data) async =>
      Warehouse.fromJson(
        await _api.patch('/inventory/warehouses/$id', data) as Json,
      );
  Future<MyStock> myStock() async =>
      MyStock.fromJson(await _api.get('/inventory/my-stock') as Json);

  /// طلبات العهدة. Reps: their own; warehouse rep: their warehouse; managers: all.
  Future<List<CustodyRequest>> custodyRequests({String? status}) async =>
      toList(
        await _api.get('/inventory/requests', {'status': status}),
        CustodyRequest.fromJson,
      );

  /// Sales rep: items = [{productId, quantity}].
  Future<CustodyRequest> createCustodyRequest(
    List<Json> items,
    String? notes,
  ) async => CustodyRequest.fromJson(
    await _api.post('/inventory/requests', {'items': items, 'notes': notes})
        as Json,
  );

  /// Warehouse rep / manager: items = the quantities actually issued.
  Future<CustodyRequest> issueCustodyRequest(
    String id,
    List<Json> items,
  ) async => CustodyRequest.fromJson(
    await _api.post('/inventory/requests/$id/issue', {'items': items}) as Json,
  );
  Future<CustodyRequest> rejectCustodyRequest(String id, String reason) async =>
      CustodyRequest.fromJson(
        await _api.post('/inventory/requests/$id/reject', {'reason': reason})
            as Json,
      );
  Future<CustodyRequest> cancelCustodyRequest(String id) async =>
      CustodyRequest.fromJson(
        await _api.post('/inventory/requests/$id/cancel') as Json,
      );

  /// type: RECEIVE (needs supplierId + unitCost per item) | ISSUE | RETURN (need repId) | TRANSFER (toWarehouseId).
  Future<Movement> move(
    String warehouseId,
    String type,
    Json data,
  ) async => Movement.fromJson(
    await _api.post(
          '/inventory/warehouses/$warehouseId/${const {'RECEIVE': 'receive', 'ISSUE': 'issue', 'RETURN': 'return', 'TRANSFER': 'transfer'}[type]}',
          data,
        )
        as Json,
  );

  /// جرد: items = [{productId, counted}]; the backend records the difference.
  Future<Movement> adjust(
    String warehouseId,
    List<Json> items,
    String reason,
  ) async => Movement.fromJson(
    await _api.post('/inventory/warehouses/$warehouseId/adjust', {
          'items': items,
          'reason': reason,
        })
        as Json,
  );
  Future<List<Movement>> movements({
    String? warehouseId,
    String? repId,
    String? type,
    String? supplierId,
    String? productId,
  }) async => toList(
    await _api.get('/inventory/movements', {
      'warehouseId': warehouseId,
      'repId': repId,
      'type': type,
      'supplierId': supplierId,
      'productId': productId,
    }),
    Movement.fromJson,
  );
  Future<PageOf<Movement>> movementsPage(
    int page, {
    String? warehouseId,
    String? repId,
    String? type,
  }) async => PageOf.fromJson(
    await _api.getPage(
      '/inventory/movements',
      {'warehouseId': warehouseId, 'repId': repId, 'type': type},
      page: page,
      limit: pageSize,
    ),
    Movement.fromJson,
  );
  Future<Movement> movement(String id) async =>
      Movement.fromJson(await _api.get('/inventory/movements/$id') as Json);

  Future<List<Supplier>> suppliers({String? search, bool? active}) async =>
      toList(
        await _api.get('/suppliers', {'search': search, 'active': active}),
        Supplier.fromJson,
      );
  Future<PageOf<Supplier>> suppliersPage(
    int page, {
    String? search,
    bool? active,
  }) async => PageOf.fromJson(
    await _api.getPage(
      '/suppliers',
      {'search': search, 'active': active},
      page: page,
      limit: pageSize,
    ),
    Supplier.fromJson,
  );
  Future<Supplier> supplier(String id) async =>
      Supplier.fromJson(await _api.get('/suppliers/$id') as Json);

  /// Fixed public balance link (رابط المديونية).
  Future<String> supplierShareLink(String id) async =>
      '$apiUrl/public/s/${(await _api.post('/suppliers/$id/share-link') as Json)['token']}';
  Future<Supplier> createSupplier(Json data) async =>
      Supplier.fromJson(await _api.post('/suppliers', data) as Json);
  Future<Supplier> updateSupplier(String id, Json data) async =>
      Supplier.fromJson(await _api.patch('/suppliers/$id', data) as Json);

  Future<List<SupplierPayment>> supplierPayments(String supplierId) async =>
      toList(
        await _api.get('/suppliers/$supplierId/payments'),
        SupplierPayment.fromJson,
      );
  Future<SupplierPayment> createSupplierPayment(
    String supplierId,
    Json data,
  ) async => SupplierPayment.fromJson(
    await _api.post('/suppliers/$supplierId/payments', data) as Json,
  );
  Future<SupplierPayment> cancelSupplierPayment(
    String paymentId,
    String reason,
  ) async => SupplierPayment.fromJson(
    await _api.post('/suppliers/payments/$paymentId/cancel', {'reason': reason})
        as Json,
  );
}
