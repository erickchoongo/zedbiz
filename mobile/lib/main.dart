import 'package:flutter/material.dart';
import 'package:zedbiz/app/app.dart';
import 'package:zedbiz/app/app_controller.dart';
import 'package:zedbiz/core/config/app_config.dart';
import 'package:zedbiz/core/offline/offline_client.dart';
import 'package:zedbiz/core/offline/open_database.dart';
import 'package:zedbiz/core/storage/token_storage.dart';
import 'package:zedbiz/features/auth/data/auth_repository.dart';
import 'package:zedbiz/features/businesses/data/business_repository.dart';
import 'package:zedbiz/features/commercial/data/commercial_repository.dart';
import 'package:zedbiz/features/admin/data/admin_repository.dart';
import 'package:zedbiz/features/customers/data/customer_repository.dart';
import 'package:zedbiz/features/debts/data/debt_repository.dart';
import 'package:zedbiz/features/expenses/data/expense_repository.dart';
import 'package:zedbiz/features/products/data/product_repository.dart';
import 'package:zedbiz/features/reporting/data/reporting_repository.dart';
import 'package:zedbiz/features/sales/data/sale_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final tokenStorage = SecureTokenStorage();
  final apiClient = OfflineClient(
    db: openLocalDatabase(),
    baseUrl: config.apiBaseUrl,
    tokenStorage: tokenStorage,
  );
  final controller = AppController(
    offline: apiClient,
    authGateway: AuthRepository(
      apiClient: apiClient,
      tokenStorage: tokenStorage,
    ),
    businessGateway: BusinessRepository(apiClient),
    commercialGateway: CommercialRepository(apiClient),
    adminGateway: AdminRepository(apiClient),
    productGateway: ProductRepository(apiClient),
    saleGateway: SaleRepository(apiClient),
    customerGateway: CustomerRepository(apiClient),
    debtGateway: DebtRepository(apiClient),
    expenseGateway: ExpenseRepository(apiClient),
    reportingGateway: ReportingRepository(apiClient),
  );
  runApp(ZedBizApp(controller: controller));
}
