import 'package:flutter/material.dart';

import '../../accounts/compose/account_editor.dart';
import '../compose/recurring_editor.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/entry_tile.dart';
import '../../../core/nav.dart';
import '../model/calendar.dart';
import '../model/subscriptions.dart';

part 'recurring_calendar.dart';
part 'recurring_lists.dart';

/// The colour of 定期交易, as on 更多.
const _recurringHue = Palette.orange;

/// The grey of a day with several items, or with all of them booked.
const _busyDay = Shade(0xFFEAEEEC, 0xFF3E4A50);

/// An item's colour and mark: its category's.
(Glyph, Color) _mark(Ledger ledger, Recurring item) {
  final c = ledger.category(item.category);
  return (iconFor(c.icon), c.color);
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

  Future<void> _edit({Recurring? item, DateTime? on}) async {
    if (!await ensureAccount(context, ledger) || !mounted) return;
    await editRecurring(context, ledger, item: item, on: on);
  }

  void _push(Widget Function(BuildContext) page) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        backgroundColor: Hue.paper,
        body: SafeArea(child: page(context)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger.watch(const {
        Area.entries,
        Area.recurring,
        Area.accounts,
        Area.categories,
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
                  _push((context) => _Manage(ledger: ledger, onEdit: _edit)),
            ),
            HeaderButton(glyph: Glyph.add, label: '新增', onTap: _edit),
          ],
        );
        if (ledger.recurring.isEmpty) {
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
          for (final r in ledger.recurring)
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
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            header,
            Row(
              children: [
                Text(
                  '$month 月',
                  style: const TextStyle(
                    fontSize: 32,
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
                    style: TextButton.styleFrom(
                      backgroundColor: Hue.selected,
                      foregroundColor: Hue.accent,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
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
                label: current ? '本月還沒扣' : '$month 月要扣',
                value: ledger.orDots(groupDigits(toCome)),
              ),
              _Cell(
                label: '訂閱與固定支出 ›',
                value: '一年 ${ledger.orDots(groupDigits(yearly))}',
                onTap: () => _push((context) => _Subscriptions(ledger: ledger)),
              ),
              _Cell(
                label: '已暫停 ›',
                value: '${paused.length} 項',
                onTap: () =>
                    _push((context) => _Paused(ledger: ledger, onEdit: _edit)),
              ),
            ]),
          ],
        );
      },
    );
  }
}
