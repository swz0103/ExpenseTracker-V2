part of 'preview_engine.dart';

/// Private-vault staging for a card authorization command. No estimate, card
/// balance, or operation ID is written to an unencrypted workspace file.
final class _CardAuthorizationIntent {
  const _CardAuthorizationIntent({
    required this.kind,
    required this.workspace,
    required this.cardId,
    required this.chargeId,
    required this.operation,
    required this.authorizedOn,
    required this.postedOn,
    required this.amount,
    required this.eventId,
    required this.accountVersion,
    required this.committed,
  });

  final String kind;
  final WorkspaceId workspace;
  final PublicId cardId, chargeId;
  final OperationId operation;
  final BusinessDate? authorizedOn, postedOn;
  final Money? amount;
  final PublicId? eventId;
  final int? accountVersion;
  final bool committed;

  _CardAuthorizationIntent complete() => _CardAuthorizationIntent(
    kind: kind,
    workspace: workspace,
    cardId: cardId,
    chargeId: chargeId,
    operation: operation,
    authorizedOn: authorizedOn,
    postedOn: postedOn,
    amount: amount,
    eventId: eventId,
    accountVersion: accountVersion,
    committed: true,
  );

  bool sameRequest(_CardAuthorizationIntent other) =>
      kind == other.kind &&
      workspace == other.workspace &&
      cardId == other.cardId &&
      (kind == 'authorization' || chargeId == other.chargeId) &&
      authorizedOn == other.authorizedOn &&
      postedOn == other.postedOn &&
      amount == other.amount;

  String encode() => jsonEncode([
    'card-authorization-intent-v1',
    kind,
    committed ? 'committed' : 'pending',
    workspace.id.value,
    cardId.value,
    chargeId.value,
    operation.id.value,
    authorizedOn?.toString(),
    postedOn?.toString(),
    amount?.currency.code,
    amount?.currency.scale,
    amount?.minorUnits.toString(),
    eventId?.value,
    accountVersion,
  ]);

  static _CardAuthorizationIntent decode(String raw, WorkspaceId workspace) {
    try {
      final fields = jsonDecode(raw);
      if (fields is! List ||
          fields.length != 14 ||
          fields[0] != 'card-authorization-intent-v1' ||
          !const {
            'authorization',
            'cancellation',
            'posting',
          }.contains(fields[1]) ||
          (fields[2] != 'pending' && fields[2] != 'committed') ||
          fields[3] != workspace.id.value ||
          fields[4] is! String ||
          fields[5] is! String ||
          fields[6] is! String) {
        throw const FormatException('Invalid card authorization intent');
      }
      final kind = fields[1] as String;
      if (kind == 'cancellation'
          ? fields.sublist(7).any((field) => field != null)
          : kind == 'authorization'
          ? fields[7] is! String ||
                fields[8] != null ||
                fields[9] is! String ||
                fields[10] is! int ||
                fields[11] is! String ||
                fields[12] != null ||
                fields[13] != null
          : fields[7] != null ||
                fields[8] is! String ||
                fields[9] is! String ||
                fields[10] is! int ||
                fields[11] is! String ||
                fields[12] is! String ||
                fields[13] is! int) {
        throw const FormatException('Invalid card authorization intent shape');
      }
      final amount = kind == 'cancellation'
          ? null
          : Money(
              Currency(fields[9] as String, fields[10] as int),
              BigInt.parse(fields[11] as String),
            );
      final intent = _CardAuthorizationIntent(
        kind: kind,
        workspace: workspace,
        cardId: PublicId.parse(fields[4] as String),
        chargeId: PublicId.parse(fields[5] as String),
        operation: OperationId.parse(fields[6] as String),
        authorizedOn: fields[7] == null
            ? null
            : BusinessDate.parse(fields[7] as String),
        postedOn: fields[8] == null
            ? null
            : BusinessDate.parse(fields[8] as String),
        amount: amount,
        eventId: fields[12] == null
            ? null
            : PublicId.parse(fields[12] as String),
        accountVersion: fields[13] as int?,
        committed: fields[2] == 'committed',
      );
      if (intent.encode() != raw ||
          (amount != null && amount.minorUnits <= BigInt.zero) ||
          (intent.accountVersion != null && intent.accountVersion! < 1)) {
        throw const FormatException('Noncanonical card authorization intent');
      }
      return intent;
    } catch (_) {
      throw DraftUnavailable();
    }
  }
}

extension PreviewAuthorizations on PreviewEngine {
  String _authorizationIntentSlot(String kind) =>
      'card_${kind}_intent_${_identity!.value}';

  Future<_CardAuthorizationIntent?> _readAuthorizationIntent(
    String kind,
  ) async {
    final raw = await vault.read(_authorizationIntentSlot(kind));
    if (raw == null) return null;
    final intent = _CardAuthorizationIntent.decode(raw, _workspace!);
    if (intent.kind != kind) throw DraftUnavailable();
    return intent;
  }

  Future<void> _writeAuthorizationIntent(
    _CardAuthorizationIntent intent,
  ) async {
    final slot = _authorizationIntentSlot(intent.kind);
    final encoded = intent.encode();
    await vault.write(slot, encoded);
    if (await vault.read(slot) != encoded) throw DraftUnavailable();
  }

  Future<void> _requireNoOtherAuthorizationIntent(String kind) async {
    for (final other in const ['authorization', 'cancellation', 'posting']) {
      if (other == kind) continue;
      if ((await _readAuthorizationIntent(other))?.committed == false) {
        throw DraftNeedsResolution();
      }
    }
  }

  Future<({bool authorization, bool cancellation, bool posting})>
  pendingCardAuthorizationIntents() => _exclusive((epoch) async {
    _require();
    if (!capabilities.cardAuthorizations) throw PreviewInvalid();
    final authorization = await _readAuthorizationIntent('authorization');
    final cancellation = await _readAuthorizationIntent('cancellation');
    final posting = await _readAuthorizationIntent('posting');
    _check(epoch);
    return (
      authorization: authorization?.committed == false,
      cancellation: cancellation?.committed == false,
      posting: posting?.committed == false,
    );
  });

  Future<List<CardAuthorizationFact>> savedCardAuthorizations() =>
      _exclusive((epoch) async {
        _require();
        if (!capabilities.cardAuthorizations) throw PreviewInvalid();
        final rows = await _session!.cardAuthorizations(_workspace!);
        _check(epoch);
        return rows;
      });

  Future<Object> _applyAuthorizationIntent(
    _CardAuthorizationIntent intent,
    int epoch,
  ) async {
    _check(epoch);
    final Object result;
    switch (intent.kind) {
      case 'authorization':
        result = await _session!.authorizeCardPurchase(
          CardCharge.pending(
            id: intent.chargeId,
            workspace: intent.workspace,
            cardId: intent.cardId,
            kind: CardChargeKind.purchase,
            authorizedOn: intent.authorizedOn!,
            authorizedAmount: intent.amount!,
          ),
          intent.operation,
        );
        break;
      case 'cancellation':
        result = await _session!.cancelCardAuthorization(
          workspace: intent.workspace,
          chargeId: intent.chargeId,
          operation: intent.operation,
        );
        break;
      case 'posting':
        final amount = intent.amount!;
        result = await _session!.postAuthorizedCardPurchase(
          chargeId: intent.chargeId,
          purchase: Posting.expense(
            id: intent.eventId!,
            operation: OperationKey(intent.workspace, intent.operation),
            date: intent.postedOn!,
            account: PostingAccount(
              id: intent.cardId,
              workspace: intent.workspace,
              currency: amount.currency,
              expectedVersion: intent.accountVersion!,
            ),
            amount: amount,
          ),
          settledAmount: amount,
          fee: Money(amount.currency, BigInt.zero),
        );
        break;
      default:
        throw DraftUnavailable();
    }
    draftCheckpoint?.call('card-${intent.kind}-committed');
    _check(epoch);
    await _writeAuthorizationIntent(intent.complete());
    return result;
  }

  Future<Object> _submitAuthorizationIntent(
    _CardAuthorizationIntent requested,
    int epoch, {
    bool startNew = false,
    Future<void> Function()? validateNew,
  }) async {
    await _requireNoOtherAuthorizationIntent(requested.kind);
    final prior = await _readAuthorizationIntent(requested.kind);
    if (prior != null && !prior.committed && !prior.sameRequest(requested)) {
      throw DraftNeedsResolution();
    }
    final same = prior?.sameRequest(requested) == true;
    if (startNew && prior?.committed == false) throw DraftNeedsResolution();
    final reuse = same && !startNew;
    final intent = reuse ? prior! : requested;
    if (!reuse) {
      await validateNew?.call();
      await _writeAuthorizationIntent(intent);
    }
    return _applyAuthorizationIntent(intent, epoch);
  }

  Future<Object> retryPendingCardAuthorizationIntent(String kind) =>
      _draftExclusive((epoch) async {
        _require();
        if (!capabilities.cardAuthorizations ||
            !const {
              'authorization',
              'cancellation',
              'posting',
            }.contains(kind)) {
          throw PreviewInvalid();
        }
        final intent = await _readAuthorizationIntent(kind);
        if (intent == null || intent.committed) throw PreviewInvalid();
        return _applyAuthorizationIntent(intent, epoch);
      });

  Future<CardAuthorizationFact> submitCardAuthorization({
    required PublicId cardId,
    required BusinessDate authorizedOn,
    required Money authorizedAmount,
    bool startNew = false,
  }) => _draftExclusive((epoch) async {
    _require();
    if (!capabilities.cardAuthorizations) throw PreviewInvalid();
    final intent = _CardAuthorizationIntent(
      kind: 'authorization',
      workspace: _workspace!,
      cardId: cardId,
      chargeId: PublicId.generate(),
      operation: OperationId(PublicId.generate()),
      authorizedOn: authorizedOn,
      postedOn: null,
      amount: authorizedAmount,
      eventId: null,
      accountVersion: null,
      committed: false,
    );
    return await _submitAuthorizationIntent(
      intent,
      epoch,
      startNew: startNew,
      validateNew: () async {
        final account = (await _session!.accounts(_workspace!))
            .where((row) => row.account.id == cardId)
            .single
            .account;
        final terms = await _session!.creditCardTerms(_workspace!);
        if (account.kind != AccountKind.creditCard ||
            account.state != AccountState.active ||
            account.currency != authorizedAmount.currency ||
            !terms.any((term) => term.cardId == cardId) ||
            authorizedAmount.minorUnits <= BigInt.zero ||
            authorizedAmount.minorUnits > BigInt.from(9223372036854775807) ||
            authorizedOn.compareTo(account.openedOn) < 0) {
          throw PreviewInvalid();
        }
      },
    ) as CardAuthorizationFact;
  });

  Future<CardAuthorizationFact> submitCardAuthorizationCancellation(
    PublicId chargeId,
  ) => _draftExclusive((epoch) async {
    _require();
    if (!capabilities.cardAuthorizations) throw PreviewInvalid();
    final fact = (await _session!.cardAuthorizations(_workspace!))
        .where((row) => row.charge.id == chargeId)
        .single;
    final intent = _CardAuthorizationIntent(
      kind: 'cancellation',
      workspace: _workspace!,
      cardId: fact.charge.cardId,
      chargeId: chargeId,
      operation: OperationId(PublicId.generate()),
      authorizedOn: null,
      postedOn: null,
      amount: null,
      eventId: null,
      accountVersion: null,
      committed: false,
    );
    return await _submitAuthorizationIntent(
      intent,
      epoch,
      validateNew: () async {
        if (fact.state != CardAuthorizationState.pending) {
          throw PreviewInvalid();
        }
      },
    ) as CardAuthorizationFact;
  });

  Future<void> submitAuthorizedCardPurchase({
    required PublicId chargeId,
    required BusinessDate postedOn,
    required Money settledAmount,
  }) => _draftExclusive((epoch) async {
    _require();
    if (!capabilities.cardAuthorizations) throw PreviewInvalid();
    final fact = (await _session!.cardAuthorizations(_workspace!))
        .where((row) => row.charge.id == chargeId)
        .single;
    final account = (await _session!.accounts(_workspace!))
        .where((row) => row.account.id == fact.charge.cardId)
        .single
        .account;
    final intent = _CardAuthorizationIntent(
      kind: 'posting',
      workspace: _workspace!,
      cardId: fact.charge.cardId,
      chargeId: chargeId,
      operation: OperationId(PublicId.generate()),
      authorizedOn: null,
      postedOn: postedOn,
      amount: settledAmount,
      eventId: PublicId.generate(),
      accountVersion: account.version,
      committed: false,
    );
    await _submitAuthorizationIntent(
      intent,
      epoch,
      validateNew: () async {
        final history = await _session!.creditCardTermsHistory(_workspace!);
        if (fact.state != CardAuthorizationState.pending ||
            account.kind != AccountKind.creditCard ||
            account.state != AccountState.active ||
            account.currency != settledAmount.currency ||
            !history.any((revision) => revision.terms.cardId == account.id) ||
            settledAmount.minorUnits <= BigInt.zero ||
            settledAmount.minorUnits > BigInt.from(9223372036854775807) ||
            postedOn.compareTo(fact.charge.authorizedOn) < 0) {
          throw PreviewInvalid();
        }
      },
    );
  });
}
