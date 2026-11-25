import 'dart:typed_data';

import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/features/entries/forms/receipt_square.dart';
import 'package:expense_tracker/src/features/entries/model/receipt_photos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Takes [named] from either source, or fails with [error].
final class _Photos implements ReceiptPhotos {
  _Photos({this.named, this.error});

  final String? named;
  final Exception? error;
  bool? usedCamera;

  @override
  Future<String?> take({required bool camera}) async {
    usedCamera = camera;
    if (error case final e?) throw e;
    return named;
  }

  @override
  Future<String?> takeLeftover() async => null;

  @override
  ImageProvider image(String name) => MemoryImage(Uint8List(0));
}

Future<void> _show(WidgetTester tester, ReceiptSquare square) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: square)),
      ),
    );

void main() {
  late List<String> said;
  setUp(() => said = []);

  ReceiptSquare square(
    _Photos photos, {
    String? receipt,
    bool removable = true,
  }) => ReceiptSquare(
    photos: photos,
    receipt: receipt,
    color: Colors.teal,
    removable: removable,
    onTaken: (name) => said.add('taken $name'),
    onFailed: ({required camera}) => said.add('failed camera=$camera'),
    onRemove: () => said.add('removed'),
  );

  testWidgets('a photo taken with the camera is handed on', (tester) async {
    final photos = _Photos(named: 'r1.etr');
    await _show(tester, square(photos));
    await tester.tap(find.byKey(Keys.receipt));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Keys.receiptSource(camera: true)));
    await tester.pumpAndSettle();
    expect(photos.usedCamera, isTrue);
    expect(said, ['taken r1.etr']);
  });

  testWidgets('a photo that cannot be read is told, not lost', (tester) async {
    final photos = _Photos(error: Exception('no access'));
    await _show(tester, square(photos));
    await tester.tap(find.byKey(Keys.receipt));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Keys.receiptSource(camera: false)));
    await tester.pumpAndSettle();
    expect(photos.usedCamera, isFalse);
    expect(said, ['failed camera=false']);
  });

  testWidgets('closing the choice takes nothing', (tester) async {
    final photos = _Photos(named: 'r1.etr');
    await _show(tester, square(photos));
    await tester.tap(find.byKey(Keys.receipt));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(photos.usedCamera, isNull);
    expect(said, isEmpty);
  });

  testWidgets('a receipt kept can be removed only while editing', (
    tester,
  ) async {
    await _show(tester, square(_Photos(), receipt: 'r1.etr'));
    await tester.tap(find.byTooltip('刪除收據'));
    expect(said, ['removed']);
    await _show(tester, square(_Photos(), receipt: 'r1.etr', removable: false));
    expect(find.byTooltip('刪除收據'), findsNothing);
  });
}
