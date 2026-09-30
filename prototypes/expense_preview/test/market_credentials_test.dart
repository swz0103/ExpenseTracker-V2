import 'package:expense_preview/market_credentials.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Vault implements FugleCredentialVault {
  String? value;
  var writes = 0;
  var deletes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String apiKey) async {
    value = apiKey;
    writes++;
  }

  @override
  Future<void> delete() async {
    value = null;
    deletes++;
  }
}

void main() {
  test('manager stores, supplies and revokes a valid key', () async {
    final vault = _Vault();
    final manager = FugleCredentialManager(vault);
    expect(await manager.isConfigured(), isFalse);
    await manager.save('test-api-key-123');
    expect(await manager.isConfigured(), isTrue);
    expect(await manager.requireApiKey(), 'test-api-key-123');
    expect(vault.writes, 1);
    await manager.revoke();
    expect(await manager.isConfigured(), isFalse);
    expect(vault.deletes, 1);
    expect(manager.requireApiKey(), throwsStateError);
  });

  test('manager rejects empty, whitespace and oversized credentials', () async {
    final manager = FugleCredentialManager(_Vault());
    for (final value in ['', 'bad key', 'x' * 513]) {
      await expectLater(manager.save(value), throwsArgumentError);
    }
  });

  testWidgets('panel never echoes a saved credential and can revoke it', (
    tester,
  ) async {
    final vault = _Vault();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FugleCredentialPanel(
            manager: FugleCredentialManager(vault),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('尚未設定 Fugle API key'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('fugle-key-input')),
      'super-secret-key',
    );
    await tester.tap(find.text('儲存或更換 key'));
    await tester.pump();
    await tester.pump();
    expect(vault.value, 'super-secret-key');
    expect(find.text('Fugle API key 已設定（內容不顯示）'), findsOneWidget);
    expect(find.text('super-secret-key'), findsNothing);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('fugle-key-input')),
    );
    expect(field.controller!.text, isEmpty);

    await tester.tap(find.text('移除本機 key'));
    await tester.pump();
    await tester.pump();
    expect(vault.value, isNull);
    expect(find.text('尚未設定 Fugle API key'), findsOneWidget);
  });

  testWidgets('invalid input shows a generic error without storing', (
    tester,
  ) async {
    final vault = _Vault();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FugleCredentialPanel(
            manager: FugleCredentialManager(vault),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('fugle-key-input')),
      'contains whitespace',
    );
    await tester.tap(find.text('儲存或更換 key'));
    await tester.pump();
    expect(find.text('API key 格式無效，請重新輸入。'), findsOneWidget);
    expect(vault.value, isNull);
  });
}
