import 'package:core/constants/category_colors.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../model/compose_draft.dart';
import '../model/compose_form.dart';
import '../../../core/messages/problem_messages.dart';
import '../model/receipt_photos.dart';
import '../../../core/design_system/spacing.dart';
import 'compose_widgets.dart';
import 'entry_view_card.dart';
import 'compose_actions.dart';
import 'fill_layout.dart';
import 'form_frame.dart';
import 'form_rows.dart';
import '../../../core/formatting/words.dart';
import 'composer.dart';
import 'composer_fields.dart';
import 'composer_lend.dart';
import 'composer_extras.dart';
import 'composer_pickers.dart';
import 'composer_amount.dart';

class ComposerState extends State<Composer>
    with WidgetsBindingObserver
    implements ComposeActions {
  /// The fields and their rules.
  @override
  late final ComposeForm form = ComposeForm(
    widget.ledger,
    type: widget.type,
    editing: widget.entry,
    draft: widget.draft,
    refunded: widget.refundOf,
    brokerDiscount: widget.brokerDiscount,
  );

  @override
  final note = TextEditingController();
  String? shownProblem;

  /// An entry opened from a list is shown first; 編輯 unlocks it.
  @override
  late var viewing = widget.entry != null;

  Ledger get composerLedger => widget.ledger;

  /// This ledger's forms put aside, by tab.
  ComposeDrafts get _drafts =>
      ComposeDrafts(composerLedger.drafts, composerLedger.attachmentCommands);

  /// The form was put aside as the app went to the background, in case
  /// the phone closes it there; taken back when the app returns.
  var _keptAway = false;

  /// The draft that tab had before, put back when the app returns.
  String? _before;

  /// A choice open in place of the form, if any.
  ComposerPage? _page;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(takeLeftoverPhoto());
    if (widget.entry == null && widget.draft == null && form.refunded == null) {
      final draft = _drafts[form.mode];
      if (draft != null) _takeDraft(draft);
    }
    note
      ..text = form.note
      ..addListener(() => form.note = note.text);
    _opened = formPrint(form);
  }

  /// The form as it opened (a draft taken back included), to ask before
  /// leaving changes (D83).
  late final String _opened;

  /// The form differs from how it opened; an entry only looked at never.
  bool get _changed => !viewing && formPrint(form) != _opened;

  /// Fills the form from [draft], and what it paid for others.
  void _takeDraft(ComposeDraft draft) {
    form.restore(draft.entry, draft.receipt);
    form.date = draft.dateOn(composerLedger.today);
    if (draft.lent != null && form.mode == ComposeMode.expense) {
      form.lent = draft.lent;
    }
  }

  /// The form as it stands, to put aside.
  ComposeDraft get _asDraft =>
      ComposeDraft(form.build(), form.receipt, form.lent, composerLedger.today);

  /// Shows the form's note again after the form filled it afresh.
  void _showNote() {
    if (note.text != form.note) note.text = form.note;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Answers a choice still open with none, without building again: the
    // sheet is going away (still mounted until super.dispose).
    final page = _page;
    _page = null;
    page?.close();
    note.dispose();
    super.dispose();
  }

  /// Starts the current tab afresh.
  void _fresh() {
    form.fresh();
    shownProblem = null;
    _showNote();
  }

  /// 代墊 from the expense tab, 對方還錢 from the income tab.
  @override
  void lend({required bool back}) {
    update(() {
      form.lend(back: back);
      if (back) form.payAll();
    });
    if (form.people.isEmpty) unawaited(choosePerson());
  }

  /// Back from 代墊 or 對方還錢 to a plain entry of the same tab.
  @override
  void unlend() => update(() {
    form.mode = form.tab;
    form.paying = {};
  });

  /// Opens a choice inside the sheet in place of the form, titled
  /// [title]; [build] is given what to call with the value chosen. The
  /// arrow back or the phone's back returns to the form with none.
  Future<T?> openPage<T>(
    String title,
    Widget Function(ValueChanged<T> done) build,
  ) {
    _page?.close();
    final result = Completer<T?>();
    late final ComposerPage page;
    void finish(T? value) {
      if (result.isCompleted) return;
      result.complete(value);
      if (identical(_page, page)) update(() => _page = null);
    }

    page = ComposerPage(title, build(finish), () => finish(null));
    update(() => _page = page);
    return result.future;
  }

  /// A category picked ([ComposeForm.pickCategory] says what else moves).
  @override
  void pickCategoryName(String name) => update(() => form.pickCategory(name));

  /// Moves to another tab: the fields start afresh, or as that tab's
  /// draft left them. A receipt photo already chosen stays, unless the
  /// draft brings its own: the photo is of what was bought or paid,
  /// whichever kind of entry it turns out to be.
  void _switch(ComposeMode mode) {
    if (mode == form.mode) return;
    setState(() {
      form.switchTo(mode);
      final draft = _drafts[mode];
      if (draft != null && widget.entry == null) {
        final photo = form.receipt;
        _takeDraft(draft);
        form.receipt ??= photo;
      }
      shownProblem = null;
      _showNote();
    });
  }

  @override
  Color get color {
    if (form.refunded != null) return AppColors.positive;
    return form.tab.color;
  }

  /// What the tabs do not say: an entry being changed, money paid for
  /// someone or paid back, a refund. Shown as small tags under the top
  /// row; a new plain entry needs none.
  List<(String, Color)> get _marks => [
    if (form.refunded != null) (Words.refund, AppColors.positive),
    if (widget.entry != null && !viewing) ('編輯中', AppColors.accent),
  ];

  String get _action {
    if (widget.entry != null) return '儲存修改';
    if (form.refunded != null) return '記下${Words.refund}';
    if (form.lending && form.own <= 0) return '記下代墊';
    return switch (form.type) {
      EntryType.expense => '記下支出',
      EntryType.income => '記下收入',
      EntryType.transfer when form.mode == ComposeMode.lend =>
        form.back ? '記下還款' : '記下代墊',
      EntryType.transfer => '確認轉帳',
      EntryType.buy => '記下買進',
      EntryType.sell => '記下賣出',
      EntryType.dividend => '記下股息',
    };
  }

  @override
  Future<String?> newCategory() async {
    final income = form.tab == ComposeMode.income;
    final count = composerLedger.categories.all.length;
    final made = await widget.categoryEditor(
      context,
      title: income ? '新增收入分類' : '新增支出分類',
      initial: Category(
        '',
        income ? 'income' : 'other',
        nextCategoryColor(count),
        income: income,
      ),
      colors: AppColors.categoryColors,
      ledger: composerLedger,
    );
    if (made == null) return null;
    composerLedger.categoryCommands.addCategory(made);
    return made.name;
  }

  @override
  void split() => setState(form.toggleSplit);

  @override
  void evenly() => setState(form.evenly);

  /// A category from the whole list while splitting: added as a part,
  /// unless it is one already.
  @override
  Future<void> addPart() async {
    final name = await chooseCategory(null);
    if (name == null) return;
    final parts = form.parts ?? const [];
    if (parts.any((p) => p.$1 == name)) return;
    setState(() => form.addPart(name));
  }

  Future<void> editPart(int index) async {
    final parts = form.parts;
    if (parts == null) return;
    final (name, value) = parts[index];
    final amount = await askAmount(name, value);
    if (amount == null) return;
    setState(() => form.setPart(index, amount));
  }

  @override
  void changeTrade(EntryType trade) => setState(() => form.changeTrade(trade));

  /// A new entry written part way is kept as the app leaves, so a phone
  /// short of memory closing the app loses nothing: it is there, with
  /// its photo, the next time 記一筆 opens. Back in time, it is taken
  /// away again, unless it was put aside with 暫存 before.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.entry != null || viewing || form.refunded != null) {
      return;
    }
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        if (_keptAway || (form.amount == 0 && form.receipt == null)) {
          return;
        }
        try {
          final draft = _asDraft;
          _before = composerLedger.drafts.of(form.tab.name);
          _drafts[form.tab] = draft;
          _keptAway = true;
        } on Object {
          // A form that cannot be built yet is not worth keeping.
        }
      case AppLifecycleState.resumed:
        if (!_keptAway) return;
        _keptAway = false;
        composerLedger.attachmentCommands.setDraft(form.tab.name, _before);
      default:
        break;
    }
  }

  void _submit() {
    final problem = form.problem;
    if (problem != null) {
      setState(() => shownProblem = problem);
      return;
    }
    // Paid partly for others, more than one entry, written as one, with
    // the receipt photo, in place of what was opened.
    final made = form.buildAll();
    final entry = made.first;
    try {
      composerLedger.entryCommands.save(
        made,
        replacing: form.openedIds,
        receipt: form.receipt,
        receiptOn: entry.id,
      );
    } on LedgerProblem catch (error) {
      // Said to the person below the form, as anywhere else.
      setState(() => shownProblem = describeProblem(error));
      return;
    }
    _drafts.remove(form.tab);
    EditGuard.close(context, (ComposeOutcome.saved, entry));
  }

  void _putAside() {
    _keptAway = false;
    _drafts[form.tab] = _asDraft;
    EditGuard.close(context);
  }

  /// Closes the form for the entry to be deleted, not asked first: the
  /// deletion is told with 復原 (D82, `deleteEntries`).
  void _delete() {
    final entry = widget.entry;
    if (entry == null) return;
    EditGuard.close(context, (ComposeOutcome.deleted, entry));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: note,
    builder: (context, _) => EditGuard(changed: _changed, child: _body()),
  );

  Widget _body() {
    if (_page case final page?) {
      return SubpageFrame(
        title: page.title,
        onBack: page.close,
        body: page.body,
      );
    }
    final entry = widget.entry;
    final refunded = form.refunded;
    final canRefund =
        viewing &&
        entry != null &&
        entry.type == EntryType.expense &&
        composerLedger.entryQueryService.refundable(entry) > 0;
    // An entry looked at shows its own card in place of the form, until
    // 編輯.
    final looked = viewing && entry != null && refunded == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (looked)
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Space.s5,
                Space.s1,
                Space.s5,
                0,
              ),
              child: EntryView(
                ledger: composerLedger,
                entry: entry,
                mode: form.mode,
                marks: _marks,
                photos: widget.photos,
                receipt: form.receipt,
              ),
            ),
          )
        else
          ..._form(entry),
        // 刪除 or 暫存 and the main button stay at the foot of the sheet,
        // in reach however long the form is.
        FormFooter(
          discard: entry != null ? Words.delete : '暫存',
          discardColor: entry != null ? AppColors.danger : AppColors.muted,
          onDiscard: entry != null ? _delete : _putAside,
          onRefund: canRefund
              ? () => EditGuard.close(context, (ComposeOutcome.refund, entry))
              : null,
          action: viewing ? Words.edit : _action,
          actionColor: viewing ? AppColors.accent : color,
          onAction: viewing ? () => setState(() => viewing = false) : _submit,
          cancel: !viewing,
        ),
      ],
    );
  }

  /// The form: the top, the amount pinned under it, and the fields under
  /// that, which scroll, cut off at the amount's foot.
  List<Widget> _form(Entry? entry) {
    final all = kindFields();
    final hero = switch (all) {
      [final AmountHero first, ...] => first,
      _ => null,
    };
    final problem = shownProblem;
    // Said before saving; the entry may still be kept.
    final warning = viewing ? null : form.warning;
    final below = [
      if (hero?.under case final under?) ...[
        const SizedBox(height: Space.s1),
        under,
      ],
      ...hero == null ? all : all.skip(1),
      if (problem != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: Text(problem, textAlign: TextAlign.center, style: dangerText),
        )
      else if (warning != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: Text(
            warning,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.goldText),
          ),
        ),
    ];
    return [
      _top(entry),
      if (hero != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s5),
          child: IgnorePointer(
            ignoring: viewing,
            child: AmountHero(
              label: hero.label,
              unit: hero.unit,
              value: hero.value,
              color: hero.color,
              onTap: hero.onTap,
              sub: hero.sub,
              // Kept from the tab's own hero: the untouched 0 stays faint.
              empty: hero.empty,
              spoken: hero.spoken,
            ),
          ),
        ),
      const SizedBox(height: Space.s2),
      // The sheet is as tall as the tallest tab's fields, which scroll
      // inside it past three quarters of the screen.
      Flexible(
        child: ClipRect(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, 0),
            child: IgnorePointer(
              ignoring: viewing,
              child: FillLayout(
                // Each tab takes only the room its fields need: kept at
                // the tallest one's height, a short tab after 投資 left a
                // blank.
                minHeight: 0,
                grow: -1,
                onHeight: (_) {},
                children: below,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// The top, which stays put: the kind of entry, or what is being
  /// changed, and the marks on it.
  Widget _top(Entry? entry) {
    final refunded = form.refunded;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (refunded != null)
            Padding(
              padding: const EdgeInsets.only(right: Space.s2, bottom: Space.s1),
              child: OriginalEntryTile(ledger: composerLedger, entry: refunded),
            )
          else if (viewing)
            Center(child: Pill(form.mode.label, color: form.mode.color))
          else if (entry == null)
            EntryTypeTabs(
              labels: [for (final m in ComposeForm.tabs) m.label],
              selected: ComposeForm.tabs.indexOf(form.tab),
              color: form.tab.color,
              onChanged: (i) => _switch(ComposeForm.tabs[i]),
              onReset: () => setState(() {
                _drafts.remove(form.tab);
                form.mode = form.tab;
                _fresh();
              }),
            ),
          if (_marks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.s1, right: Space.s2),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                children: [
                  for (final (label, color) in _marks)
                    Pill(label, color: color, tinted: true),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// A word on the scan in the form itself: a note at the foot of the
  /// screen would sit under the sheet, out of sight.
  void sayNote(String words) => update(() => shownProblem = words);

  @override
  void update(VoidCallback change) {
    if (mounted) setState(change);
  }

  // What the sections of the form ask of it (ComposeActions).

  @override
  Future<int?> ask(String title, int initial, {String unit = homeCode}) =>
      askAmount(title, initial, unit: unit);

  @override
  Future<void> calculate() => typeAmount();

  @override
  Future<void> pickHolding() => chooseHolding();

  @override
  Widget hero({Widget? under, String? unit}) =>
      amountHero(under: under, unit: unit);

  @override
  Widget pair(Widget left, Widget right) => pairCards(left, right);

  @override
  Widget accountPick(String label) => accountCard(label);

  @override
  Widget datePick() => dateCard();

  @override
  ReceiptPhotos? get photos => widget.photos;

  @override
  Future<void> pickMerchant() => chooseMerchant();

  @override
  Future<void> pickTags() => chooseTags();

  @override
  Widget receiptSquare(ReceiptPhotos photos) => receiptBeside(photos);

  @override
  bool get editing => widget.entry != null;

  @override
  Future<void> pickPerson() => choosePerson();

  @override
  Future<void> pickLent() => chooseLent();

  @override
  Widget categories({required bool expense}) =>
      CategoryFields(this).row(expense: expense);

  @override
  bool get fresh => !viewing && widget.entry == null && widget.draft == null;

  @override
  bool get canScan => widget.scan != null;

  @override
  Future<void> scanInvoice() => scanPaperInvoice();

  @override
  Future<String?> pickCategory(String? selected) => chooseCategory(selected);
}
