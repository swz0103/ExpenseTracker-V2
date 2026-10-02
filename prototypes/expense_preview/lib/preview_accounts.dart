part of 'preview_engine.dart';

extension PreviewAccounts on PreviewEngine {
  Future<void> renameAccount(
    OperationKey operation,
    Account account,
    String name,
  ) => _accountCommand(operation, account, (session) {
    return session.renameAccount(operation, account.id, account.version, name);
  });

  Future<void> setAccountNetWorthInclusion(
    OperationKey operation,
    Account account,
    bool included,
  ) => _accountCommand(operation, account, (session) {
    return session.setAccountNetWorthInclusion(
      operation,
      account.id,
      account.version,
      included,
    );
  });

  Future<void> archiveAccount(OperationKey operation, Account account) =>
      _accountCommand(operation, account, (session) {
        return session.archiveAccount(operation, account.id, account.version);
      });

  Future<void> reactivateAccount(OperationKey operation, Account account) =>
      _accountCommand(operation, account, (session) {
        return session.reactivateAccount(
          operation,
          account.id,
          account.version,
        );
      });

  Future<void> closeAccount(
    OperationKey operation,
    Account account, {
    required BusinessDate date,
    required String reason,
    PublicId? successorId,
  }) => _accountCommand(operation, account, (session) {
    return session.closeAccount(
      operation,
      account.id,
      account.version,
      date: date,
      reason: reason,
      successorId: successorId,
    );
  });

  Future<void> _accountCommand(
    OperationKey operation,
    Account account,
    Future<Object?> Function(LedgerSession) work,
  ) => _exclusive((epoch) async {
    _require();
    if (operation.workspace != _workspace || account.workspace != _workspace) {
      throw PreviewInvalid();
    }
    await work(_session!);
    _check(epoch);
  });
}
