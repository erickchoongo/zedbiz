import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:zedbiz/features/sales/domain/sale.dart';

abstract interface class ReceiptPlatform {
  Future<void> share(Uint8List bytes, String filename);
  Future<void> export(Uint8List bytes, String filename);
  Future<void> copy(String text);
}

class DeviceReceiptPlatform implements ReceiptPlatform {
  @override
  Future<void> share(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  @override
  Future<void> export(Uint8List bytes, String filename) async {
    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } else {
      await Printing.layoutPdf(name: filename, onLayout: (_) => bytes);
    }
  }

  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

class ReceiptExport {
  ReceiptExport({ReceiptPlatform? platform})
    : platform = platform ?? DeviceReceiptPlatform();
  final ReceiptPlatform platform;
  static String filename(ReceiptData r) =>
      'ZedBiz_Receipt_${r.saleNumber.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').substring(0, r.saleNumber.length.clamp(0, 80))}.pdf';
  static String date(DateTime value) {
    final z = value.toUtc().add(const Duration(hours: 2));
    return '${z.day.toString().padLeft(2, '0')}/${z.month.toString().padLeft(2, '0')}/${z.year} ${z.hour.toString().padLeft(2, '0')}:${z.minute.toString().padLeft(2, '0')} (Lusaka)';
  }

  static List<String> lines(ReceiptData r) => [
    r.businessName,
    if (r.phone != null) r.phone!,
    if (r.location != null) r.location!,
    r.localSyncState == null
        ? 'SALES RECEIPT'
        : 'PROVISIONAL RECEIPT - PENDING SYNC',
    r.saleNumber,
    date(r.soldAt),
    'Seller: ${r.seller}',
    'Status: ${r.localSyncState == null ? r.status.name.toUpperCase() : 'NOT SERVER-CONFIRMED'}',
    for (final i in r.items) ...[
      i.name,
      '${i.quantity.display} x ${r.currency} ${i.unitPrice.decimal}     ${r.currency} ${i.lineTotal.decimal}',
    ],
    'Subtotal: ${r.currency} ${r.subtotal.decimal}',
    'Discount: ${r.currency} ${r.discount.decimal}',
    'TOTAL: ${r.currency} ${r.total.decimal}',
    'Payment: ${paymentLabel(r.paymentMethod)}',
    if (r.reference != null) 'Reference: ${r.reference}',
    'Thank you',
  ];
  Future<Uint8List> generate(ReceiptData r) async {
    final doc = pw.Document();
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    doc.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: font, bold: font),
        maxPages: 100,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Text(r.businessName, style: const pw.TextStyle(fontSize: 22)),
          if (r.phone != null) pw.Text(r.phone!),
          if (r.location != null) pw.Text(r.location!),
          pw.SizedBox(height: 18),
          pw.Text(
            r.localSyncState == null
                ? 'SALES RECEIPT'
                : 'PROVISIONAL RECEIPT - PENDING SYNC',
            style: const pw.TextStyle(fontSize: 16),
          ),
          pw.Text(r.saleNumber),
          pw.Text(date(r.soldAt)),
          pw.Text('Seller: ${r.seller}'),
          pw.Text(
            'Status: ${r.localSyncState == null ? r.status.name.toUpperCase() : 'NOT SERVER-CONFIRMED'}',
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: ['Item', 'Qty', 'Unit price', 'Amount (${r.currency})'],
            data: [
              for (final item in r.items)
                [
                  item.name,
                  item.quantity.display,
                  item.unitPrice.decimal,
                  item.lineTotal.decimal,
                ],
            ],
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            border: null,
            cellPadding: const pw.EdgeInsets.all(7),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerStyle: const pw.TextStyle(fontSize: 10),
            columnWidths: {
              0: const pw.FlexColumnWidth(5),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
            },
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
          ),
          pw.Divider(),
          for (final line in [
            'Subtotal: ${r.currency} ${r.subtotal.decimal}',
            'Discount: ${r.currency} ${r.discount.decimal}',
          ])
            pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(line)),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'TOTAL: ${r.currency} ${r.total.decimal}',
              style: const pw.TextStyle(fontSize: 16),
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Text('Payment: ${paymentLabel(r.paymentMethod)}'),
          if (r.reference != null) pw.Text('Reference: ${r.reference}'),
          pw.SizedBox(height: 18),
          pw.Text('Thank you'),
        ],
        footer: (c) => pw.Text(
          'ZedBiz | ${c.pageNumber} / ${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
    );
    return doc.save();
  }

  Future<void> share(ReceiptData r) async =>
      platform.share(await generate(r), filename(r));
  Future<void> export(ReceiptData r) async =>
      platform.export(await generate(r), filename(r));
  Future<void> copy(ReceiptData r) => platform.copy(lines(r).join('\n'));
}
