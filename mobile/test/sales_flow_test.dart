import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/businesses/domain/business_summary.dart';
import 'package:zedbiz/features/commercial/domain/money.dart';
import 'package:zedbiz/features/products/data/product_repository.dart';
import 'package:zedbiz/features/products/domain/product.dart';
import 'package:zedbiz/features/sales/application/sale_cart_controller.dart';
import 'package:zedbiz/features/sales/data/sale_repository.dart';
import 'package:zedbiz/features/sales/domain/sale.dart';
import 'package:zedbiz/features/sales/presentation/sales_screen.dart';

import 'helpers/fakes.dart';

Product sampleProduct({
  String id = 'product-1',
  String name = 'Kapenta',
  String stock = '5.000',
  bool tracked = true,
}) => Product.fromJson({
  'id': id,
  'name': name,
  'sku': 'SKU-$id',
  'barcode': null,
  'description': null,
  'selling_price': '79.99',
  'stock_quantity': tracked ? stock : '0.000',
  'low_stock_threshold': '1.000',
  'track_inventory': tracked,
  'is_active': true,
  'is_low_stock': false,
});

SaleDetail sampleSale({
  SaleStatus status = SaleStatus.completed,
  bool margins = true,
}) => SaleDetail(
  id: 'sale-1',
  number: 'ZB-20260830-000001',
  status: status,
  subtotal: Money.parse('79.99', 'ZMW'),
  discount: Money.parse('0.00', 'ZMW'),
  total: Money.parse('79.99', 'ZMW'),
  paymentMethod: SalePaymentMethod.mtnMoney,
  soldAt: DateTime.utc(2026, 8, 30, 12),
  seller: 'Test Owner',
  items: [
    SaleLine(
      name: 'Kapenta',
      quantity: Quantity.parse('1.000'),
      unitPrice: Money.parse('79.99', 'ZMW'),
      lineTotal: Money.parse('79.99', 'ZMW'),
      unitCost: margins ? Money.parse('30.00', 'ZMW') : null,
    ),
  ],
  totalCost: margins ? Money.parse('30.00', 'ZMW') : null,
  grossProfit: margins ? Money.parse('49.99', 'ZMW') : null,
  voidReason: status == SaleStatus.voided ? 'Customer cancelled' : null,
  voidedBy: status == SaleStatus.voided ? 'Manager' : null,
  voidedAt: status == SaleStatus.voided ? DateTime.utc(2026, 8, 30, 13) : null,
);

class FakeProducts implements ProductGateway {
  FakeProducts(this.items);
  final List<Product> items;
  @override
  Future<ProductPage> list(
    String businessId, {
    int page = 1,
    String? search,
    bool lowStock = false,
  }) async => ProductPage(
    items
        .where(
          (p) =>
              search == null ||
              p.name.toLowerCase().contains(search.toLowerCase()),
        )
        .toList(),
    page,
    20,
    items.length,
  );
  @override
  Future<Product> create(String a, Map<String, dynamic> b) =>
      throw UnimplementedError();
  @override
  Future<List<InventoryMovement>> history(String a, String b) =>
      throw UnimplementedError();
  @override
  Future<Product> setActive(String a, String b, bool c) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> stock(
    String a,
    String b,
    String c,
    Map<String, dynamic> d,
  ) => throw UnimplementedError();
}

class FakeSales implements SaleGateway {
  int createCalls = 0;
  Object? createError;
  Completer<void>? gate;
  final List<Map<String, dynamic>> payloads = [];
  SaleDetail current = sampleSale();
  List<SaleSummary> summaries = [];
  @override
  Future<SaleDetail> create(
    String a,
    String b,
    Map<String, dynamic> payload,
  ) async {
    createCalls++;
    payloads.add(payload);
    if (gate != null) await gate!.future;
    if (createError != null) throw createError!;
    return current;
  }

  @override
  Future<SaleDetail> detail(String a, String b, String c) async => current;
  @override
  Future<SalePage> list(
    String a,
    String b, {
    int page = 1,
    String? search,
    String? status,
  }) async => SalePage(summaries, page, 20, summaries.length);
  @override
  Future<ReceiptData> receipt(String a, String b) async => ReceiptData(
    businessName: 'Brown Tech',
    currency: 'ZMW',
    saleNumber: current.number,
    status: current.status,
    soldAt: current.soldAt,
    seller: current.seller,
    items: current.items,
    subtotal: current.subtotal,
    discount: current.discount,
    total: current.total,
    paymentMethod: current.paymentMethod,
    phone: '+260970000000',
    location: 'Lusaka',
  );
  @override
  Future<SaleDetail> voidSale(
    String a,
    String b,
    String c, {
    required String operationId,
    required String reason,
  }) async {
    current = sampleSale(status: SaleStatus.voided);
    return current;
  }
}

AppController controller(
  FakeSales sales,
  FakeProducts products, {
  BusinessSummary business = testBusinessA,
}) => AppController(
  authGateway: FakeAuthGateway(sessionAvailable: true),
  businessGateway: FakeBusinessGateway(businesses: [business]),
  commercialGateway: FakeCommercialGateway(),
  adminGateway: FakeAdminGateway(),
  productGateway: products,
  saleGateway: sales,
);

void main() {
  test('cart add remove exact totals and fractional stock validation', () {
    final sales = FakeSales();
    final cart = SaleCartController(
      gateway: sales,
      businessId: 'b',
      currency: 'ZMW',
      operationId: 'operation-1',
    );
    final p = sampleProduct();
    cart.add(p);
    cart.setQuantity(p, Quantity.parse('0.500'));
    expect(cart.subtotal.decimal, '40.00');
    expect(
      () => cart.setQuantity(p, Quantity.parse('5.001')),
      throwsStateError,
    );
    cart.remove(p.id);
    expect(cart.lines, isEmpty);
  });

  test(
    'operation ID is stable, double submit is blocked, and success clears cart',
    () async {
      final sales = FakeSales()..gate = Completer<void>();
      final cart = SaleCartController(
        gateway: sales,
        businessId: 'b',
        currency: 'ZMW',
        operationId: 'stable-id',
      );
      cart.add(sampleProduct());
      final first = cart.complete();
      final second = await cart.complete();
      expect(second, isNull);
      expect(sales.createCalls, 1);
      expect(sales.payloads.single['client_operation_id'], 'stable-id');
      sales.gate!.complete();
      expect(await first, isNotNull);
      expect(cart.lines, isEmpty);
      expect(cart.operationId, isNot('stable-id'));
    },
  );

  test('failed sale retains cart and operation ID for safe retry', () async {
    final sales = FakeSales()..createError = const ApiException('Offline');
    final cart = SaleCartController(
      gateway: sales,
      businessId: 'b',
      currency: 'ZMW',
      operationId: 'retry-id',
    );
    cart.add(sampleProduct());
    expect(await cart.complete(), isNull);
    expect(cart.lines, hasLength(1));
    expect(cart.operationId, 'retry-id');
    sales.createError = null;
    expect(await cart.complete(), isNotNull);
    expect(
      sales.payloads.every((p) => p['client_operation_id'] == 'retry-id'),
      isTrue,
    );
  });

  testWidgets('product search adds item and exposes payment selection', (
    tester,
  ) async {
    final sales = FakeSales();
    final c = controller(
      sales,
      FakeProducts([
        sampleProduct(),
        sampleProduct(id: 'service', name: 'Cleaning', tracked: false),
      ]),
    );
    await c.initialize();
    await tester.pumpWidget(MaterialApp(home: NewSaleScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('Kapenta'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
    await tester.pump();
    expect(find.text('Cart'), findsOneWidget);
    expect(find.textContaining('79.99 × 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('continue-sale')));
    await tester.pumpAndSettle();
    expect(find.text('MTN Money'), findsOneWidget);
    expect(find.byKey(const Key('complete-sale')), findsOneWidget);
  });

  testWidgets('sale list shows VOIDED and expired history stays readable', (
    tester,
  ) async {
    final sales = FakeSales()
      ..summaries = [
        SaleSummary(
          id: 'sale-1',
          number: 'ZB-20260830-000001',
          status: SaleStatus.voided,
          total: Money.parse('79.99', 'ZMW'),
          paymentMethod: SalePaymentMethod.cash,
          soldAt: DateTime.utc(2026, 8, 30),
          seller: 'Cashier',
        ),
      ];
    final c = controller(sales, FakeProducts([]));
    await c.initialize();
    await tester.pumpWidget(
      MaterialApp(home: SalesScreen(controller: c, writable: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sales are read-only'), findsOneWidget);
    expect(find.text('VOIDED'), findsOneWidget);
    expect(find.byKey(const Key('new-sale')), findsNothing);
  });

  testWidgets('cashier sale detail has no void control or margins', (
    tester,
  ) async {
    const cashier = BusinessSummary(
      id: 'business-a',
      name: 'Brown Tech',
      role: BusinessRole.cashier,
      currency: 'ZMW',
      timezone: 'Africa/Lusaka',
    );
    final sales = FakeSales()..current = sampleSale(margins: false);
    final c = controller(sales, FakeProducts([]), business: cashier);
    await c.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: SaleDetailScreen(
          controller: c,
          saleId: 'sale-1',
          writable: true,
          canVoid: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('VOID SALE'), findsNothing);
    expect(find.text('Gross profit'), findsNothing);
    expect(find.text('VIEW RECEIPT'), findsOneWidget);
  });

  testWidgets('receipt displays customer-safe values and share action', (
    tester,
  ) async {
    final sales = FakeSales();
    final c = controller(sales, FakeProducts([]));
    await c.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: ReceiptScreen(controller: c, saleId: 'sale-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SALES RECEIPT'), findsOneWidget);
    expect(find.text('ZB-20260830-000001'), findsOneWidget);
    expect(find.text('Gross profit'), findsNothing);
    expect(find.text('SHARE'), findsOneWidget);
  });
}
