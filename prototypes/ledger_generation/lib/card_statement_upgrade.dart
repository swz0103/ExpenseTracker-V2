part of 'safety_backup.dart';

/// Schema 17 had Ledger card events but no card facts. Only an unambiguous
/// posted expense or fee-free bank payment can be reconstructed. A statement
/// identity, pending authorization, fee split, or allocation is never guessed.
List<int> _backfillCardStatementFacts(List<int> targetBytes) {
  try {
    final root = jsonDecode(utf8.decode(targetBytes)) as Map<String, dynamic>;
    if (root['version'] != 17 || root['schema'] != 18) {
      throw const InvalidSnapshot();
    }
    final tables = root['tables'] as Map<String, dynamic>;
    List<Map<String, dynamic>> rows(String table) => [
      for (final value in tables[table] as List)
        (value as Map).cast<String, dynamic>(),
    ];
    for (final name in [
      'card_posted_charges',
      'card_statements',
      'card_payments',
      'card_payment_allocations',
    ]) {
      if (rows(name).isNotEmpty) throw const InvalidSnapshot();
    }

    final accounts =
        <(String, String), ({String kind, String currency, int scale})>{};
    for (final row in rows('accounts')) {
      final payload =
          jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      final key = (row['workspace'] as String, row['id'] as String);
      if (accounts.containsKey(key)) throw const InvalidSnapshot();
      accounts[key] = (
        kind: payload['kind'] as String,
        currency: payload['currency'] as String,
        scale: payload['scale'] as int,
      );
    }
    final legs = <(String, String), List<Map<String, dynamic>>>{};
    for (final leg in rows('legs')) {
      final key = (leg['workspace'] as String, leg['event_id'] as String);
      (legs[key] ??= []).add(leg);
    }
    final cardEvents = <(String, String)>{};
    for (final entry in legs.entries) {
      for (final leg in entry.value) {
        final account = accounts[(entry.key.$1, leg['account_id'] as String)];
        if (account == null) throw const InvalidSnapshot();
        if (account.kind == 'creditCard') cardEvents.add(entry.key);
      }
    }
    bool touchesCard(Map<String, dynamic> row, String idColumn) => cardEvents
        .contains((row['workspace'] as String, row[idColumn] as String));
    for (final row in rows('event_refunds')) {
      if (touchesCard(row, 'event_id') || touchesCard(row, 'original_id')) {
        throw const InvalidSnapshot();
      }
    }
    for (final row in rows('event_reversals')) {
      if (touchesCard(row, 'event_id') || touchesCard(row, 'original_id')) {
        throw const InvalidSnapshot();
      }
    }
    for (final row in rows('event_corrections')) {
      if (touchesCard(row, 'original_id') ||
          touchesCard(row, 'reversal_id') ||
          touchesCard(row, 'replacement_id')) {
        throw const InvalidSnapshot();
      }
    }
    for (final row in rows('event_tombstones')) {
      if (touchesCard(row, 'event_id')) throw const InvalidSnapshot();
    }
    for (final row in rows('event_fx')) {
      if (touchesCard(row, 'event_id')) throw const InvalidSnapshot();
    }

    final receipts = <(String, String), List<Map<String, dynamic>>>{};
    for (final receipt in rows('receipts')) {
      final key = (
        receipt['workspace'] as String,
        receipt['result_id'] as String,
      );
      (receipts[key] ??= []).add(receipt);
    }
    final audits = <(String, String), Map<String, dynamic>>{};
    for (final audit in rows('audit')) {
      final key = (
        audit['workspace'] as String,
        audit['operation_id'] as String,
      );
      if (audits.containsKey(key)) throw const InvalidSnapshot();
      audits[key] = audit;
    }
    bool financial(Map<String, dynamic> receipt) {
      final kind =
          audits[(
                receipt['workspace'] as String,
                receipt['operation_id'] as String,
              )]?['kind']
              as String?;
      return kind == null ||
          !(kind.startsWith('category.') ||
              kind.startsWith('tag.') ||
              kind.startsWith('merchant.') ||
              kind == 'ledger.note' ||
              kind == 'ledger.tombstone');
    }

    void requireReceipt((String, String) event, String expectedKind) {
      // A note on a card entry adds a second receipt for the same event.
      final matching = receipts[event]?.where(financial).toList();
      if (matching == null || matching.length != 1) {
        throw const InvalidSnapshot();
      }
      final receipt = matching.single;
      final audit = audits[(event.$1, receipt['operation_id'] as String)];
      if (audit == null ||
          audit['entity_id'] != event.$2 ||
          audit['kind'] != expectedKind) {
        throw const InvalidSnapshot();
      }
    }

    final charges = <Map<String, String>>[];
    final payments = <Map<String, String>>[];
    final seen = <(String, String)>{};
    for (final event in rows('events')) {
      final ws = event['workspace'] as String;
      final id = event['id'] as String;
      final key = (ws, id);
      if (!cardEvents.contains(key)) continue;
      if (!seen.add(key)) throw const InvalidSnapshot();
      final eventLegs = legs[key] ?? const <Map<String, dynamic>>[];
      final kind = event['kind'] as String;
      final date = event['business_date'] as String;
      if (BusinessDate.parse(date).toString() != date) {
        throw const InvalidSnapshot();
      }
      final income = BigInt.parse(event['income'] as String);
      final expense = BigInt.parse(event['expense'] as String);
      final currency = event['currency'] as String;
      final scale = int.parse(event['scale'] as String);
      final primary = eventLegs.isEmpty ? null : eventLegs.first;
      final primaryAccount = primary == null
          ? null
          : accounts[(ws, primary['account_id'] as String)];
      if (kind == 'opening') {
        if (eventLegs.length != 1 ||
            primaryAccount?.kind != 'creditCard' ||
            primary!['ordinal'] != '0' ||
            primary['role'] != 'principal' ||
            BigInt.parse(primary['amount'] as String) != BigInt.zero ||
            income != BigInt.zero ||
            expense != BigInt.zero) {
          throw const InvalidSnapshot();
        }
        continue;
      }
      if (kind == 'expense') {
        if (eventLegs.length != 1 ||
            primaryAccount?.kind != 'creditCard' ||
            primary!['ordinal'] != '0' ||
            primary['role'] != 'principal' ||
            primaryAccount!.currency != currency ||
            primaryAccount.scale != scale ||
            primary['currency'] != currency ||
            primary['scale'] != event['scale'] ||
            income != BigInt.zero ||
            expense <= BigInt.zero ||
            BigInt.parse(primary['amount'] as String) != -expense) {
          throw const InvalidSnapshot();
        }
        requireReceipt(key, 'ledger.expense');
        charges.add({
          'workspace': ws,
          'event_id': id,
          'card_id': primary['account_id'] as String,
          'posted_on': date,
          'amount_minor': expense.toString(),
        });
        continue;
      }
      if (kind == 'transfer') {
        if (eventLegs.length != 2 ||
            primaryAccount?.kind != 'bank' ||
            primary!['ordinal'] != '0' ||
            primary['role'] != 'principal' ||
            eventLegs[1]['ordinal'] != '1' ||
            eventLegs[1]['role'] != 'principal' ||
            income != BigInt.zero ||
            expense != BigInt.zero) {
          throw const InvalidSnapshot();
        }
        final destination = eventLegs[1];
        final card = accounts[(ws, destination['account_id'] as String)];
        final paid = BigInt.parse(destination['amount'] as String);
        if (card?.kind != 'creditCard' ||
            paid <= BigInt.zero ||
            BigInt.parse(primary['amount'] as String) != -paid ||
            primaryAccount!.currency != currency ||
            primaryAccount.scale != scale ||
            card!.currency != currency ||
            card.scale != scale ||
            primary['currency'] != currency ||
            destination['currency'] != currency ||
            primary['scale'] != event['scale'] ||
            destination['scale'] != event['scale']) {
          throw const InvalidSnapshot();
        }
        requireReceipt(key, 'ledger.transfer');
        payments.add({
          'workspace': ws,
          'event_id': id,
          'card_id': destination['account_id'] as String,
          'posted_on': date,
          'amount_minor': paid.toString(),
        });
        continue;
      }
      throw const InvalidSnapshot();
    }
    if (seen.length != cardEvents.length) throw const InvalidSnapshot();
    int byIdentity(Map<String, String> left, Map<String, String> right) {
      final workspace = left['workspace']!.compareTo(right['workspace']!);
      return workspace != 0
          ? workspace
          : left['event_id']!.compareTo(right['event_id']!);
    }

    charges.sort(byIdentity);
    payments.sort(byIdentity);
    tables['card_posted_charges'] = charges;
    tables['card_payments'] = payments;
    return utf8.encode(jsonEncode(root));
  } on InvalidSnapshot {
    rethrow;
  } catch (_) {
    throw const InvalidSnapshot();
  }
}
