import 'package:flutter_test/flutter_test.dart';
import 'package:zedbiz/features/products/data/product_repository.dart';
import 'package:zedbiz/features/products/domain/product.dart';

void main() {
  test('quantity preserves exact thousandths without floating point', () {
    expect(Quantity.parse('12.345').apiValue, '12.345');
    expect(Quantity.parse('2.5').apiValue, '2.500');
    expect(Quantity.parse('2.000').display, '2');
  });

  test('quantity rejects excess precision and negative input', () {
    expect(() => Quantity.parse('1.2345'), throwsFormatException);
    expect(() => Quantity.parse('-1'), throwsFormatException);
  });

  test('operation IDs are unique RFC 4122 version 4 UUIDs', () {
    final first = newOperationId();
    final second = newOperationId();
    expect(first, isNot(second));
    expect(
      first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('movement types receive friendly user labels', () {
    final movement = InventoryMovement.fromJson({
      'movement_type': 'DAMAGED',
      'quantity_delta': '-1.000',
      'quantity_after': '2.000',
      'performed_by_name': 'Owner',
      'reason': 'Spoiled',
      'created_at': '2026-08-30T10:00:00Z',
    });
    expect(movement.label, 'Damaged stock');
    expect(movement.actor, 'Owner');
  });
}
