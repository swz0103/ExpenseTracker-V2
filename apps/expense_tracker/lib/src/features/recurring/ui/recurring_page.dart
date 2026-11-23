import 'package:flutter/material.dart';

import '../../accounts/forms/account_editor.dart';
import '../forms/recurring_editor.dart';
import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/entry_tile.dart';
import '../../../core/navigation/nav.dart';
import '../model/recurring_schedule.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/month_grid.dart';
import '../../../core/design_system/motion.dart';
import '../../../core/formatting/words.dart';
import 'recurring_rows.dart';
import '../model/subscriptions.dart';

part 'recurring_calendar.dart';
part 'recurring_lists.dart';

/// The colour of 定期交易, as on 更多.
const _recurringColor = Palette.orange;

/// The grey of a day with several items, or with all of them booked.
const _busyDay = AppColors.surface;

/// Adds an item, or changes [item], after making sure there is an account
/// to book it to.
Future<void> _editItem(
  BuildContext context,
  Ledger ledger, {
  Recurring? item,
  DateTime? on,
}) async {
  if (!await ensureAccount(context, ledger) || !context.mounted) return;
  await editRecurring(context, ledger, item: item, on: on);
}

/// A page under 定期交易: 管理固定項目, 訂閱與固定支出 or 已暫停.
class RecurringViewPage extends StatelessWidget {
  const RecurringViewPage({
    super.key,
    required this.ledger,
    required this.nav,
    required this.view,
  });

  final Ledger ledger;
  final Nav nav;
  final RecurringView view;

  @override
  Widget build(BuildContext context) {
    Future<void> edit({Recurring? item, DateTime? on}) =>
        _editItem(context, ledger, item: item, on: on);
    return switch (view) {
      RecurringView.manage => _Manage(ledger: ledger, nav: nav, onEdit: edit),
      RecurringView.subscriptions => _Subscriptions(ledger: ledger, nav: nav),
      RecurringView.paused => _Paused(ledger: ledger, nav: nav, onEdit: edit),
    };
  }
}

/// 定期交易: the month in big words, a calendar of what falls due on
/// which day (one item: the day in its colour with its mark; several:
/// grey with a dot each; booked: grey with a tick; due: 到期 under it),
/// the chosen day's items as cards, and three small cells: what is still
/// to come this month, 訂閱與固定支出 and 已暫停. Opens on the next day
/// with something to book.
class RecurringPage extends StatefulWidget {
  const RecurringPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  /// Opens one of 定期交易's own pages.
  void _view(RecurringView view) =>
      widget.nav.open(AppRoutes.recurringView(view));

  late var _month = _now;

  /// The day chosen; null for the month's first with something.
  int? _day;

  Ledger get ledger => widget.ledger;

  (int, int) get _now => (ledger.today.year, ledger.today.month);

  void _step(int by) => setState(() {
    final next = DateTime.utc(_month.$1, _month.$2 + by);
    _month = (next.year, next.month);
    _day = null;
  });

  void _book(Recurring item) =>
      widget.nav.compose(draft: ledger.recurringService.booking(item));

  Future<void> _edit({Recurring? item, DateTime? on}) =>
      _editItem(context, ledger, item: item, on: on);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger.watch(const {
        Topic.entries,
        Topic.recurring,
        Topic.accounts,
        Topic.categories,
      }),
      builder: (context, _) {
        final (year, month) = _month;
        final today = ledger.today;
        final plan = monthPlanOf(ledger, year, month);
        final day = _day ?? firstShown(plan, today, year, month);
        final current = _month == _now;
        final header = CenterHeader(
          '定期交易',
          onBack: widget.nav.back,
          actions: [
            HeaderButton(
              glyph: Glyph.list,
              label: '管理',
              onTap: () => _view(RecurringView.manage),
            ),
            HeaderButton(glyph: Glyph.add, label: Words.add, onTap: _edit),
          ],
        );
        if (ledger.recurring.all.isEmpty) return _empty(header);
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s4),
          header: header,
          children: [
            _MonthBar(
              month: month,
              current: current,
              onToday: () => setState(() {
                _month = _now;
                _day = null;
              }),
              onStep: _step,
            ),
            const SizedBox(height: Space.s2),
            _Calendar(
              ledger: ledger,
              year: year,
              month: month,
              plan: plan,
              chosen: day,
              onPick: (d) => setState(() => _day = d),
            ),
            if (day != null) ...[
              const SizedBox(height: Space.s4),
              _DayItems(
                ledger: ledger,
                day: DateTime.utc(year, month, day),
                items: plan[day] ?? const [],
                onBook: _book,
                onEdit: (item) => _edit(item: item),
                onOpen: widget.nav.showEntry,
                onAdd: () => _edit(on: DateTime.utc(year, month, day)),
              ),
            ],
            const SizedBox(height: Space.s4),
            _cells(plan, month: month, current: current),
          ],
        );
      },
    );
  }

  /// 定期交易 before anything is added: the header over an invitation to
  /// add the first.
  Widget _empty(Widget header) => ListView(
    padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s8),
    children: [
      header,
      EmptyState(
        glyph: Glyph.cycleCalendar,
        color: _recurringColor,
        message: '房租、訂閱、薪水這些固定的，\n記一次就會每期提醒',
        action: '新增固定交易',
        onAction: _edit,
      ),
    ],
  );

  /// The three cells under the calendar: what is still to be spent in
  /// [month] of [plan], 固定支出/年 and 已暫停.
  Widget _cells(
    Map<int, List<Due>> plan, {
    required int month,
    required bool current,
  }) {
    final paused = [
      for (final r in ledger.recurring.all)
        if (!r.active) r,
    ];
    var toCome = 0;
    for (final list in plan.values) {
      for (final d in list) {
        if (!d.settled && !d.item.income) {
          toCome += ledger.recurringService.worth(d.item);
        }
      }
    }
    final yearly = yearlyCostsOf(ledger).fold(0, (sum, r) => sum + r.$2);
    return CardGrid(columns: 3, gap: 8, [
      _Cell(
        label: current ? '還沒扣' : '$month 月要扣',
        value: ledger.orDots(groupDigits(toCome)),
      ),
      _Cell(
        label: '固定支出/年 ›',
        value: ledger.orDots(groupDigits(yearly)),
        onTap: () => widget.nav.open(
          AppRoutes.recurringView(RecurringView.subscriptions),
        ),
      ),
      _Cell(
        label: '已暫停 ›',
        value: countOf(paused.length, CountUnit.items),
        onTap: () => _view(RecurringView.paused),
      ),
    ]);
  }
}

/// The top of 定期交易: the month in big words, 回到今天 when another
/// month is shown, and the arrows to the month before and after.
class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.current,
    required this.onToday,
    required this.onStep,
  });

  final int month;

  /// Whether the month shown is this month, when 回到今天 is not needed.
  final bool current;
  final VoidCallback onToday;

  /// Moves the month shown by a month back (-1) or forward (1).
  final void Function(int by) onStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$month 月',
          style: const TextStyle(
            fontSize: TextSize.big,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        if (!current)
          TextButton(
            onPressed: onToday,
            style: wordButton(
              AppColors.accent,
              fill: AppColors.selected,
              minimumSize: Size(0, 44),
              radius: Radii.largeIncreased,
            ),
            child: const Text(
              '回到今天',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        for (final (glyph, label, by) in const [
          (Glyph.back, Words.previousMonth, -1),
          (Glyph.next, Words.nextMonth, 1),
        ])
          Padding(
            padding: const EdgeInsets.only(left: Space.s2),
            child: Material(
              color: AppColors.surface,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: label,
                onPressed: () => onStep(by),
                icon: GlyphIcon(glyph, size: 20),
              ),
            ),
          ),
      ],
    );
  }
}

// The recurring models as the screens use them, from the parts of the
// ledger each reads (docs/adr/0013-models-take-what-they-use.md).

/// [ledger]'s recurring items due in [month] of [year], by day.
Map<int, List<Due>> monthPlanOf(Ledger ledger, int year, int month) =>
    monthPlan(ledger.recurring, ledger.recurringService, year, month);

/// What each active spending item of [ledger] costs over a year.
List<(Recurring, int)> yearlyCostsOf(Ledger ledger) =>
    yearlyCosts(ledger.recurring, ledger.recurringService, today: ledger.today);
