part of 'preview_engine.dart';

/// The private vault retains the exact preview and event ID until the
/// encrypted Ledger result is known. An ambiguous result can only be retried
/// with the same financial identity, never rebuilt as a fresh buy.
final class _InvestmentBuyIntent {
  const _InvestmentBuyIntent(this.preview, this.eventId, this.committed);

  final InvestmentBuyPreview preview;
  final PublicId eventId;
  final bool committed;

  String get signature => const InvestmentBuyPreviewCodec().encode(preview);

  _InvestmentBuyIntent complete() =>
      _InvestmentBuyIntent(preview, eventId, true);

  String encode() => jsonEncode([
    'investment-buy-intent-v1',
    committed ? 'committed' : 'pending',
    signature,
    eventId.value,
  ]);

  static _InvestmentBuyIntent decode(String raw, WorkspaceId workspace) {
    try {
      final fields = jsonDecode(raw);
      if (fields is! List ||
          fields.length != 4 ||
          fields[0] != 'investment-buy-intent-v1' ||
          (fields[1] != 'pending' && fields[1] != 'committed') ||
          fields[2] is! String ||
          fields[3] is! String) {
        throw const FormatException('Invalid investment intent');
      }
      final intent = _InvestmentBuyIntent(
        const InvestmentBuyPreviewCodec().decode(fields[2] as String),
        PublicId.parse(fields[3] as String),
        fields[1] == 'committed',
      );
      if (intent.preview.operation.workspace != workspace ||
          intent.encode() != raw) {
        throw const FormatException('Noncanonical investment intent');
      }
      return intent;
    } catch (_) {
      throw DraftUnavailable();
    }
  }
}

/// A sale retry retains both the complete priced lot snapshot and event ID.
/// Rebuilding a quote from changed holdings after an ambiguous result could
/// post a second sale, so unresolved intents block new sale submissions.
final class _InvestmentSellIntent {
  const _InvestmentSellIntent(this.preview, this.eventId, this.committed);

  final InvestmentSellPreview preview;
  final PublicId eventId;
  final bool committed;

  String get signature => const InvestmentSellPreviewCodec().encode(preview);

  _InvestmentSellIntent complete() =>
      _InvestmentSellIntent(preview, eventId, true);

  String encode() => jsonEncode([
    'investment-sell-intent-v1',
    committed ? 'committed' : 'pending',
    signature,
    eventId.value,
  ]);

  static _InvestmentSellIntent decode(String raw, WorkspaceId workspace) {
    try {
      final fields = jsonDecode(raw);
      if (fields is! List ||
          fields.length != 4 ||
          fields[0] != 'investment-sell-intent-v1' ||
          (fields[1] != 'pending' && fields[1] != 'committed') ||
          fields[2] is! String ||
          fields[3] is! String) {
        throw const FormatException('Invalid investment sale intent');
      }
      final intent = _InvestmentSellIntent(
        const InvestmentSellPreviewCodec().decode(fields[2] as String),
        PublicId.parse(fields[3] as String),
        fields[1] == 'committed',
      );
      if (intent.preview.operation.workspace != workspace ||
          intent.encode() != raw) {
        throw const FormatException('Noncanonical investment sale intent');
      }
      return intent;
    } catch (_) {
      throw DraftUnavailable();
    }
  }
}

extension PreviewInvestments on PreviewEngine {
  String get _investmentIntentSlot =>
      'investment_buy_intent_${_identity!.value}';

  Future<_InvestmentBuyIntent?> _readInvestmentIntent() async {
    final raw = await vault.read(_investmentIntentSlot);
    if (raw == null) return null;
    return _InvestmentBuyIntent.decode(raw, _workspace!);
  }

  Future<void> _writeInvestmentIntent(_InvestmentBuyIntent intent) async {
    final encoded = intent.encode();
    await vault.write(_investmentIntentSlot, encoded);
    if (await vault.read(_investmentIntentSlot) != encoded) {
      throw DraftUnavailable();
    }
  }

  Future<List<InvestmentBuyFact>> investmentBuys() => _exclusive((epoch) async {
    _require();
    if (!capabilities.investments) throw PreviewInvalid();
    final rows = await _session!.investmentBuys(_workspace!);
    _check(epoch);
    return rows;
  });

  Future<bool> hasPendingInvestmentBuy() => _exclusive((epoch) async {
    _require();
    if (!capabilities.investments) throw PreviewInvalid();
    final intent = await _readInvestmentIntent();
    _check(epoch);
    return intent != null && !intent.committed;
  });

  Future<void> _replayInvestmentBuy(
    _InvestmentBuyIntent intent,
    int epoch,
  ) async {
    _check(epoch);
    await _session!.postInvestmentBuy(intent.preview, intent.eventId);
    draftCheckpoint?.call('investment-buy-committed');
    _check(epoch);
    await _writeInvestmentIntent(intent.complete());
  }

  Future<void> retryPendingInvestmentBuy() => _draftExclusive((epoch) async {
    _require();
    if (!capabilities.investments) throw PreviewInvalid();
    final intent = await _readInvestmentIntent();
    if (intent == null || intent.committed) throw PreviewInvalid();
    await _replayInvestmentBuy(intent, epoch);
  });

  Future<void> submitInvestmentBuy(InvestmentBuyPreview preview) =>
      _draftExclusive((epoch) async {
        _require();
        if (!capabilities.investments ||
            preview.operation.workspace != _workspace) {
          throw PreviewInvalid();
        }
        if (capabilities.investmentSales) {
          final pendingSale = await _readInvestmentSellIntent();
          if (pendingSale != null && !pendingSale.committed) {
            throw DraftNeedsResolution();
          }
        }
        final prior = await _readInvestmentIntent();
        final signature = const InvestmentBuyPreviewCodec().encode(preview);
        if (prior != null && !prior.committed && prior.signature != signature) {
          throw DraftNeedsResolution();
        }
        final intent = prior?.signature == signature
            ? prior!
            : _InvestmentBuyIntent(preview, PublicId.generate(), false);
        if (!identical(intent, prior)) await _writeInvestmentIntent(intent);
        await _replayInvestmentBuy(intent, epoch);
      });

  String get _investmentSellIntentSlot =>
      'investment_sell_intent_${_identity!.value}';

  Future<_InvestmentSellIntent?> _readInvestmentSellIntent() async {
    final raw = await vault.read(_investmentSellIntentSlot);
    if (raw == null) return null;
    return _InvestmentSellIntent.decode(raw, _workspace!);
  }

  Future<void> _writeInvestmentSellIntent(_InvestmentSellIntent intent) async {
    final encoded = intent.encode();
    await vault.write(_investmentSellIntentSlot, encoded);
    if (await vault.read(_investmentSellIntentSlot) != encoded) {
      throw DraftUnavailable();
    }
  }

  Future<List<InvestmentHoldingLot>> investmentHoldingLots(
    PublicId accountId,
    PublicId instrumentId,
  ) => _exclusive((epoch) async {
    _require();
    if (!capabilities.investmentSales) throw PreviewInvalid();
    final rows = await _session!.investmentHoldingLots(
      _workspace!,
      accountId,
      instrumentId,
    );
    _check(epoch);
    return rows;
  });

  Future<List<InvestmentSellFact>> investmentSales(
    PublicId accountId,
    PublicId instrumentId,
  ) => _exclusive((epoch) async {
    _require();
    if (!capabilities.investmentSales) throw PreviewInvalid();
    final rows = await _session!.investmentSales(
      _workspace!,
      accountId,
      instrumentId,
    );
    _check(epoch);
    return rows;
  });

  Future<bool> hasPendingInvestmentSell() => _exclusive((epoch) async {
    _require();
    if (!capabilities.investmentSales) throw PreviewInvalid();
    final intent = await _readInvestmentSellIntent();
    _check(epoch);
    return intent != null && !intent.committed;
  });

  Future<void> _replayInvestmentSell(
    _InvestmentSellIntent intent,
    int epoch,
  ) async {
    _check(epoch);
    await _session!.postInvestmentSell(intent.preview, intent.eventId);
    draftCheckpoint?.call('investment-sell-committed');
    _check(epoch);
    await _writeInvestmentSellIntent(intent.complete());
  }

  Future<void> retryPendingInvestmentSell() => _draftExclusive((epoch) async {
    _require();
    if (!capabilities.investmentSales) throw PreviewInvalid();
    final intent = await _readInvestmentSellIntent();
    if (intent == null || intent.committed) throw PreviewInvalid();
    await _replayInvestmentSell(intent, epoch);
  });

  Future<void> submitInvestmentSell(InvestmentSellPreview preview) =>
      _draftExclusive((epoch) async {
        _require();
        if (!capabilities.investmentSales ||
            preview.operation.workspace != _workspace) {
          throw PreviewInvalid();
        }
        final pendingBuy = await _readInvestmentIntent();
        if (pendingBuy != null && !pendingBuy.committed) {
          throw DraftNeedsResolution();
        }
        final prior = await _readInvestmentSellIntent();
        final signature = const InvestmentSellPreviewCodec().encode(preview);
        if (prior != null && !prior.committed && prior.signature != signature) {
          throw DraftNeedsResolution();
        }
        final intent = prior?.signature == signature
            ? prior!
            : _InvestmentSellIntent(preview, PublicId.generate(), false);
        if (!identical(intent, prior)) await _writeInvestmentSellIntent(intent);
        await _replayInvestmentSell(intent, epoch);
      });
}
