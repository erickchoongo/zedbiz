import 'package:flutter/foundation.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/commercial/domain/money.dart';
import 'package:zedbiz/features/customers/domain/customer.dart';
import 'package:zedbiz/features/products/data/product_repository.dart';
import 'package:zedbiz/features/products/domain/product.dart';
import 'package:zedbiz/features/sales/data/sale_repository.dart';
import 'package:zedbiz/features/sales/domain/sale.dart';

class CartLine {
  const CartLine(this.product, this.quantity);
  final Product product;
  final Quantity quantity;
  Money total(String currency) => Money.parse(
    product.sellingPrice,
    currency,
  ).multiplyThousandths(quantity.thousandths);
}

class SaleCartController extends ChangeNotifier {
  SaleCartController({
    required this.gateway,
    required this.businessId,
    required this.currency,
    String? operationId,
  }) : _operationId = operationId ?? newOperationId();
  final SaleGateway gateway;
  final String businessId, currency;
  String _operationId;
  final Map<String, CartLine> _lines = {};
  SalePaymentMethod paymentMethod = SalePaymentMethod.cash;
  String? paymentReference, notes, errorMessage;
  CustomerSummary? selectedCustomer;
  DateTime? dueDate;
  Money? _discount;
  bool busy = false;
  SaleDetail? completedSale;
  List<CartLine> get lines => List.unmodifiable(_lines.values);
  String get operationId => _operationId;
  Money get subtotal => _lines.values.fold(
    Money.fromMinorUnits(0, currency),
    (sum, line) => sum + line.total(currency),
  );
  Money get discount => _discount ?? Money.fromMinorUnits(0, currency);
  Money get total => subtotal - discount;
  void add(Product product) {
    if (!product.isActive) {
      throw StateError('This product is inactive.');
    }
    if (product.trackInventory && product.stockQuantity.thousandths <= 0) {
      throw StateError('${product.name} is out of stock.');
    }
    final existing = _lines[product.id];
    final current = existing?.quantity.thousandths ?? 0;
    final next =
        current == 0 &&
            product.trackInventory &&
            product.stockQuantity.thousandths < 1000
        ? product.stockQuantity.thousandths
        : current + 1000;
    setQuantity(product, Quantity.fromThousandths(next));
  }

  void setQuantity(Product product, Quantity quantity) {
    if (quantity.thousandths <= 0) {
      _lines.remove(product.id);
      notifyListeners();
      return;
    }
    if (product.trackInventory &&
        quantity.thousandths > product.stockQuantity.thousandths) {
      throw StateError('Only ${product.stockQuantity.display} available.');
    }
    _lines[product.id] = CartLine(product, quantity);
    _clampDiscount();
    notifyListeners();
  }

  void decrement(Product product) {
    final current = _lines[product.id];
    if (current == null) return;
    final next = current.quantity.thousandths - 1000;
    if (next <= 0) {
      remove(product.id);
    } else {
      setQuantity(product, Quantity.fromThousandths(next));
    }
  }

  void remove(String productId) {
    _lines.remove(productId);
    _clampDiscount();
    notifyListeners();
  }

  void _clampDiscount() {
    if ((_discount?.minorUnits ?? 0) > subtotal.minorUnits) {
      _discount = Money.fromMinorUnits(0, currency);
    }
  }

  void setDiscount(String value) {
    final parsed = Money.parse(value.isEmpty ? '0' : value, currency);
    if (parsed.minorUnits > subtotal.minorUnits) {
      throw StateError('Discount cannot exceed subtotal.');
    }
    _discount = parsed;
    notifyListeners();
  }

  void setPayment(SalePaymentMethod value) {
    paymentMethod = value;
    if (value != SalePaymentMethod.customerDebt) {
      selectedCustomer = null;
      dueDate = null;
    }
    notifyListeners();
  }

  void selectCustomer(CustomerSummary customer) {
    if (!customer.isActive) {
      throw StateError('Select an active customer for customer credit.');
    }
    selectedCustomer = customer;
    errorMessage = null;
    notifyListeners();
  }

  void setDueDate(DateTime? value) {
    dueDate = value == null
        ? null
        : DateTime(value.year, value.month, value.day);
    notifyListeners();
  }

  Future<SaleDetail?> complete() async {
    if (busy || _lines.isEmpty) return null;
    if (paymentMethod == SalePaymentMethod.customerDebt &&
        selectedCustomer == null) {
      errorMessage = 'Select a customer for Customer Credit.';
      notifyListeners();
      return null;
    }
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await gateway.create(businessId, currency, {
        'client_operation_id': _operationId,
        'items': _lines.values
            .map(
              (line) => {
                'product_id': line.product.id,
                'quantity': line.quantity.apiValue,
                if (line.product.saleVersion != null)
                  'sale_version': line.product.saleVersion,
              },
            )
            .toList(),
        'payment_method': paymentApi(paymentMethod),
        'customer_id': paymentMethod == SalePaymentMethod.customerDebt
            ? selectedCustomer!.id
            : null,
        'due_date':
            paymentMethod == SalePaymentMethod.customerDebt && dueDate != null
            ? _dateOnly(dueDate!)
            : null,
        'payment_reference': paymentReference?.trim().isEmpty == true
            ? null
            : paymentReference?.trim(),
        'discount_amount': discount.decimal,
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      });
      completedSale = result;
      _lines.clear();
      _discount = null;
      selectedCustomer = null;
      dueDate = null;
      _operationId = newOperationId();
      return result;
    } on ApiException catch (e) {
      errorMessage = e.message;
      return null;
    } on Object {
      errorMessage = 'Could not complete the sale. Your cart is safe; retry when connected.';
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
