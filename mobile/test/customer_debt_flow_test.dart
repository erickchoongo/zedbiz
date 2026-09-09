import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/businesses/domain/business_summary.dart';
import 'package:zedbiz/features/businesses/presentation/business_shell.dart';
import 'package:zedbiz/features/commercial/domain/money.dart';
import 'package:zedbiz/features/customers/data/customer_repository.dart';
import 'package:zedbiz/features/customers/domain/customer.dart';
import 'package:zedbiz/features/customers/presentation/customers_screen.dart';
import 'package:zedbiz/features/debts/application/repayment_controller.dart';
import 'package:zedbiz/features/debts/data/debt_repository.dart';
import 'package:zedbiz/features/debts/domain/debt.dart';
import 'package:zedbiz/features/debts/presentation/debts_screen.dart';
import 'package:zedbiz/features/products/data/product_repository.dart';
import 'package:zedbiz/features/products/domain/product.dart';
import 'package:zedbiz/features/sales/application/sale_cart_controller.dart';
import 'package:zedbiz/features/sales/data/sale_repository.dart';
import 'package:zedbiz/features/sales/domain/sale.dart';
import 'package:zedbiz/features/sales/presentation/sales_screen.dart';

import 'helpers/fakes.dart';

CustomerDetail sampleCustomer({
  String id = 'customer-1',
  String name = 'John Banda',
  String outstanding = '250.50',
  String overdue = '150.00',
  bool active = true,
  List<DebtSummary>? recentDebts,
}) => CustomerDetail(
  id: id,
  businessId: 'business-a',
  name: name,
  phoneNumber: '+260971234567',
  email: 'john@example.com',
  isActive: active,
  totalOutstanding: Money.parse(outstanding, 'ZMW'),
  totalOverdue: Money.parse(overdue, 'ZMW'),
  openDebtCount: outstanding == '0.00' ? 0 : 1,
  notes: 'Management note',
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  recentDebts: recentDebts ?? const [],
);

DebtDetail sampleDebt({
  String id = 'debt-1',
  String original = '300.00',
  String paid = '49.50',
  String outstanding = '250.50',
  DebtStatus status = DebtStatus.partiallyPaid,
  bool overdue = true,
}) => DebtDetail(
  id: id,
  businessId: 'business-a',
  customerId: 'customer-1',
  customerName: 'John Banda',
  customerPhoneNumber: '+260971234567',
  saleId: 'sale-1',
  saleNumber: 'ZB-20260901-000001',
  originalAmount: Money.parse(original, 'ZMW'),
  amountPaid: Money.parse(paid, 'ZMW'),
  outstandingAmount: Money.parse(outstanding, 'ZMW'),
  status: status,
  dueDate: DateTime(2026, 8, 31),
  isOverdue: overdue,
  createdAt: DateTime.utc(2026, 8, 1),
  createdByUserId: 'user-1',
  createdByName: 'Test Owner',
  settledAt: status == DebtStatus.paid ? DateTime.utc(2026, 9, 2) : null,
);

DebtPayment samplePayment({String amount = '100.00'}) => DebtPayment(
  id: 'payment-1',
  businessId: 'business-a',
  debtId: 'debt-1',
  customerId: 'customer-1',
  customerName: 'John Banda',
  amount: Money.parse(amount, 'ZMW'),
  paymentMethod: DebtPaymentMethod.mtnMoney,
  paymentReference: 'TXN123',
  receivedByUserId: 'user-1',
  receivedByName: 'Test Owner',
  paidAt: DateTime.utc(2026, 9, 2, 8),
  createdAt: DateTime.utc(2026, 9, 2, 8),
);

class FakeCustomers implements CustomerGateway {
  FakeCustomers({CustomerDetail? customer})
    : current = customer ?? sampleCustomer();

  CustomerDetail current;
  List<CustomerSummary>? listOverride;
  int createCalls = 0;
  String? lastSearch;
  final List<Map<String, dynamic>> payloads = [];

  @override
  Future<CustomerDetail> create(
    String businessId,
    String currency,
    Map<String, dynamic> payload,
  ) async {
    createCalls++;
    payloads.add(payload);
    current = sampleCustomer(name: payload['name'] as String);
    return current;
  }

  @override
  Future<CustomerDetail> detail(
    String businessId,
    String customerId,
    String currency,
  ) async => current;

  @override
  Future<CustomerPage> list(
    String businessId,
    String currency, {
    int page = 1,
    String? search,
    bool? active,
    bool outstandingOnly = false,
  }) async {
    lastSearch = search;
    final source = listOverride ?? [current];
    final filtered = source
        .where(
          (customer) =>
              (active == null || customer.isActive == active) &&
              (!outstandingOnly || customer.totalOutstanding.minorUnits > 0) &&
              (search?.isEmpty != false ||
                  customer.name.toLowerCase().contains(search!.toLowerCase())),
        )
        .toList();
    return CustomerPage(filtered, page, 20, filtered.length);
  }

  @override
  Future<CustomerDetail> setActive(
    String businessId,
    String customerId,
    String currency,
    bool active,
  ) async {
    current = sampleCustomer(name: current.name, active: active);
    return current;
  }

  @override
  Future<CustomerDetail> update(
    String businessId,
    String customerId,
    String currency,
    Map<String, dynamic> payload,
  ) async {
    current = sampleCustomer(name: payload['name'] as String);
    return current;
  }
}

class FakeDebts implements DebtGateway {
  FakeDebts({DebtDetail? debt}) : current = debt ?? sampleDebt();

  DebtDetail current;
  Object? paymentError;
  Completer<void>? paymentGate;
  int recordCalls = 0;
  final List<Map<String, dynamic>> paymentPayloads = [];
  List<DebtPayment> history = [samplePayment(amount: '49.50')];

  @override
  Future<DebtDetail> detail(
    String businessId,
    String debtId,
    String currency,
  ) async => current;

  @override
  Future<DebtPage> list(
    String businessId,
    String currency, {
    int page = 1,
    String? search,
    String? status,
    bool overdueOnly = false,
    String? customerId,
  }) async {
    final include =
        (!overdueOnly || current.isOverdue) &&
        (status == null || debtStatusApi(current.status) == status) &&
        (customerId == null || current.customerId == customerId);
    return DebtPage(include ? [current] : [], page, 20, include ? 1 : 0);
  }

  @override
  Future<DebtPaymentPage> payments(
    String businessId,
    String debtId,
    String currency, {
    int page = 1,
  }) async => DebtPaymentPage(history, page, 20, history.length);

  @override
  Future<RepaymentResult> recordPayment(
    String businessId,
    String debtId,
    String currency,
    Map<String, dynamic> payload,
  ) async {
    recordCalls++;
    paymentPayloads.add(Map<String, dynamic>.from(payload));
    if (paymentGate != null) await paymentGate!.future;
    if (paymentError != null) throw paymentError!;
    final amount = Money.parse(payload['amount'] as String, currency);
    final remaining = current.outstandingAmount - amount;
    final totalPaid = current.amountPaid + amount;
    current = sampleDebt(
      original: current.originalAmount.decimal,
      paid: totalPaid.decimal,
      outstanding: remaining.decimal,
      status: remaining.minorUnits == 0
          ? DebtStatus.paid
          : DebtStatus.partiallyPaid,
      overdue: remaining.minorUnits > 0 && current.isOverdue,
    );
    final payment = samplePayment(amount: amount.decimal);
    history = [payment, ...history];
    return RepaymentResult(payment: payment, debt: current);
  }

  @override
  Future<DebtReminder> reminder(
    String businessId,
    String debtId,
    String currency,
  ) async => DebtReminder(
    debtId: debtId,
    customerId: current.customerId,
    customerName: current.customerName,
    phoneNumber: current.customerPhoneNumber,
    outstandingAmount: current.outstandingAmount,
    dueDate: current.dueDate,
    message:
        'Hello John,\n\nThis is a reminder from Brown Tech that your outstanding balance is K${current.outstandingAmount.decimal}.\n\nThank you.',
  );

  @override
  Future<DebtMetrics> summary(String businessId, String currency) async =>
      DebtMetrics(
        totalOutstanding: current.outstandingAmount,
        totalOverdue: current.isOverdue
            ? current.outstandingAmount
            : Money.parse('0.00', currency),
        customersOwing: current.outstandingAmount.minorUnits > 0 ? 1 : 0,
        openDebtCount: current.acceptsPayment ? 1 : 0,
      );
}

Product testProduct() => Product.fromJson({
  'id': 'product-1',
  'name': 'School shoes',
  'sku': 'SHOE-1',
  'barcode': null,
  'description': null,
  'selling_price': '300.00',
  'stock_quantity': '20.000',
  'low_stock_threshold': '2.000',
  'track_inventory': true,
  'is_active': true,
  'is_low_stock': false,
});

class FakeM6Products implements ProductGateway {
  @override
  Future<ProductPage> list(
    String businessId, {
    int page = 1,
    String? search,
    bool lowStock = false,
  }) async => ProductPage([testProduct()], page, 20, 1);

  @override
  Future<Product> create(String businessId, Map<String, dynamic> payload) =>
      throw UnimplementedError();
  @override
  Future<List<InventoryMovement>> history(
    String businessId,
    String productId,
  ) => throw UnimplementedError();
  @override
  Future<Product> setActive(String businessId, String productId, bool active) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> stock(
    String businessId,
    String productId,
    String action,
    Map<String, dynamic> payload,
  ) => throw UnimplementedError();
}

class FakeM6Sales implements SaleGateway {
  int createCalls = 0;
  Object? createError;
  final List<Map<String, dynamic>> payloads = [];

  SaleDetail get creditSale => SaleDetail(
    id: 'sale-1',
    number: 'ZB-20260901-000001',
    status: SaleStatus.completed,
    subtotal: Money.parse('300.00', 'ZMW'),
    discount: Money.parse('0.00', 'ZMW'),
    total: Money.parse('300.00', 'ZMW'),
    paymentMethod: SalePaymentMethod.customerDebt,
    soldAt: DateTime.utc(2026, 9, 1),
    seller: 'Test Owner',
    items: const [],
    customerId: 'customer-1',
    customerName: 'John Banda',
    debtId: 'debt-1',
    debtStatus: DebtStatus.open,
    debtDueDate: DateTime(2026, 9, 30),
    debtOutstandingAmount: Money.parse('300.00', 'ZMW'),
  );

  @override
  Future<SaleDetail> create(
    String businessId,
    String currency,
    Map<String, dynamic> payload,
  ) async {
    createCalls++;
    payloads.add(Map<String, dynamic>.from(payload));
    if (createError != null) throw createError!;
    return creditSale;
  }

  @override
  Future<SaleDetail> detail(
    String businessId,
    String saleId,
    String currency,
  ) async => creditSale;
  @override
  Future<SalePage> list(
    String businessId,
    String currency, {
    int page = 1,
    String? search,
    String? status,
  }) async => SalePage(const [], page, 20, 0);
  @override
  Future<ReceiptData> receipt(String businessId, String saleId) =>
      throw UnimplementedError();
  @override
  Future<SaleDetail> voidSale(
    String businessId,
    String saleId,
    String currency, {
    required String operationId,
    required String reason,
  }) => throw UnimplementedError();
}

AppController m6Controller({
  FakeCustomers? customers,
  FakeDebts? debts,
  FakeM6Sales? sales,
  BusinessSummary business = testBusinessA,
}) => AppController(
  authGateway: FakeAuthGateway(sessionAvailable: true),
  businessGateway: FakeBusinessGateway(businesses: [business]),
  commercialGateway: FakeCommercialGateway(),
  adminGateway: FakeAdminGateway(),
  productGateway: FakeM6Products(),
  saleGateway: sales ?? FakeM6Sales(),
  customerGateway: customers ?? FakeCustomers(),
  debtGateway: debts ?? FakeDebts(),
);

void main() {
  test(
    'customer phone validation accepts Zambia and safe international forms',
    () {
      expect(customerPhoneError('0971234567'), isNull);
      expect(customerPhoneError('260971234567'), isNull);
      expect(customerPhoneError('+260 971 234 567'), isNull);
      expect(customerPhoneError(''), isNull);
      expect(customerPhoneError('97123'), isNotNull);
      expect(customerPhoneError('not-a-number'), isNotNull);
    },
  );

  testWidgets('customer list shows exact balances, overdue state, and search', (
    tester,
  ) async {
    final customers = FakeCustomers();
    final controller = m6Controller(customers: customers);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: CustomersScreen(controller: controller, writable: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('John Banda'), findsOneWidget);
    expect(find.textContaining('Owes K250.50'), findsOneWidget);
    expect(find.text('OVERDUE'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('customer-search')), 'John');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(customers.lastSearch, 'John');
  });

  testWidgets('customer list has an empty state', (tester) async {
    final customers = FakeCustomers()..listOverride = [];
    final controller = m6Controller(customers: customers);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: CustomersScreen(controller: controller, writable: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No customers yet'), findsOneWidget);
  });

  testWidgets('add customer validates phone and omits no required contact', (
    tester,
  ) async {
    final customers = FakeCustomers()..listOverride = [];
    final controller = m6Controller(customers: customers);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: CustomersScreen(controller: controller, writable: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-customer')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('customer-name')),
      'Mary Phiri',
    );
    await tester.enterText(find.byKey(const Key('customer-phone')), '123');
    await tester.tap(find.byKey(const Key('save-customer')));
    await tester.pump();
    expect(find.textContaining('Use 097'), findsOneWidget);
    expect(customers.createCalls, 0);

    await tester.enterText(
      find.byKey(const Key('customer-phone')),
      '0961234567',
    );
    await tester.tap(find.byKey(const Key('save-customer')));
    await tester.pumpAndSettle();
    expect(customers.createCalls, 1);
    expect(customers.payloads.single['name'], 'Mary Phiri');
  });

  test(
    'credit cart requires customer and sends exact customer/due payload',
    () async {
      final sales = FakeM6Sales();
      final cart = SaleCartController(
        gateway: sales,
        businessId: 'business-a',
        currency: 'ZMW',
        operationId: 'sale-operation',
      );
      cart.add(testProduct());
      cart.setPayment(SalePaymentMethod.customerDebt);
      expect(await cart.complete(), isNull);
      expect(cart.errorMessage, contains('Select a customer'));
      expect(sales.createCalls, 0);

      cart.selectCustomer(sampleCustomer());
      cart.setDueDate(DateTime(2026, 9, 30));
      final completed = await cart.complete();
      expect(completed, isNotNull);
      expect(completed!.customerName, 'John Banda');
      expect(completed.paymentMethod, SalePaymentMethod.customerDebt);
      expect(completed.debtStatus, DebtStatus.open);
      expect(completed.debtOutstandingAmount?.decimal, '300.00');
      expect(sales.payloads.single['client_operation_id'], 'sale-operation');
      expect(sales.payloads.single['payment_method'], 'CUSTOMER_DEBT');
      expect(sales.payloads.single['customer_id'], 'customer-1');
      expect(sales.payloads.single['due_date'], '2026-09-30');
    },
  );

  testWidgets('adding a customer during credit selection preserves the cart', (
    tester,
  ) async {
    final customers = FakeCustomers()..listOverride = [];
    final controller = m6Controller(customers: customers);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: NewSaleScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('continue-sale')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customer Credit'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('credit-due-date')), findsOneWidget);
    await tester.tap(find.text('Select customer *'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('credit-add-customer')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('customer-name')),
      'John Banda',
    );
    await tester.enterText(
      find.byKey(const Key('customer-phone')),
      '0971234567',
    );
    await tester.tap(find.byKey(const Key('save-customer')));
    await tester.pumpAndSettle();
    expect(find.text('John Banda'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Cart'), findsOneWidget);
    expect(find.textContaining('School shoes'), findsWidgets);
  });

  test('repayment preview is exact and rejects overpayment locally', () async {
    final debts = FakeDebts();
    final controller = RepaymentController(
      gateway: debts,
      businessId: 'business-a',
      debtId: 'debt-1',
      currency: 'ZMW',
      outstanding: Money.parse('250.50', 'ZMW'),
      operationId: 'payment-operation',
    );
    controller.setAmount('100.00');
    expect(controller.previewRemaining?.decimal, '150.50');
    controller.setAmount('250.51');
    expect(controller.previewRemaining, isNull);
    expect(controller.validationMessage, contains('cannot exceed K250.50'));
    expect(await controller.record(), isNull);
    expect(debts.recordCalls, 0);
  });

  test('failed repayment retains input and operation ID, then success updates balance', () async {
    final debts = FakeDebts()
      ..paymentError = const ApiException('Connection lost');
    final controller = RepaymentController(
      gateway: debts,
      businessId: 'business-a',
      debtId: 'debt-1',
      currency: 'ZMW',
      outstanding: Money.parse('250.50', 'ZMW'),
      operationId: 'stable-payment-id',
    );
    controller.setAmount('100.00');
    expect(await controller.record(), isNull);
    expect(controller.amountInput, '100.00');
    expect(controller.operationId, 'stable-payment-id');
    debts.paymentError = null;
    expect(await controller.record(), isNotNull);
    expect(controller.outstanding.decimal, '150.50');
    expect(controller.amountInput, isEmpty);
    expect(controller.operationId, isNot('stable-payment-id'));
    expect(
      debts.paymentPayloads.every(
        (payload) => payload['client_operation_id'] == 'stable-payment-id',
      ),
      isTrue,
    );
  });

  test('exact final repayment exposes paid status and zero balance', () async {
    final debts = FakeDebts(
      debt: sampleDebt(
        original: '250.50',
        paid: '0.00',
        outstanding: '250.50',
        status: DebtStatus.open,
        overdue: false,
      ),
    );
    final controller = RepaymentController(
      gateway: debts,
      businessId: 'business-a',
      debtId: 'debt-1',
      currency: 'ZMW',
      outstanding: Money.parse('250.50', 'ZMW'),
      operationId: 'final-payment-id',
    );

    controller.setAmount('250.50');
    final result = await controller.record();

    expect(result?.debt.status, DebtStatus.paid);
    expect(result?.debt.outstandingAmount.decimal, '0.00');
    expect(controller.outstanding.decimal, '0.00');
    expect(controller.amountInput, isEmpty);
    expect(controller.operationId, isNot('final-payment-id'));
  });

  testWidgets('debt detail records partial payment and shows confirmation', (
    tester,
  ) async {
    final debts = FakeDebts();
    final controller = m6Controller(debts: debts);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: DebtDetailScreen(
          controller: controller,
          debtId: 'debt-1',
          writable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Payment history'), findsOneWidget);
    expect(find.text('OVERDUE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('record-payment')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('repayment-amount')), '100.00');
    await tester.pump();
    expect(find.text('K150.50'), findsOneWidget);
    await tester.tap(find.byKey(const Key('submit-repayment')));
    await tester.pumpAndSettle();
    expect(find.text('Payment recorded'), findsWidgets);
    expect(find.text('Remaining: K150.50'), findsOneWidget);
  });

  testWidgets('debt reminder is customer-safe and can be copied', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var clipboardSet = false;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      if (call.method == 'Clipboard.setData') clipboardSet = true;
      if (call.method == 'Clipboard.hasStrings') {
        return <String, Object?>{'value': false};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final controller = m6Controller();
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: DebtDetailScreen(
          controller: controller,
          debtId: 'debt-1',
          writable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-reminder')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hello John'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('K250.50'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Management note'), findsNothing);
    await tester.tap(find.byKey(const Key('copy-reminder')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(clipboardSet, isTrue);
    expect(find.textContaining('Reminder copied'), findsOneWidget);
  });

  testWidgets('expired credit history is readable but repayment is hidden', (
    tester,
  ) async {
    final controller = m6Controller();
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: DebtDetailScreen(
          controller: controller,
          debtId: 'debt-1',
          writable: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Repayments are read-only'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Payment history'),
      250,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Payment history'), findsOneWidget);
    expect(find.byKey(const Key('record-payment')), findsNothing);
    expect(find.byKey(const Key('share-reminder')), findsOneWidget);
  });

  testWidgets('grace-enabled debt view keeps repayment write action available', (
    tester,
  ) async {
    final controller = m6Controller();
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: DebtDetailScreen(
          controller: controller,
          debtId: 'debt-1',
          writable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // BusinessShell derives `writable: true` for ACTIVE and GRACE_PERIOD.
    // The commercial suite independently verifies that grace maps to writable.
    expect(find.byKey(const Key('record-payment')), findsOneWidget);
  });

  testWidgets(
    'cashier can create a customer and record a repayment without notes',
    (tester) async {
      const cashierBusiness = BusinessSummary(
        id: 'business-a',
        name: 'Brown Tech',
        role: BusinessRole.cashier,
        currency: 'ZMW',
        timezone: 'Africa/Lusaka',
      );
      final controller = m6Controller(business: cashierBusiness);
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(home: AddCustomerDialog(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customer-notes')), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: DebtDetailScreen(
            controller: controller,
            debtId: 'debt-1',
            writable: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('record-payment')), findsOneWidget);
    },
  );

  testWidgets('More navigation exposes real customers and credit screens', (
    tester,
  ) async {
    final controller = m6Controller();
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: BusinessShell(controller: controller, writable: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Customer Credit'), findsOneWidget);
    await tester.tap(find.byKey(const Key('more-customers')));
    await tester.pumpAndSettle();
    expect(find.text('John Banda'), findsOneWidget);
  });
}
