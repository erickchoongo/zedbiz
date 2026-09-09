import 'package:flutter/foundation.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/commercial/domain/money.dart';
import 'package:zedbiz/features/debts/data/debt_repository.dart';
import 'package:zedbiz/features/debts/domain/debt.dart';
import 'package:zedbiz/features/products/data/product_repository.dart';

class RepaymentController extends ChangeNotifier {
  RepaymentController({
    required this.gateway,
    required this.businessId,
    required this.debtId,
    required this.currency,
    required this.outstanding,
    String? operationId,
  }) : _operationId = operationId ?? newOperationId();

  final DebtGateway gateway;
  final String businessId, debtId, currency;
  String _operationId;
  Money outstanding;

  String amountInput = '';
  String? paymentReference, notes, errorMessage;
  DebtPaymentMethod paymentMethod = DebtPaymentMethod.cash;
  bool busy = false;
  RepaymentResult? completedResult;

  String get operationId => _operationId;
  Money? get enteredAmount {
    try {
      return Money.parse(amountInput.trim(), currency);
    } on FormatException {
      return null;
    }
  }

  Money? get previewRemaining {
    final amount = enteredAmount;
    if (amount == null ||
        amount.minorUnits <= 0 ||
        amount.minorUnits > outstanding.minorUnits) {
      return null;
    }
    return outstanding - amount;
  }

  String? get validationMessage {
    final amount = enteredAmount;
    if (amount == null) return 'Enter an amount with up to 2 decimal places.';
    if (amount.minorUnits <= 0) {
      return 'Payment amount must be greater than zero.';
    }
    if (amount.minorUnits > outstanding.minorUnits) {
      return 'Payment cannot exceed K${outstanding.decimal} outstanding.';
    }
    return null;
  }

  void setAmount(String value) {
    amountInput = value;
    errorMessage = null;
    notifyListeners();
  }

  void setPaymentMethod(DebtPaymentMethod value) {
    paymentMethod = value;
    notifyListeners();
  }

  Future<RepaymentResult?> record() async {
    if (busy) return null;
    final validation = validationMessage;
    if (validation != null) {
      errorMessage = validation;
      notifyListeners();
      return null;
    }
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await gateway.recordPayment(businessId, debtId, currency, {
        'client_operation_id': _operationId,
        'amount': enteredAmount!.decimal,
        'payment_method': debtPaymentApi(paymentMethod),
        'payment_reference': _clean(paymentReference),
        'notes': _clean(notes),
      });
      completedResult = result;
      outstanding = result.debt.outstandingAmount;
      amountInput = '';
      paymentReference = null;
      notes = null;
      _operationId = newOperationId();
      return result;
    } on ApiException catch (error) {
      errorMessage = error.message;
      return null;
    } on Object {
      errorMessage = 'Could not record the payment. Your entry is safe; retry when connected.';
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String? _clean(String? value) {
    final result = value?.trim();
    return result == null || result.isEmpty ? null : result;
  }
}
