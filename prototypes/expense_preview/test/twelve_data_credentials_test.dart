import 'package:expense_preview/twelve_data_credentials.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Vault implements TwelveDataCredentialVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String apiKey) async => value = apiKey;
  @override
  Future<void> delete() async => value = null;
}

void main() {
  test('manager stores, supplies, validates and revokes', () async {
    final vault = _Vault();
    final manager = TwelveDataCredentialManager(vault);
    await manager.save('twelve-key-123');
    expect(await manager.requireApiKey(), 'twelve-key-123');
    await expectLater(manager.save('bad key'), throwsArgumentError);
    await manager.revoke();
    expect(await manager.isConfigured(), isFalse);
    await expectLater(manager.requireApiKey(), throwsStateError);
  });

  testWidgets('panel hides stored value, explains quota and revokes', (
    tester,
  ) async {
    final vault = _Vault();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TwelveDataCredentialPanel(
            manager: TwelveDataCredentialManager(vault),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('twelve-key-input')),
      'private-twelve-key',
    );
    await tester.tap(find.text('儲存或更換 key'));
    await tester.pump();
    await tester.pump();
    expect(vault.value, 'private-twelve-key');
    expect(find.text('Twelve Data API key 已設定（內容不顯示）'), findsOneWidget);
    expect(find.text('private-twelve-key'), findsNothing);
    expect(find.textContaining('8 credits/分鐘'), findsOneWidget);

    await tester.tap(find.text('移除本機 key'));
    await tester.pump();
    await tester.pump();
    expect(vault.value, isNull);
  });

  testWidgets('invalid key is rejected without writing', (tester) async {
    final vault = _Vault();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TwelveDataCredentialPanel(
            manager: TwelveDataCredentialManager(vault),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('twelve-key-input')),
      'bad key',
    );
    await tester.tap(find.text('儲存或更換 key'));
    await tester.pump();
    expect(find.text('API key 格式無效，請重新輸入。'), findsOneWidget);
    expect(vault.value, isNull);
  });
}
