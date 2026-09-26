import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:flutter/foundation.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:path_provider/path_provider.dart';
import 'package:validated_restore_probe/restore_store.dart';
import 'package:validated_restore_probe/snapshot.dart';

import 'android_key_vault.dart';
import 'generation_probe.dart';
import 'key_access.dart';

final class ProbeRunner {
  static bool _running = false;
  final _keys = KeyAccess(AndroidKeyVault());
  Future<List<String>> run() async {
    if (!Platform.isAndroid || kReleaseMode || _running) {
      throw StateError('Probe unavailable.');
    }
    _running = true;
    try {
      return await _run();
    } finally {
      _running = false;
    }
  }

  Future<List<String>> _run() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/foundation_fixture_v1');
    await root.create(recursive: true);
    final current = File('${root.path}/current.db');
    final key = await _keys.load(databaseExists: current.exists);
    final workspace = WorkspaceId.parse('019f0000-0000-7000-8000-000000000000');
    final account = Account.open(
      id: PublicId.parse('019f0000-0000-7000-8000-000000000001'),
      workspace: workspace,
      name: 'Android fixture only',
      kind: AccountKind.bank,
      currency: Currency('USD', 2),
      openedOn: BusinessDate(2026, 9, 26),
    );
    final ref = PostingAccount(
      id: account.id,
      workspace: workspace,
      currency: account.currency,
      expectedVersion: 1,
    );
    OperationKey operation(String suffix) => OperationKey(
      workspace,
      OperationId.parse('019f0000-0000-7000-8000-0000000000$suffix'),
    );
    PublicId id(String suffix) =>
        PublicId.parse('019f0000-0000-7000-8000-0000000000$suffix');
    final db = openEncrypted(current, key);
    try {
      final flows = FinancialWorkflows(db);
      await flows.createAccount(
        account,
        Posting.opening(
          id: id('20'),
          operation: operation('10'),
          date: account.openedOn,
          account: ref,
          amount: Money.parse(account.currency, '100'),
        ),
      );
      await flows.post(
        Posting.income(
          id: id('21'),
          operation: operation('11'),
          date: account.openedOn,
          account: ref,
          amount: Money.parse(account.currency, '20'),
        ),
      );
      await flows.post(
        Posting.expense(
          id: id('22'),
          operation: operation('12'),
          date: account.openedOn,
          account: ref,
          amount: Money.parse(account.currency, '5'),
        ),
      );
    } finally {
      await db.close();
    }
    final reread = await KeyAccess(AndroidKeyVault())
        .load(databaseExists: current.exists);
    final reopened = openEncrypted(current, reread);
    late final List<int> expected;
    late final String envelope;
    late final String recovery;
    try {
      if (await FinancialWorkflows(reopened).ledger.balance(ref) !=
          Money.parse(account.currency, '115')) {
        throw StateError('Balance mismatch.');
      }
      expected = await SnapshotCodec().capture(reopened);
      final backup = await RestoreStore(root)
          .backup(reopened, 'android-synthetic-fixture-only');
      envelope = backup.envelope;
      recovery = backup.recoveryKey;
    } finally {
      await reopened.close();
    }
    await verifyGenerationRestores(
      root: root,
      envelope: envelope,
      recovery: recovery,
      expected: expected,
      account: ref,
    );
    return ['安全儲存讀回成功', '加密帳務重開與餘額核對成功', '雙路還原、金鑰配對與防重複入帳核對成功'];
  }
}
