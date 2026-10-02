part of 'preview_engine.dart';

enum InvestmentIntentResolution { committed, discarded }

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

/// Vault-owned retry identity survives an ambiguous dividend commit.
final class _InvestmentDividendIntent {
  const _InvestmentDividendIntent(this.preview, this.eventId, this.committed);

  final InvestmentDividendPreview preview;
  final PublicId eventId;
  final bool committed;

  String get signature =>
      const InvestmentDividendPreviewCodec().encode(preview);

  _InvestmentDividendIntent complete() =>
      _InvestmentDividendIntent(preview, eventId, true);

  String encode() => jsonEncode([
    'investment-dividend-intent-v1',
    committed ? 'committed' : 'pending',
    signature,
    eventId.value,
  ]);

  static _InvestmentDividendIntent decode(String raw, WorkspaceId workspace) {
    try {
      final fields = jsonDecode(raw);
      if (fields is! List ||
          fields.length != 4 ||
          fields[0] != 'investment-dividend-intent-v1' ||
          (fields[1] != 'pending' && fields[1] != 'committed') ||
          fields[2] is! String ||
          fields[3] is! String) {
        throw const FormatException('Invalid dividend intent');
      }
      final intent = _InvestmentDividendIntent(
        const InvestmentDividendPreviewCodec().decode(fields[2] as String),
        PublicId.parse(fields[3] as String),
        fields[1] == 'committed',
      );
      if (intent.preview.operation.workspace != workspace ||
          intent.encode() != raw) {
        throw const FormatException('Noncanonical dividend intent');
      }
      return intent;
    } catch (_) {
      throw DraftUnavailable();
    }
  }
}

/// A split has no cash event; its own immutable ID is the receipt result.
final class _InvestmentSplitIntent {
  const _InvestmentSplitIntent(this.preview, this.committed);

  final StockSplitPreview preview;
  final bool committed;
  String get signature => const StockSplitPreviewCodec().encode(preview);

  _InvestmentSplitIntent complete() => _InvestmentSplitIntent(preview, true);

  String encode() => jsonEncode([
    'investment-split-intent-v1',
    committed ? 'committed' : 'pending',
    signature,
  ]);

  static _InvestmentSplitIntent decode(String raw, WorkspaceId workspace) {
    try {
      final fields = jsonDecode(raw);
      if (fields is! List ||
          fields.length != 3 ||
          fields[0] != 'investment-split-intent-v1' ||
          (fields[1] != 'pending' && fields[1] != 'committed') ||
          fields[2] is! String) {
        throw const FormatException('Invalid split intent');
      }
      final intent = _InvestmentSplitIntent(
        const StockSplitPreviewCodec().decode(fields[2] as String),
        fields[1] == 'committed',
      );
      if (intent.preview.operation.workspace != workspace ||
          intent.encode() != raw) {
        throw const FormatException('Noncanonical split intent');
      }
      return intent;
    } catch (_) {
      throw DraftUnavailable();
    }
  }
}

extension PreviewInvestments on PreviewEngine {
  String get _investmentSplitIntentSlot =>
      'investment_split_intent_${_identity!.value}';

  Future<_InvestmentSplitIntent?> _readInvestmentSplitIntent() async {
    final raw = await vault.read(_investmentSplitIntentSlot);
    if (raw == null) return null;
    return _InvestmentSplitIntent.decode(raw, _workspace!);
  }

  Future<void> _writeInvestmentSplitIntent(
    _InvestmentSplitIntent intent,
  ) async {
    final encoded = intent.encode();
    await vault.write(_investmentSplitIntentSlot, encoded);
    if (await vault.read(_investmentSplitIntentSlot) != encoded) {
      throw DraftUnavailable();
    }
  }

  Future<List<InvestmentSplitFact>> investmentSplits([PublicId? accountId]) =>
      _exclusive((epoch) async {
        _require();
        if (!capabilities.investmentSplits) throw PreviewInvalid();
        final facts = await _session!.investmentSplits(_workspace!, accountId);
        _check(epoch);
        return facts;
      });

  Future<bool> hasPendingInvestmentSplit() => _exclusive((epoch) async {
    _require();
    if (!capabilities.investmentSplits) throw PreviewInvalid();
    final intent = await _readInvestmentSplitIntent();
    _check(epoch);
    return intent != null && !intent.committed;
  });

  Future<void> _replayInvestmentSplit(
    _InvestmentSplitIntent intent,
    int epoch,
  ) async {
    _check(epoch);
    await _session!.postInvestmentSplit(intent.preview);
    draftCheckpoint?.call('investment-split-committed');
    _check(epoch);
    await _writeInvestmentSplitIntent(intent.complete());
  }

  Future<void> retryPendingInvestmentSplit() => _draftExclusive((epoch) async {
    _require();
    if (!capabilities.investmentSplits) throw PreviewInvalid();
    final intent = await _readInvestmentSplitIntent();
    if (intent == null || intent.committed) throw PreviewInvalid();
    await _replayInvestmentSplit(intent, epoch);
  });

  Future<InvestmentIntentResolution> resolvePendingInvestmentSplit() =>
      _draftExclusive((epoch) async {
        _require();
        if (!capabilities.investmentSplits) throw PreviewInvalid();
        final intent = await _readInvestmentSplitIntent();
        if (intent == null || intent.committed) throw PreviewInvalid();
        final facts = await _session!.investmentSplits(_workspace!);
        _check(epoch);
        final related = facts
            .where(
              (fact) =>
                  fact.preview.id == intent.preview.id ||
                  fact.preview.operation == intent.preview.operation,
            )
            .toList(growable: false);
        if (related.length > 1) throw DraftUnavailable();
        if (related case [final fact]) {
          if (const StockSplitPreviewCodec().encode(fact.preview) !=
              intent.signature) {
            throw DraftUnavailable();
          }
          await _writeInvestmentSplitIntent(intent.complete());
          return InvestmentIntentResolution.committed;
        }
        await vault.delete(_investmentSplitIntentSlot);
        if (await vault.read(_investmentSplitIntentSlot) != null) {
          throw DraftUnavailable();
        }
        _check(epoch);
        return InvestmentIntentResolution.discarded;
      });

  Future<void> submitInvestmentSplit(StockSplitPreview preview) =>
      _draftExclusive((epoch) async {
        _require();
        if (!capabilities.investmentSplits ||
            preview.operation.workspace != _workspace) {
          throw PreviewInvalid();
        }
        final pendingBuy = await _readInvestmentIntent();
        final pendingSell = await _readInvestmentSellIntent();
        final pendingDividend = await _readInvestmentDividendIntent();
        if ((pendingBuy != null && !pendingBuy.committed) ||
            (pendingSell != null && !pendingSell.committed) ||
            (pendingDividend != null && !pendingDividend.committed)) {
          throw DraftNeedsResolution();
        }
        final prior = await _readInvestmentSplitIntent();
        final signature = const StockSplitPreviewCodec().encode(preview);
        if (prior != null && !prior.committed && prior.signature != signature) {
          throw DraftNeedsResolution();
        }
        final intent = prior?.signature == signature
            ? prior!
            : _InvestmentSplitIntent(preview, false);
        if (!identical(intent, prior)) {
          await _writeInvestmentSplitIntent(intent);
        }
        await _replayInvestmentSplit(intent, epoch);
      });

  String get _investmentDividendIntentSlot =>
      'investment_dividend_intent_${_identity!.value}';

  Future<_InvestmentDividendIntent?> _readInvestmentDividendIntent() async {
    final raw = await vault.read(_investmentDividendIntentSlot);
    if (raw == null) return null;
    return _InvestmentDividendIntent.decode(raw, _workspace!);
  }

  Future<void> _writeInvestmentDividendIntent(
    _InvestmentDividendIntent intent,
  ) async {
    final encoded = intent.encode();
    await vault.write(_investmentDividendIntentSlot, encoded);
    if (await vault.read(_investmentDividendIntentSlot) != encoded) {
      throw DraftUnavailable();
    }
  }

  Future<List<InvestmentDividendFact>> investmentDividends([
    PublicId? accountId,
  ]) => _exclusive((epoch) async {
    _require();
    if (!capabilities.investmentDividends) throw PreviewInvalid();
    final facts = await _session!.investmentDividends(_workspace!, accountId);
    _check(epoch);
    return facts;
  });

  Future<bool> hasPendingInvestmentDividend() => _exclusive((epoch) async {
    _require();
    if (!capabilities.investmentDividends) throw PreviewInvalid();
    final intent = await _readInvestmentDividendIntent();
    _check(epoch);
    return intent != null && !intent.committed;
  });

  Future<void> _replayInvestmentDividend(
    _InvestmentDividendIntent intent,
    int epoch,
  ) async {
    _check(epoch);
    await _session!.postInvestmentDividend(intent.preview, intent.eventId);
    draftCheckpoint?.call('investment-dividend-committed');
    _check(epoch);
    await _writeInvestmentDividendIntent(intent.complete());
  }

  Future<void> retryPendingInvestmentDividend() =>
      _draftExclusive((epoch) async {
        _require();
        if (!capabilities.investmentDividends) throw PreviewInvalid();
        final intent = await _readInvestmentDividendIntent();
        if (intent == null || intent.committed) throw PreviewInvalid();
        await _replayInvestmentDividend(intent, epoch);
      });

  Future<InvestmentIntentResolution> resolvePendingInvestmentDividend() =>
      _draftExclusive((epoch) async {
        _require();
        if (!capabilities.investmentDividends) throw PreviewInvalid();
        final intent = await _readInvestmentDividendIntent();
        if (intent == null || intent.committed) throw PreviewInvalid();
        final facts = await _session!.investmentDividends(_workspace!);
        _check(epoch);
        final related = facts
            .where(
              (fact) =>
                  fact.preview.id == intent.preview.id ||
                  fact.preview.operation == intent.preview.operation ||
                  fact.eventId == intent.eventId,
            )
            .toList(growable: false);
        if (related.length > 1) throw DraftUnavailable();
        if (related case [final fact]) {
          if (fact.eventId != intent.eventId ||
              const InvestmentDividendPreviewCodec().encode(fact.preview) !=
                  intent.signature) {
            throw DraftUnavailable();
          }
          await _writeInvestmentDividendIntent(intent.complete());
          return InvestmentIntentResolution.committed;
        }
        await vault.delete(_investmentDividendIntentSlot);
        if (await vault.read(_investmentDividendIntentSlot) != null) {
          throw DraftUnavailable();
        }
        _check(epoch);
        return InvestmentIntentResolution.discarded;
      });

  Future<void> submitInvestmentDividend(InvestmentDividendPreview preview) =>
      _draftExclusive((epoch) async {
        _require();
        if (!capabilities.investmentDividends ||
            preview.operation.workspace != _workspace) {
          throw PreviewInvalid();
        }
        final pendingBuy = await _readInvestmentIntent();
        final pendingSell = await _readInvestmentSellIntent();
        if ((pendingBuy != null && !pendingBuy.committed) ||
            (pendingSell != null && !pendingSell.committed)) {
          throw DraftNeedsResolution();
        }
        if (capabilities.investmentSplits) {
          final pendingSplit = await _readInvestmentSplitIntent();
          if (pendingSplit != null && !pendingSplit.committed) {
            throw DraftNeedsResolution();
          }
        }
        final prior = await _readInvestmentDividendIntent();
        final signature = const InvestmentDividendPreviewCodec().encode(
          preview,
        );
        if (prior != null && !prior.committed && prior.signature != signature) {
          throw DraftNeedsResolution();
        }
        final intent = prior?.signature == signature
            ? prior!
            : _InvestmentDividendIntent(preview, PublicId.generate(), false);
        if (!identical(intent, prior)) {
          await _writeInvestmentDividendIntent(intent);
        }
        await _replayInvestmentDividend(intent, epoch);
      });

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

  Future<InvestmentIntentResolution> resolvePendingInvestmentBuy() =>
      _draftExclusive((epoch) async {
        _require();
        if (!capabilities.investments) throw PreviewInvalid();
        final intent = await _readInvestmentIntent();
        if (intent == null || intent.committed) throw PreviewInvalid();
        final facts = await _session!.investmentBuys(_workspace!);
        _check(epoch);
        final related = facts
            .where(
              (fact) =>
                  fact.preview.id == intent.preview.id ||
                  fact.preview.operation == intent.preview.operation ||
                  fact.eventId == intent.eventId,
            )
            .toList(growable: false);
        if (related.length > 1) throw DraftUnavailable();
        if (related case [final fact]) {
          if (fact.eventId != intent.eventId ||
              const InvestmentBuyPreviewCodec().encode(fact.preview) !=
                  intent.signature) {
            throw DraftUnavailable();
          }
          await _writeInvestmentIntent(intent.complete());
          return InvestmentIntentResolution.committed;
        }
        await vault.delete(_investmentIntentSlot);
        if (await vault.read(_investmentIntentSlot) != null) {
          throw DraftUnavailable();
        }
        _check(epoch);
        return InvestmentIntentResolution.discarded;
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
        if (capabilities.investmentDividends) {
          final pendingDividend = await _readInvestmentDividendIntent();
          if (pendingDividend != null && !pendingDividend.committed) {
            throw DraftNeedsResolution();
          }
        }
        if (capabilities.investmentSplits) {
          final pendingSplit = await _readInvestmentSplitIntent();
          if (pendingSplit != null && !pendingSplit.committed) {
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

  Future<InvestmentIntentResolution> resolvePendingInvestmentSell() =>
      _draftExclusive((epoch) async {
        _require();
        if (!capabilities.investmentSales) throw PreviewInvalid();
        final intent = await _readInvestmentSellIntent();
        if (intent == null || intent.committed) throw PreviewInvalid();
        final facts = await _session!.allInvestmentSales(_workspace!);
        _check(epoch);
        final related = facts
            .where(
              (fact) =>
                  fact.preview.id == intent.preview.id ||
                  fact.preview.operation == intent.preview.operation ||
                  fact.eventId == intent.eventId,
            )
            .toList(growable: false);
        if (related.length > 1) throw DraftUnavailable();
        if (related case [final fact]) {
          if (fact.eventId != intent.eventId ||
              const InvestmentSellPreviewCodec().encode(fact.preview) !=
                  intent.signature) {
            throw DraftUnavailable();
          }
          await _writeInvestmentSellIntent(intent.complete());
          return InvestmentIntentResolution.committed;
        }
        await vault.delete(_investmentSellIntentSlot);
        if (await vault.read(_investmentSellIntentSlot) != null) {
          throw DraftUnavailable();
        }
        _check(epoch);
        return InvestmentIntentResolution.discarded;
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
        if (capabilities.investmentDividends) {
          final pendingDividend = await _readInvestmentDividendIntent();
          if (pendingDividend != null && !pendingDividend.committed) {
            throw DraftNeedsResolution();
          }
        }
        if (capabilities.investmentSplits) {
          final pendingSplit = await _readInvestmentSplitIntent();
          if (pendingSplit != null && !pendingSplit.committed) {
            throw DraftNeedsResolution();
          }
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
