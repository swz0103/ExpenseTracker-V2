import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:backup_security/backup_security.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:expense_tracker/src/vault_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_vault/ledger_vault.dart';

/// The real encrypted store inside the Flutter test host: what the phone
/// build will run.
void main() {
  test('entries survive closing and reopening the encrypted ledger', () async {
    final directory = Directory.systemTemp.createTempSync('vault-session-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final vault = LedgerVault(
      directory,
      codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
    );
    final clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 3, 4)));
    final twd = Currency.of('TWD');

    final (open, _) = await vault.create('correct horse battery');
    final session = vaultSession(open, clock: clock);
    await session.openAccount(
      session.begin(),
      '現金',
      AccountKind.cash,
      opening: Money(twd, BigInt.from(10000)),
    );
    final cash = session.accounts.single;
    await session.record(
      session.begin(),
      CashFlow.expense,
      cash,
      Money(twd, BigInt.from(2500)),
      session.today,
    );
    open.close();

    final again = vaultSession(
      await vault.unlockWithPassword('correct horse battery'),
      clock: clock,
    );
    expect(again.workspace, session.workspace);
    final balance = again.balanceOf(again.accounts.single);
    expect(balance, Money(twd, BigInt.from(7500)));
    expect(again.recent, hasLength(2));
    expect(again.monthTotal(2026, 10).expense, Money(twd, BigInt.from(2500)));
  });
}
