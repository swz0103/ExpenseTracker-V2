import '../persistence/write_batch.dart';
import '../repositories/draft_repository.dart';
import '../repositories/receipt_repository.dart';
import 'command_context.dart';

/// Writes what is kept beside the entries: the forms put aside in the
/// composer. A receipt photo is written with its entry, by the entry
/// commands' `add` and `replace`.
final class AttachmentCommands {
  AttachmentCommands({
    required this._context,
    required ReceiptRepository receiptRepository,
    required DraftRepository draftRepository,
  }) : _receipts = receiptRepository,
       _drafts = draftRepository;

  final CommandContext _context;
  final ReceiptRepository _receipts;
  final DraftRepository _drafts;

  /// Every receipt photo an entry keeps, deleted entries' included, and
  /// those chosen on a form put aside: what a sweep of the photo folder
  /// must leave.
  Set<String> get receiptFiles => {..._receipts.files, ..._drafts.receipts};

  /// Keeps the form put aside on [tab], or clears it when [json] is null.
  void setDraft(String tab, String? json) {
    if (!_drafts.set(tab, json)) return;
    _context.keep(WriteBatch(drafts: {tab: json}));
  }
}
