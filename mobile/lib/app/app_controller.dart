import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:zedbiz/core/offline/offline_client.dart';
import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/auth/data/auth_repository.dart';
import 'package:zedbiz/features/auth/domain/user_profile.dart';
import 'package:zedbiz/features/businesses/data/business_repository.dart';
import 'package:zedbiz/features/businesses/domain/business_summary.dart';
import 'package:zedbiz/features/commercial/data/commercial_repository.dart';
import 'package:zedbiz/features/commercial/domain/commercial_status.dart';
import 'package:zedbiz/features/admin/data/admin_repository.dart';
import 'package:zedbiz/features/customers/data/customer_repository.dart';
import 'package:zedbiz/features/debts/data/debt_repository.dart';
import 'package:zedbiz/features/expenses/data/expense_repository.dart';
import 'package:zedbiz/features/products/data/product_repository.dart';
import 'package:zedbiz/features/reporting/data/reporting_repository.dart';
import 'package:zedbiz/features/sales/data/sale_repository.dart';

enum SessionStatus { starting, signedOut, signedIn }

class AppController extends ChangeNotifier {
  AppController({
    this.offline,
    bool monitorConnectivity = true,
    required this.authGateway,
    required this.businessGateway,
    required this.commercialGateway,
    required this.adminGateway,
    this.productGateway = const UnavailableProductGateway(),
    this.saleGateway = const UnavailableSaleGateway(),
    this.customerGateway = const UnavailableCustomerGateway(),
    this.debtGateway = const UnavailableDebtGateway(),
    this.expenseGateway = const UnavailableExpenseGateway(),
    this.reportingGateway = const UnavailableReportingGateway(),
  }) {
    offline?.changes.addListener(_offlineChanged);
    if (offline != null) {
      offline!.membershipsVerified = (records) {
        businesses = records.map(BusinessSummary.fromJson).toList();
        final selected = selectedBusiness;
        if (selected != null) {
          final matches = businesses.where((b) => b.id == selected.id);
          selectedBusiness = matches.isEmpty ? null : matches.single;
        }
        notifyListeners();
      };
      if (monitorConnectivity) {
        _connectivity = Connectivity().onConnectivityChanged.listen((result) {
          if (result.contains(ConnectivityResult.none)) {
            offline!.online = false;
            offline!.changed();
          } else if (selectedBusiness != null &&
              status == SessionStatus.signedIn) {
            unawaited(
              offline!.syncPendingOperations(
                selectedBusiness!.id,
                manual: true,
              ),
            );
          }
        });
      }
    }
  }
  final OfflineClient? offline;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  bool get online => offline?.online ?? true;
  void _offlineChanged() => notifyListeners();
  void _openOfflineBusiness() {
    offline?.selectedBusiness = selectedBusiness?.id;
    if (selectedBusiness != null) {
      unawaited(offline?.syncPendingOperations(selectedBusiness!.id));
    }
  }

  @override
  void dispose() {
    _connectivity?.cancel();
    offline?.changes.removeListener(_offlineChanged);
    super.dispose();
  }

  final AuthGateway authGateway;
  final BusinessGateway businessGateway;
  final CommercialGateway commercialGateway;
  final AdminGateway adminGateway;
  final ProductGateway productGateway;
  final SaleGateway saleGateway;
  final CustomerGateway customerGateway;
  final DebtGateway debtGateway;
  final ExpenseGateway expenseGateway;
  final ReportingGateway reportingGateway;

  SessionStatus status = SessionStatus.starting;
  UserProfile? currentUser;
  List<BusinessSummary> businesses = const [];
  BusinessSummary? selectedBusiness;
  CommercialStatus? commercialStatus;
  bool adminMode = false;
  bool busy = false;
  String? errorMessage;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!await authGateway.hasSession()) {
      status = SessionStatus.signedOut;
      notifyListeners();
      return;
    }
    try {
      await _loadAuthenticatedContext();
    } on Object {
      await authGateway.clearSession();
      _clearAuthenticatedState();
    }
    notifyListeners();
  }

  Future<bool> login({required String email, required String password}) async {
    return _authenticate(
      () => authGateway.login(email: email, password: password),
    );
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    return _authenticate(
      () => authGateway.register(
        fullName: fullName,
        email: email,
        password: password,
      ),
    );
  }

  Future<bool> _authenticate(Future<void> Function() operation) async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await operation();
      await _loadAuthenticatedContext();
      return true;
    } on ApiException catch (error) {
      errorMessage = error.message;
      return false;
    } on Object {
      errorMessage = 'Unable to connect to ZedBiz. Please try again.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _loadAuthenticatedContext() async {
    currentUser = await authGateway.me();
    businesses = await businessGateway.listBusinesses();
    selectedBusiness = businesses.length == 1 ? businesses.single : null;
    if (selectedBusiness == null && offline != null) {
      final saved = await offline!.db.readCache(
        currentUser!.id,
        '',
        'selected_business',
      );
      final matching = businesses.where((b) => b.id == saved?.data);
      if (matching.isNotEmpty) selectedBusiness = matching.first;
    }
    if (selectedBusiness != null) await _loadCommercialStatus();
    status = SessionStatus.signedIn;
    _openOfflineBusiness();
  }

  Future<bool> createBusiness({
    required String name,
    String? businessType,
    String? phoneNumber,
    String? location,
  }) async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final business = await businessGateway.createBusiness(
        name: name,
        businessType: businessType,
        phoneNumber: phoneNumber,
        location: location,
      );
      businesses = [...businesses, business];
      selectedBusiness = business;
      await _loadCommercialStatus();
      return true;
    } on ApiException catch (error) {
      errorMessage = error.message;
      return false;
    } on Object {
      errorMessage = 'Could not create the business. Please try again.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> selectBusiness(BusinessSummary business) async {
    if (!businesses.any((candidate) => candidate.id == business.id)) return;
    selectedBusiness = business;
    if (offline != null && currentUser != null) {
      await offline!.db.cache(
        currentUser!.id,
        '',
        'selected_business',
        business.id,
      );
    }
    commercialStatus = null;
    errorMessage = null;
    notifyListeners();
    await refreshCommercialStatus();
    _openOfflineBusiness();
  }

  Future<void> refreshCommercialStatus() async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _loadCommercialStatus();
    } on ApiException catch (error) {
      errorMessage = error.message;
    } on Object {
      errorMessage = 'Could not load the commercial status.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _loadCommercialStatus() async {
    final business = selectedBusiness;
    if (business == null) return;
    commercialStatus = await commercialGateway.getStatus(business.id);
  }

  void openAdmin() {
    if (currentUser?.isPlatformAdmin != true) return;
    adminMode = true;
    notifyListeners();
  }

  void closeAdmin() {
    adminMode = false;
    notifyListeners();
  }

  void showBusinessList() {
    selectedBusiness = null;
    commercialStatus = null;
    notifyListeners();
  }

  Future<void> logout() async {
    busy = true;
    notifyListeners();
    try {
      await authGateway.logout();
    } finally {
      busy = false;
      _clearAuthenticatedState();
      notifyListeners();
    }
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  void _clearAuthenticatedState() {
    offline?.lastSync = null;
    offline?.lastCacheRead = null;
    offline?.selectedBusiness = null;
    status = SessionStatus.signedOut;
    currentUser = null;
    businesses = const [];
    selectedBusiness = null;
    commercialStatus = null;
    adminMode = false;
    errorMessage = null;
  }
}
