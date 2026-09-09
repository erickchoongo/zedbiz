class Quantity {
  const Quantity._(this.thousandths);
  const Quantity.fromThousandths(this.thousandths);
  final int thousandths;

  factory Quantity.parse(String value) {
    final match = RegExp(r'^(\d+)(?:\.(\d{1,3}))?$').firstMatch(value.trim());
    if (match == null) {
      throw const FormatException(
        'Use a positive number with up to 3 decimal places.',
      );
    }
    final fraction = (match.group(2) ?? '').padRight(3, '0');
    return Quantity._(
      int.parse(match.group(1)!) * 1000 +
          int.parse(fraction.isEmpty ? '0' : fraction),
    );
  }

  String get apiValue =>
      '${thousandths ~/ 1000}.${(thousandths % 1000).toString().padLeft(3, '0')}';
  String get display => thousandths % 1000 == 0
      ? '${thousandths ~/ 1000}'
      : apiValue.replaceFirst(RegExp(r'0+$'), '');
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.sellingPrice,
    required this.stockQuantity,
    required this.lowStockThreshold,
    required this.trackInventory,
    required this.isActive,
    required this.isLowStock,
    this.sku,
    this.barcode,
    this.description,
    this.saleVersion,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    name: json['name'] as String,
    sku: json['sku'] as String?,
    barcode: json['barcode'] as String?,
    description: json['description'] as String?,
    saleVersion: json['sale_version'] as String?,
    sellingPrice: json['selling_price'] as String,
    stockQuantity: Quantity.parse(json['stock_quantity'] as String),
    lowStockThreshold: Quantity.parse(json['low_stock_threshold'] as String),
    trackInventory: json['track_inventory'] as bool,
    isActive: json['is_active'] as bool,
    isLowStock: json['is_low_stock'] as bool,
  );
  final String id, name, sellingPrice;
  final String? sku, barcode, description;
  final String? saleVersion;
  final Quantity stockQuantity, lowStockThreshold;
  final bool trackInventory, isActive, isLowStock;
}

class ProductPage {
  const ProductPage(this.items, this.page, this.pageSize, this.total);
  factory ProductPage.fromJson(Map<String, dynamic> json) => ProductPage(
    (json['items'] as List)
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList(),
    json['page'] as int,
    json['page_size'] as int,
    json['total'] as int,
  );
  final List<Product> items;
  final int page, pageSize, total;
}

class InventoryMovement {
  const InventoryMovement({
    required this.type,
    required this.delta,
    required this.after,
    required this.actor,
    required this.createdAt,
    this.reason,
  });
  factory InventoryMovement.fromJson(Map<String, dynamic> json) =>
      InventoryMovement(
        type: json['movement_type'] as String,
        delta: json['quantity_delta'] as String,
        after: json['quantity_after'] as String,
        actor: json['performed_by_name'] as String? ?? 'Team member',
        reason: json['reason'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
  final String type, delta, after, actor;
  final String? reason;
  final DateTime createdAt;
  String get label =>
      const {
        'OPENING_STOCK': 'Opening stock',
        'STOCK_ADDED': 'Stock added',
        'MANUAL_ADJUSTMENT': 'Manual adjustment',
        'DAMAGED': 'Damaged stock',
        'LOST': 'Lost stock',
      }[type] ??
      type;
}
