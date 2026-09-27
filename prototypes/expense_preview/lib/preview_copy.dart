part of 'preview_engine.dart';

/// A read-only seed: no amount, date, operation ID or external identity.
/// Merged or archived metadata needs a fresh choice, never a silent redirect.
final class PostingCopy {
  PostingCopy({
    required this.account,
    required this.income,
    this.categoryId,
    required Iterable<TagSelection> tags,
    this.merchant,
    required this.omittedMetadata,
  }) : tags = List.unmodifiable(tags);
  final PostingAccount account;
  final bool income;
  final PublicId? categoryId;
  final List<TagSelection> tags;
  final MerchantSelection? merchant;
  final bool omittedMetadata;
}

extension PreviewCopy on PreviewEngine {
  Future<PostingCopy> preparePostingCopy(PublicId id) => _exclusive((
    epoch,
  ) async {
    _require();
    if (schemaVersion < 5) throw PreviewInvalid();
    final session = _session!;
    final source = await session.entry(workspace, id);
    if (source == null ||
        ![PostingKind.income, PostingKind.expense].contains(source.kind)) {
      throw PreviewInvalid();
    }
    final accounts = await session.accounts(workspace);
    final account = accounts
        .where((a) => a.account.id == source.accountId)
        .firstOrNull
        ?.account;
    if (account == null || account.state != AccountState.active) {
      throw PreviewInvalid();
    }
    final categoryRefs = await session.allocations(workspace, id);
    final categories = await session.categories(workspace);
    PublicId? categoryId;
    var omitted = false;
    if (categoryRefs.length == 1) {
      final category = categories.get(categoryRefs.single.categoryId);
      if (!category.archived && category.replacementId == null) {
        categoryId = category.id;
      } else {
        omitted = true;
      }
    } else if (categoryRefs.isNotEmpty) {
      // A split cannot silently become one category; this form supports one.
      omitted = true;
    }
    final tags = <TagSelection>[];
    if (schemaVersion >= 6) {
      final catalog = await session.tags(workspace);
      for (final ref in await session.tagsFor(workspace, id)) {
        final tag = catalog.get(ref.id);
        if (!tag.archived && tag.replacementId == null) {
          tags.add(TagSelection(tag.id, tag.version));
        } else {
          omitted = true;
        }
      }
    }
    MerchantSelection? merchant;
    if (schemaVersion >= 7) {
      final ref = await session.merchantFor(workspace, id);
      if (ref != null) {
        final item = (await session.merchants(workspace)).get(ref.id);
        if (!item.archived && item.replacementId == null) {
          merchant = MerchantSelection(item.id, item.version);
        } else {
          omitted = true;
        }
      }
    }
    _check(epoch);
    return PostingCopy(
      account: PostingAccount(
        id: account.id,
        workspace: account.workspace,
        currency: account.currency,
        expectedVersion: account.version,
      ),
      income: source.kind == PostingKind.income,
      categoryId: categoryId,
      tags: tags,
      merchant: merchant,
      omittedMetadata: omitted,
    );
  });
}
