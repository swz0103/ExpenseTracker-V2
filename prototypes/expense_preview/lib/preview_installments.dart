part of 'preview_engine.dart';

/// Private-vault intent permits replay after an ambiguous encrypted commit.
/// A plan is a forecast linked to an existing posted purchase, never a new
/// expense or an issuer-confirmed statement.
final class _CardInstallmentIntent {
  const _CardInstallmentIntent(this.plan, this.operation, this.committed);

  final CardInstallmentSchedule plan;
  final OperationId operation;
  final bool committed;

  String get signature => const CardInstallmentScheduleCodec().encode(plan);

  _CardInstallmentIntent complete() =>
      _CardInstallmentIntent(plan, operation, true);

  String encode() => jsonEncode([
    'card-installment-intent-v1',
    committed ? 'committed' : 'pending',
    signature,
    operation.id.value,
  ]);

  static _CardInstallmentIntent decode(String raw, WorkspaceId workspace) {
    try {
      final fields = jsonDecode(raw);
      if (fields is! List ||
          fields.length != 4 ||
          fields[0] != 'card-installment-intent-v1' ||
          (fields[1] != 'pending' && fields[1] != 'committed') ||
          fields[2] is! String ||
          fields[3] is! String) {
        throw const FormatException('Invalid installment intent');
      }
      final intent = _CardInstallmentIntent(
        const CardInstallmentScheduleCodec().decode(fields[2] as String),
        OperationId.parse(fields[3] as String),
        fields[1] == 'committed',
      );
      if (intent.plan.workspace != workspace || intent.encode() != raw) {
        throw const FormatException('Noncanonical installment intent');
      }
      return intent;
    } catch (_) {
      throw DraftUnavailable();
    }
  }
}

extension PreviewInstallments on PreviewEngine {
  String get _installmentIntentSlot =>
      'card_installment_intent_${_identity!.value}';

  Future<_CardInstallmentIntent?> _readInstallmentIntent() async {
    final raw = await vault.read(_installmentIntentSlot);
    if (raw == null) return null;
    return _CardInstallmentIntent.decode(raw, _workspace!);
  }

  Future<void> _writeInstallmentIntent(_CardInstallmentIntent intent) async {
    final encoded = intent.encode();
    await vault.write(_installmentIntentSlot, encoded);
    if (await vault.read(_installmentIntentSlot) != encoded) {
      throw DraftUnavailable();
    }
  }

  Future<List<CardInstallmentPurchase>> availableInstallmentPurchases(
    PublicId cardId,
  ) => _exclusive((epoch) async {
    _require();
    if (!capabilities.installments) throw PreviewInvalid();
    final rows = await _session!.availableCardInstallmentPurchases(
      _workspace!,
      cardId,
    );
    _check(epoch);
    return rows;
  });

  Future<List<CardInstallmentFact>> savedCardInstallmentPlans(
    PublicId cardId,
  ) => _exclusive((epoch) async {
    _require();
    if (!capabilities.installments) throw PreviewInvalid();
    final rows = await _session!.cardInstallmentPlans(_workspace!, cardId);
    _check(epoch);
    return rows;
  });

  Future<bool> hasPendingInstallmentPlan() => _exclusive((epoch) async {
    _require();
    if (!capabilities.installments) throw PreviewInvalid();
    final intent = await _readInstallmentIntent();
    _check(epoch);
    return intent != null && !intent.committed;
  });

  Future<void> _replayInstallmentPlan(
    _CardInstallmentIntent intent,
    int epoch,
  ) async {
    _check(epoch);
    await _session!.createCardInstallmentPlan(intent.plan, intent.operation);
    draftCheckpoint?.call('card-installment-committed');
    _check(epoch);
    await _writeInstallmentIntent(intent.complete());
  }

  Future<void> retryPendingInstallmentPlan() => _draftExclusive((epoch) async {
    _require();
    if (!capabilities.installments) throw PreviewInvalid();
    final intent = await _readInstallmentIntent();
    if (intent == null || intent.committed) throw PreviewInvalid();
    await _replayInstallmentPlan(intent, epoch);
  });

  Future<void> submitCardInstallmentPlan(CardInstallmentSchedule plan) =>
      _draftExclusive((epoch) async {
        _require();
        if (!capabilities.installments || plan.workspace != _workspace) {
          throw PreviewInvalid();
        }
        final prior = await _readInstallmentIntent();
        final signature = const CardInstallmentScheduleCodec().encode(plan);
        if (prior != null && !prior.committed && prior.signature != signature) {
          throw DraftNeedsResolution();
        }
        final intent = prior?.signature == signature
            ? prior!
            : _CardInstallmentIntent(
                plan,
                OperationId(PublicId.generate()),
                false,
              );
        if (!identical(intent, prior)) await _writeInstallmentIntent(intent);
        await _replayInstallmentPlan(intent, epoch);
      });
}
