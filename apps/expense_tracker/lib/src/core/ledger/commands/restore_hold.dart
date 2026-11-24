import '../models/models.dart';

/// What stands in the way of putting an entry back from the trash as it
/// is (D78), for the person to decide.
sealed class RestoreHold {
  const RestoreHold();
}

/// It names accounts closed (archived) since it was deleted.
final class ClosedAccounts extends RestoreHold {
  const ClosedAccounts(this.accounts);

  final List<Account> accounts;
}

/// A refund whose purchase is in the trash too: they may come back
/// together.
final class OriginalInTrash extends RestoreHold {
  const OriginalInTrash(this.original);

  final Trashed original;
}

/// A refund whose purchase is gone for good: it would come back refunding
/// nothing the book has.
final class OriginalGone extends RestoreHold {
  const OriginalGone();
}
