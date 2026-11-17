import 'package:flutter/material.dart';

import '../../accounts/compose/account_editor.dart';
import '../compose/recurring_editor.dart';
import '../../../core/text/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/ui/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/entry_tile.dart';
import '../../../core/nav.dart';
import '../model/recurring_schedule.dart';
import '../model/subscriptions.dart';
import '../../../core/ui/shown_amounts.dart';

part 'recurring_calendar.dart';
part 'recurring_lists.dart';
part 'recurring_rows.dart';

/// The colour of 定期交易, as on 更多.
const _recurringHue = Palette.orange;

/// The grey of a day with several items, or with all of them booked.
const _busyDay = Hue.surface;

/// An item's colour and mark: its category's.
(Glyph, Color) _mark(Ledger ledger, Recurring item) {
  final c = ledger.category(item.category);
  return (iconFor(c.icon), shownColor(Color(c.color)));
}

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

  void _book(Recurring item) => widget.nav.compose(draft: ledger.booking(item));

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
        final plan = monthPlan(ledger, year, month);
        final day = _day ?? firstShown(plan, today, year, month);
        final current = _month == _now;
        final header = CenterHeader(
          '定期交易',
          onBack: widget.nav.back,
          actions: [
            HeaderButton(
              glyph: Glyph.list,
              label: '管理',
              onTap: () =>
                  widget.nav.open(Pages.recurringView(RecurringView.manage)),
            ),
            HeaderButton(glyph: Glyph.add, label: '新增', onTap: _edit),
          ],
        );
        if (ledger.recurring.all.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              header,
              EmptyState(
                glyph: Glyph.cycleCalendar,
                color: _recurringHue,
                message: '房租、訂閱、薪水這些固定的，\n記一次就會每期提醒',
                action: '新增固定交易',
                onAction: _edit,
              ),
            ],
          );
        }
        final paused = [
          for (final r in ledger.recurring.all)
            if (!r.active) r,
        ];
        var toCome = 0;
        for (final list in plan.values) {
          for (final d in list) {
            if (!d.settled && !d.item.income) {
              toCome += ledger.recurringWorth(d.item);
            }
          }
        }
        final yearly = yearlyCosts(ledger).fold(0, (sum, r) => sum + r.$2);
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          header: header,
          children: [
            Row(
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
                    onPressed: () => setState(() {
                      _month = _now;
                      _day = null;
                    }),
                    style: wordButton(
                      Hue.accent,
                      fill: Hue.selected,
                      minimumSize: Size(0, 44),
                      radius: 22,
                    ),
                    child: const Text(
                      '回到今天',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                for (final (glyph, label, by) in const [
                  (Glyph.back, '上個月', -1),
                  (Glyph.next, '下個月', 1),
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Material(
                      color: Hue.surface,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: label,
                        onPressed: () => _step(by),
                        icon: GlyphIcon(glyph, size: 20),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _Calendar(
              ledger: ledger,
              year: year,
              month: month,
              plan: plan,
              chosen: day,
              onPick: (d) => setState(() => _day = d),
            ),
            if (day != null) ...[
              const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            CardGrid(columns: 3, gap: 8, [
              _Cell(
                label: current ? '還沒扣' : '$month 月要扣',
                value: ledger.orDots(groupDigits(toCome)),
              ),
              _Cell(
                label: '固定支出/年 ›',
                value: ledger.orDots(groupDigits(yearly)),
                onTap: () => widget.nav.open(
                  Pages.recurringView(RecurringView.subscriptions),
                ),
              ),
              _Cell(
                label: '已暫停 ›',
                value: '${paused.length} 項',
                onTap: () =>
                    widget.nav.open(Pages.recurringView(RecurringView.paused)),
              ),
            ]),
          ],
        );
      },
    );
  }
}
