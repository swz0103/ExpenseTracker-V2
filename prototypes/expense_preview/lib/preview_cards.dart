part of 'preview_engine.dart';

/// One private-vault intent survives an ambiguous commit. Keeping the last
/// completed identity also makes a repeated tap after process exit a replay.
final class _CardStatementIntent {
  const _CardStatementIntent({
    required this.kind,
    required this.workspace,
    required this.cardId,
    required this.statementId,
    required this.revision,
    required this.paymentId,
    required this.cycle,
    required this.amount,
    required this.operation,
    required this.committed,
  });

  final String kind;
  final WorkspaceId workspace;
  final PublicId cardId, statementId;
  final int revision;
  final PublicId? paymentId;
  final CardCycle? cycle;
  final Money amount;
  final OperationId operation;
  final bool committed;

  _CardStatementIntent complete() => _CardStatementIntent(
    kind: kind,
    workspace: workspace,
    cardId: cardId,
    statementId: statementId,
    revision: revision,
    paymentId: paymentId,
    cycle: cycle,
    amount: amount,
    operation: operation,
    committed: true,
  );

  bool sameRequest(_CardStatementIntent other) =>
      kind == other.kind &&
      workspace == other.workspace &&
      cardId == other.cardId &&
      (kind == 'confirmation' || statementId == other.statementId) &&
      revision == other.revision &&
      paymentId == other.paymentId &&
      cycle?.startsAfter == other.cycle?.startsAfter &&
      cycle?.closesOn == other.cycle?.closesOn &&
      cycle?.dueOn == other.cycle?.dueOn &&
      amount == other.amount;

  String encode() => jsonEncode([
    'card-statement-intent-v1',
    kind,
    committed ? 'committed' : 'pending',
    workspace.id.value,
    cardId.value,
    statementId.value,
    revision,
    paymentId?.value,
    cycle?.startsAfter.toString(),
    cycle?.closesOn.toString(),
    cycle?.dueOn.toString(),
    amount.currency.code,
    amount.currency.scale,
    amount.minorUnits.toString(),
    operation.id.value,
  ]);

  static _CardStatementIntent decode(String raw, WorkspaceId workspace) {
    try {
      final fields = jsonDecode(raw);
      if (fields is! List ||
          fields.length != 15 ||
          fields[0] != 'card-statement-intent-v1' ||
          (fields[1] != 'confirmation' && fields[1] != 'allocation') ||
          (fields[2] != 'pending' && fields[2] != 'committed') ||
          fields[3] != workspace.id.value ||
          fields[4] is! String ||
          fields[5] is! String ||
          fields[6] is! int ||
          fields[11] is! String ||
          fields[12] is! int ||
          fields[13] is! String ||
          fields[14] is! String) {
        throw const FormatException('Invalid card intent');
      }
      final kind = fields[1] as String;
      if (kind == 'confirmation'
          ? fields[7] != null ||
                fields[8] is! String ||
                fields[9] is! String ||
                fields[10] is! String ||
                fields[6] != 1
          : fields[7] is! String ||
                fields[8] != null ||
                fields[9] != null ||
                fields[10] != null ||
                (fields[6] as int) < 1) {
        throw const FormatException('Invalid card intent shape');
      }
      final currency = Currency(fields[11] as String, fields[12] as int);
      final intent = _CardStatementIntent(
        kind: kind,
        workspace: workspace,
        cardId: PublicId.parse(fields[4] as String),
        statementId: PublicId.parse(fields[5] as String),
        revision: fields[6] as int,
        paymentId: fields[7] == null
            ? null
            : PublicId.parse(fields[7] as String),
        cycle: kind == 'confirmation'
            ? CardCycle(
                startsAfter: BusinessDate.parse(fields[8] as String),
                closesOn: BusinessDate.parse(fields[9] as String),
                dueOn: BusinessDate.parse(fields[10] as String),
              )
            : null,
        amount: Money(currency, BigInt.parse(fields[13] as String)),
        operation: OperationId.parse(fields[14] as String),
        committed: fields[2] == 'committed',
      );
      if (intent.encode() != raw ||
          (kind == 'confirmation'
              ? intent.amount.minorUnits < BigInt.zero
              : intent.amount.minorUnits <= BigInt.zero)) {
        throw const FormatException('Noncanonical card intent');
      }
      return intent;
    } catch (_) {
      throw DraftUnavailable();
    }
  }
}

extension PreviewCards on PreviewEngine {
  String _cardIntentSlot(String kind) =>
      'card_statement_${kind}_intent_${_identity!.value}';

  Future<_CardStatementIntent?> _readCardIntent(String kind) async {
    final raw = await vault.read(_cardIntentSlot(kind));
    if (raw == null) return null;
    final intent = _CardStatementIntent.decode(raw, _workspace!);
    if (intent.kind != kind) throw DraftUnavailable();
    return intent;
  }

  Future<void> _writeCardIntent(_CardStatementIntent intent) async {
    final slot = _cardIntentSlot(intent.kind);
    final encoded = intent.encode();
    await vault.write(slot, encoded);
    if (await vault.read(slot) != encoded) throw DraftUnavailable();
  }

  Future<({bool confirmation, bool allocation})>
  pendingCardStatementIntents() => _exclusive((epoch) async {
    _require();
    if (!capabilities.cardStatements) throw PreviewInvalid();
    final confirmation = await _readCardIntent('confirmation');
    final allocation = await _readCardIntent('allocation');
    _check(epoch);
    return (
      confirmation: confirmation?.committed == false,
      allocation: allocation?.committed == false,
    );
  });

  Future<void> _replayCardIntent(_CardStatementIntent intent, int epoch) async {
    _check(epoch);
    if (intent.kind == 'confirmation') {
      await _session!.confirmCardStatement(
        workspace: intent.workspace,
        statementId: intent.statementId,
        cardId: intent.cardId,
        revision: intent.revision,
        cycle: intent.cycle!,
        billed: intent.amount,
        operation: intent.operation,
      );
    } else {
      await _session!.allocateCardPayment(
        workspace: intent.workspace,
        paymentEventId: intent.paymentId!,
        statementId: intent.statementId,
        statementRevision: intent.revision,
        amount: intent.amount,
        operation: intent.operation,
      );
    }
    draftCheckpoint?.call('card-${intent.kind}-committed');
    _check(epoch);
    await _writeCardIntent(intent.complete());
  }

  Future<void> retryPendingCardStatementIntent(String kind) =>
      _draftExclusive((epoch) async {
        _require();
        if (!capabilities.cardStatements ||
            (kind != 'confirmation' && kind != 'allocation')) {
          throw PreviewInvalid();
        }
        final intent = await _readCardIntent(kind);
        if (intent == null || intent.committed) throw PreviewInvalid();
        await _replayCardIntent(intent, epoch);
      });

  Future<void> submitCardStatementConfirmation({
    required PublicId cardId,
    required CardCycle cycle,
    required Money billed,
  }) => _draftExclusive((epoch) async {
    _require();
    if (!capabilities.cardStatements) throw PreviewInvalid();
    final requested = _CardStatementIntent(
      kind: 'confirmation',
      workspace: _workspace!,
      cardId: cardId,
      statementId: PublicId.generate(),
      revision: 1,
      paymentId: null,
      cycle: cycle,
      amount: billed,
      operation: OperationId(PublicId.generate()),
      committed: false,
    );
    final prior = await _readCardIntent('confirmation');
    if (prior != null && !prior.sameRequest(requested) && !prior.committed) {
      throw DraftNeedsResolution();
    }
    final intent = prior?.sameRequest(requested) == true ? prior! : requested;
    if (identical(intent, requested)) await _writeCardIntent(intent);
    await _replayCardIntent(intent, epoch);
  });

  Future<void> submitCardPaymentAllocation({
    required PublicId paymentEventId,
    required PublicId statementId,
    required int statementRevision,
    required PublicId cardId,
    required Money amount,
  }) => _draftExclusive((epoch) async {
    _require();
    if (!capabilities.cardStatements) throw PreviewInvalid();
    final requested = _CardStatementIntent(
      kind: 'allocation',
      workspace: _workspace!,
      cardId: cardId,
      statementId: statementId,
      revision: statementRevision,
      paymentId: paymentEventId,
      cycle: null,
      amount: amount,
      operation: OperationId(PublicId.generate()),
      committed: false,
    );
    final prior = await _readCardIntent('allocation');
    if (prior != null && !prior.sameRequest(requested) && !prior.committed) {
      throw DraftNeedsResolution();
    }
    final intent = prior?.sameRequest(requested) == true ? prior! : requested;
    if (identical(intent, requested)) await _writeCardIntent(intent);
    await _replayCardIntent(intent, epoch);
  });
  Future<List<CreditCardTerms>> savedCreditCards() => _exclusive((epoch) async {
    _require();
    if (!capabilities.creditCards) throw PreviewInvalid();
    final cards = await _session!.creditCardTerms(_workspace!);
    _check(epoch);
    return cards;
  });

  Future<List<CardTermsRevision>> savedCreditCardHistory() =>
      _exclusive((epoch) async {
        _require();
        if (!capabilities.creditCards) throw PreviewInvalid();
        final revisions = await _session!.creditCardTermsHistory(_workspace!);
        _check(epoch);
        return revisions;
      });

  Future<void> reviseCreditCard(
    CreditCardTerms terms,
    OperationId operation, {
    bool disabled = false,
  }) => _exclusive((epoch) async {
    _require();
    if (!capabilities.creditCards || terms.workspace != _workspace) {
      throw PreviewInvalid();
    }
    await _session!.reviseCreditCard(
      terms,
      operation,
      DateTime.now().toUtc(),
      disabled: disabled,
    );
    _check(epoch);
  });

  Future<List<ConfirmedCardStatement>> confirmedCardStatements(
    PublicId cardId,
  ) => _exclusive((epoch) async {
    _require();
    if (!capabilities.cardStatements) throw PreviewInvalid();
    final rows = await _session!.confirmedCardStatements(
      workspace: _workspace!,
      cardId: cardId,
    );
    _check(epoch);
    return rows;
  });

  Future<List<CardUnallocatedPayment>> unallocatedCardPayments(
    PublicId cardId,
  ) => _exclusive((epoch) async {
    _require();
    if (!capabilities.cardStatements) throw PreviewInvalid();
    final rows = await _session!.unallocatedCardPayments(
      workspace: _workspace!,
      cardId: cardId,
    );
    _check(epoch);
    return rows;
  });

  Future<void> confirmCardStatement({
    required PublicId statementId,
    required PublicId cardId,
    required int revision,
    required CardCycle cycle,
    required Money billed,
    required OperationId operation,
  }) => _exclusive((epoch) async {
    _require();
    if (!capabilities.cardStatements) throw PreviewInvalid();
    await _session!.confirmCardStatement(
      workspace: _workspace!,
      statementId: statementId,
      cardId: cardId,
      revision: revision,
      cycle: cycle,
      billed: billed,
      operation: operation,
    );
    _check(epoch);
  });

  Future<void> allocateCardPayment({
    required PublicId paymentEventId,
    required PublicId statementId,
    required int statementRevision,
    required Money amount,
    required OperationId operation,
  }) => _exclusive((epoch) async {
    _require();
    if (!capabilities.cardStatements) throw PreviewInvalid();
    await _session!.allocateCardPayment(
      workspace: _workspace!,
      paymentEventId: paymentEventId,
      statementId: statementId,
      statementRevision: statementRevision,
      amount: amount,
      operation: operation,
    );
    _check(epoch);
  });
}
