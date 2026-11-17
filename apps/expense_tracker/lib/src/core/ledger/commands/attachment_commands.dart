import '../persistence/ledger_data_source.dart';
import '../repositories/draft_repository.dart';
import '../repositories/receipt_repository.dart';
import 'command_context.dart';

/// Writes what is kept beside the entries: receipt photos and the forms
/// put aside in the composer.
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

  /// Gives the entry with [id] the receipt photo [file], or takes its
  /// photo away when null.
  void setReceipt(String id, String? file) {
    if (!_receipts.set(id, file)) return;
    _context.signal();
    _context.keep(WriteBatch(receipts: {id: file}));
  }
}
