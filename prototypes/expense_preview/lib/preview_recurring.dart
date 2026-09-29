part of 'preview_engine.dart';

extension PreviewRecurring on PreviewEngine {
  Future<List<RecurringTemplate>> savedRecurringTemplates() =>
      _exclusive((epoch) async {
        _require();
        if (!capabilities.recurring) throw PreviewInvalid();
        final templates = await _session!.recurringTemplates(_workspace!);
        _check(epoch);
        return templates;
      });

  Future<List<RecurringCandidate>> dueRecurringCandidates({
    required BusinessDate after,
    required BusinessDate through,
  }) => _exclusive((epoch) async {
    _require();
    if (!capabilities.recurring) throw PreviewInvalid();
    final candidates = await _session!.recurringDue(
      _workspace!,
      after: after,
      through: through,
    );
    _check(epoch);
    return candidates;
  });

  Future<void> saveRecurringTemplate(
    RecurringTemplate template,
    OperationId operation, {
    bool deleted = false,
  }) => _exclusive((epoch) async {
    _require();
    if (!capabilities.recurring || template.workspace != _workspace) {
      throw PreviewInvalid();
    }
    await _session!.saveRecurringTemplate(
      template,
      operation,
      DateTime.now().toUtc(),
      deleted: deleted,
    );
    _check(epoch);
  });

  Future<({PublicId eventId, bool replayed})> confirmRecurringCandidate(
    RecurringCandidate candidate,
    PublicId eventId,
    OperationId operation,
  ) => _exclusive((epoch) async {
    _require();
    if (!capabilities.recurring || candidate.template.workspace != _workspace) {
      throw PreviewInvalid();
    }
    final result = await _session!.confirmRecurring(
      candidate,
      eventId,
      operation,
      DateTime.now().toUtc(),
    );
    _check(epoch);
    return result;
  });
}
