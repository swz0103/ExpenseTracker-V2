import 'dart:async';

import '../../../core/design_system/dialogs.dart';
import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ledger/trading.dart';
import '../../../core/widgets/calculator.dart';
import '../../../core/widgets/pickers.dart';
import '../../../core/widgets/pickers_days.dart';
import '../model/compose_form.dart';
import '../../../core/messages/installment_messages.dart';
import '../../../core/messages/invoice_messages.dart';
import '../../../core/messages/scan_messages.dart';
import '../../../core/platform/scan.dart';
import '../model/invoices.dart';
import '../model/invoice_qr.dart';
import 'compose_widgets.dart';
import 'holding_choices.dart';
import '../../../core/formatting/words.dart';
import 'composer_state.dart';

// The choices the form opens: amount, day, account, category, holding,
// merchant, tags and instalments; and what it takes in from outside, an
// invoice scanned and a receipt photo left over.

extension ComposerPickers on ComposerState {
  Future<int?> askAmount(String title, int initial, {String unit = homeCode}) {
    return showCalculator(
      context,
      title: title,
      initial: initial,
      color: color,
      unit: unit,
    );
  }

  Future<void> typeAmount() async {
    final value = await askAmount('輸入金額', form.amount, unit: form.currency);
    if (value == null) return;
    update(() {
      form.setAmount(value);
    });
  }

  Future<void> chooseDate() async {
    final marked = {
      // Exception to as-of-today: the date picker marks every day something is
      // written on.
      for (final e in composerLedger.entries.inMonth(
        form.date.year,
        form.date.month,
      ))
        e.date,
    };
    final day = await openPage<DateTime>(
      Words.date,
      (done) => DayChoices(
        selected: form.date,
        // Spending, income and transfers may be 預定, up to the write
        // rules' limit; shares change hands on the day they do (D25).
        latest: form.mode == ComposeMode.investment
            ? composerLedger.today
            : latestEntryDay(composerLedger.today),
        today: composerLedger.today,
        marked: marked,
        color: color,
        onPick: done,
      ),
    );
    if (day != null) update(() => form.date = day);
  }

  /// An open account; for a refund, one in the purchase's currency.
  Future<String?> chooseAccount(String title, String selected) {
    final refunded = form.refunded;
    final currency = refunded == null
        ? null
        : composerLedger.account(refunded.account).currency;
    return openPage<String>(
      title,
      (done) => AccountChoices(
        ledger: composerLedger,
        selected: selected,
        currency: currency,
        ring: color,
        onPick: done,
      ),
    );
  }

  /// A category from them all; 新增 at the end makes one and gives it.
  Future<String?> chooseCategory(String? selected) async {
    final income = form.tab == ComposeMode.income;
    const adding = '';
    final picked = await openPage<String>(
      income ? '收入分類' : '支出分類',
      (done) => OptionGrid<String>(
        options: [
          ...categoryOptions(composerLedger, income: income),
          if (!viewing)
            const Option(adding, Words.add, Glyph.add, AppColors.muted),
        ],
        selected: selected,
        ring: color,
        onPick: done,
      ),
    );
    if (picked != adding) return picked;
    return newCategory();
  }

  Future<void> chooseHolding() async {
    final picked = await openPage<String>(
      '標的',
      (done) => HoldingChoices(
        ledger: composerLedger,
        selected: form.holding,
        onPick: done,
        onAdd: viewing ? null : () => done(''),
      ),
    );
    if (picked == null) return;
    if (picked.isEmpty) return _newHolding();
    update(() => form.holding = picked);
  }

  Future<void> _newHolding() async {
    final typed = await askText(context, '新增標的代號');
    if (typed == null) return;
    final code = tidyCode(typed);
    if (code.isEmpty) return;
    update(() => form.holding = code);
    if (!quotable(code) && mounted) {
      showNote(context, '證交所與櫃買中心沒有「$code」這個代號，市值會以成本估算');
    }
  }

  Future<void> chooseMerchant() async {
    final picked = await openPage<String>(
      Words.merchant,
      (done) => MerchantPicker(
        known: composerLedger.entryQueryService.merchants,
        initial: form.merchant,
        onDone: done,
      ),
    );
    if (picked == null) return;
    update(() => form.pickMerchant(picked));
  }

  Future<void> chooseTags() async {
    final picked = await openPage<List<String>>(
      Words.tag,
      (done) => TagPicker(
        known: composerLedger.reportService.tags,
        initial: form.tags,
        onDone: done,
      ),
    );
    if (picked != null) update(() => form.tags = picked);
  }

  Future<void> chooseInstallments() async {
    final picked = await openPage<int>(
      '分期付款',
      (done) => OptionGrid<int>(
        selected: form.installments,
        columns: 3,
        ring: color,
        onPick: done,
        options: [
          for (final n in installmentChoices)
            Option(
              n,
              n == 0 ? '不分期' : countOf(n, CountUnit.periods),
              Glyph.card,
              AppColors.muted,
            ),
        ],
      ),
    );
    if (picked != null) update(() => form.installments = picked);
  }

  /// A receipt photo the camera took while the phone closed the app goes
  /// with the next new entry.
  Future<void> takeLeftoverPhoto() async {
    final photos = widget.photos;
    if (photos == null || widget.entry != null || form.refunded != null) {
      return;
    }
    // One that cannot be taken back is told by the phone's side.
    final name = await photos.takeLeftover();
    if (name == null || !mounted) return;
    update(() => form.receipt = name);
  }

  /// Applies `change` while the form is still on screen: the field
  /// builders in composer_fields.dart run it after a dialog closes.
  /// 掃發票: reads a paper e-invoice's left QR code (and its right one when
  /// the items go on there) and fills the form: the day, the total, its
  /// items and number in the note, tagged 發票, and a category guessed from
  /// the items. One already in the book is said, not filled again. When
  /// the right code cannot be read, the left one still fills the form.
  Future<void> scanPaperInvoice() async {
    if (widget.scan == null) return;
    final left = await _scanCode();
    if (left == null || !mounted) return;
    var invoice = InvoiceQr.parse(left);
    if (invoice == null) {
      sayNote(InvoiceMessages.notLeft);
      return;
    }
    if (invoiceRecorded(composerLedger.entries, invoice.date, invoice.number)) {
      sayNote(InvoiceMessages.recorded(invoice.number));
      return;
    }
    if (invoice.wantsMore) {
      sayNote(InvoiceMessages.scanRight);
      final right = await _scanCode();
      if (right != null) invoice = invoice.withRight(right);
    }
    if (!mounted) return;
    final scanned = invoice;
    update(() => form.fillInvoice(scanned));
    // The right code failed: what the left one gives is filled in, and
    // the person is told the items are missing; every field stays theirs
    // to change (D30).
    if (scanned.wantsMore) sayNote(InvoiceMessages.filledWithoutItems);
  }

  /// One code from the scanner; null when there is none, the person
  /// having closed it or the scanner having failed, which is said in the
  /// form with what to do next (the fault itself is in the error log).
  /// While the phone still has to fetch the scanner, the form says so.
  Future<String?> _scanCode() async {
    final scan = widget.scan;
    if (scan == null) return null;
    final outcome = await scan(
      preparing: () => sayNote(ScanMessages.preparing),
    );
    // The wait is over, however it ended.
    if (shownProblem == ScanMessages.preparing) {
      update(() => shownProblem = null);
    }
    switch (outcome) {
      case ScanRead(:final text):
        return text;
      case ScanClosed():
        return null;
      case ScanFailed(:final failure):
        sayNote(ScanMessages.failure(failure));
        return null;
    }
  }
}
