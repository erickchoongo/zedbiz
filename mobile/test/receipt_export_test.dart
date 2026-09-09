import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zedbiz/features/sales/application/receipt_export.dart';
import 'package:zedbiz/features/sales/domain/sale.dart';

class ExportPlatform implements ReceiptPlatform {
  String? name, text;
  int shares = 0, exports = 0;
  @override
  Future<void> share(Uint8List bytes, String filename) async {
    shares++;
    name = filename;
    expect(bytes.take(4), [37, 80, 68, 70]);
  }

  @override
  Future<void> export(Uint8List bytes, String filename) async {
    exports++;
    name = filename;
  }

  @override
  Future<void> copy(String value) async {
    text = value;
  }
}

Map<String, dynamic> data({bool pending = false, int items = 1}) => {
  'business_name': 'Lusaka Shop',
  'currency': 'ZMW',
  'business_phone': '+260970000000',
  'business_location': 'Lusaka',
  'sale_number': pending ? 'Pending #1234' : 'ZB-20260908-000123',
  'status': 'VOIDED',
  'sold_at': '2026-09-08T10:30:00Z',
  'seller_name': 'Owner',
  'items': List.generate(
    items,
    (_) => {
      'product_name': 'Long product name café ${'rice ' * 30}',
      'quantity': '1.250',
      'unit_price': '79.99',
      'line_total': '99.99',
      'unit_cost': 'SECRET_COST',
    },
  ),
  'subtotal': '99.99',
  'discount_amount': '0.00',
  'total_amount': '99.99',
  'payment_method': 'MTN_MONEY',
  'payment_reference': 'REF123',
  'cost': 'SECRET_COST',
  'gross_profit': 'SECRET_PROFIT',
  'notes': 'SECRET_NOTE',
  if (pending) 'local_sync_state': 'pending',
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'receipt mapping, Lusaka date, exact totals, void status and privacy',
    () {
      final r = ReceiptData.fromJson(data());
      final text = ReceiptExport.lines(r).join('\n');
      expect(text, contains('12:30 (Lusaka)'));
      expect(text, contains('TOTAL: ZMW 99.99'));
      expect(text, contains('MTN Money'));
      expect(text, contains('VOIDED'));
      expect(text, contains('ZB-20260908-000123'));
      expect(text, isNot(contains('SECRET')));
      expect(text, isNot(contains('Tax Invoice')));
      expect(
        ReceiptExport.filename(r),
        'ZedBiz_Receipt_ZB-20260908-000123.pdf',
      );
    },
  );
  test('PDF long names and multiple pages generate offline, share/export/copy abstraction', () async {
    final r = ReceiptData.fromJson(data(items: 100));
    final platform = ExportPlatform();
    final service = ReceiptExport(platform: platform);
    final bytes = await service.generate(r);
    expect(bytes.length, greaterThan(1000));
    final output = Platform.environment['ZEDBIZ_RECEIPT_TEST_OUTPUT'];
    if (output != null) await File(output).writeAsBytes(bytes);
    await service.share(r);
    await service.export(r);
    await service.copy(r);
    expect(platform.shares, 1);
    expect(platform.exports, 1);
    expect(platform.text, isNot(contains('SECRET')));
  });
  test('provisional to synchronized labels and safe filenames', () {
    final pending = ReceiptData.fromJson(data(pending: true));
    expect(
      ReceiptExport.lines(pending).join('\n'),
      contains('NOT SERVER-CONFIRMED'),
    );
    final unsafe = ReceiptData.fromJson({
      ...data(),
      'sale_number': 'ZB/..:123*?',
    });
    expect(
      ReceiptExport.filename(unsafe),
      matches(r'^ZedBiz_Receipt_[A-Za-z0-9_-]+\.pdf$'),
    );
    final confirmed = ReceiptData.fromJson(data());
    expect(
      ReceiptExport.lines(confirmed).join('\n'),
      isNot(contains('PROVISIONAL')),
    );
  });
}
