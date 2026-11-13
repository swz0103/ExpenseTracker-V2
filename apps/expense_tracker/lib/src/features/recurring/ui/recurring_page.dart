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

/// The colour of 定期交易, as on 更多.
const _recurringHue = Shade(0xFFD08B5B, 0xFFE3AA82);

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
            if (d.booked == null && !d.item.income) {
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

/// The month as a white calendar: day numbers on one line, a fixed slot
/// under each for its mark, dots or tick, and 到期 under a day due.
class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.ledger,
    required this.year,
    required this.month,
    required this.plan,
    required this.chosen,
    required this.onPick,
  });

  final Ledger ledger;
  final int year;
  final int month;
  final Map<int, List<Due>> plan;
  final int? chosen;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final today = ledger.today;
    final first = DateTime.utc(year, month);
    final days = DateTime.utc(year, month + 1, 0).day;
    // Sunday first, as the design reads.
    final lead = first.weekday % 7;
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var d = 1; d <= days; d++) _dayCell(d, today),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox());
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: Hue.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: Hue.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final w in const ['日', '一', '二', '三', '四', '五', '六'])
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Hue.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var r = 0; r < cells.length; r += 7)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final cell in cells.sublist(r, r + 7))
                  Expanded(child: cell),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell(int d, DateTime today) {
    final day = DateTime.utc(year, month, d);
    final todayDay = DateTime.utc(today.year, today.month, today.day);
    final isToday = day == todayDay;
    final past = day.isBefore(todayDay);
    final items = plan[d] ?? const <Due>[];
    final allBooked = items.isNotEmpty && items.every((x) => x.booked != null);
    final due = items.any((x) => x.booked == null) && !day.isAfter(todayDay);
    final single = items.length == 1 && !allBooked;
    final (glyph, color) = single
        ? _mark(ledger, items.first.item)
        : (Glyph.other, Hue.muted);
    final isChosen = d == chosen;
    BoxDecoration? fill;
    if (single) {
      fill = BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, const Color(0xFFFFFFFF), 0.15)!, color],
        ),
      );
    } else if (items.isNotEmpty) {
      fill = BoxDecoration(
        color: _busyDay,
        borderRadius: BorderRadius.circular(12),
      );
    }
    final onColor = single ? const Color(0xFFFFFFFF) : Hue.ink;
    final number = Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: isToday
          ? const BoxDecoration(color: Hue.accent, shape: BoxShape.circle)
          : null,
      child: Text(
        '$d',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: isToday
              ? Hue.onAccent
              : single
              ? onColor
              : past && items.isEmpty
              ? Hue.faint
              : Hue.ink,
        ),
      ),
    );
    Widget slot;
    if (allBooked) {
      slot = const GlyphIcon(Glyph.check, size: 14, color: Hue.muted);
    } else if (single) {
      slot = GlyphIcon(
        glyph,
        size: 16,
        color: const Color(0xFFFFFFFF),
        tinted: false,
      );
    } else if (items.isNotEmpty) {
      slot = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final x in items.take(3))
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: x.booked == null ? _mark(ledger, x.item).$2 : Hue.faint,
                shape: BoxShape.circle,
              ),
            ),
        ],
      );
    } else {
      slot = const SizedBox();
    }
    return Semantics(
      button: true,
      selected: isChosen,
      label:
          '$month 月 $d 日'
          '${items.isEmpty ? '' : '，${items.length} 筆${due ? '，到期' : ''}'}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onPick(d),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            children: [
              Container(
                height: 50,
                decoration: (fill ?? const BoxDecoration()).copyWith(
                  borderRadius: BorderRadius.circular(12),
                  border: isChosen
                      ? Border.all(color: Hue.accent, width: 2)
                      : null,
                ),
                foregroundDecoration: isChosen
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Hue.white, width: 2),
                      )
                    : null,
                padding: const EdgeInsets.only(top: 3),
                child: Column(
                  children: [
                    number,
                    SizedBox(height: 18, child: Center(child: slot)),
                  ],
                ),
              ),
              SizedBox(
                height: 14,
                child: due
                    ? const Text(
                        '到期',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Hue.negative,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chosen day: its date and how far off, then its items as cards
/// (side by side to slide through when several), or a line to add one.
class _DayItems extends StatefulWidget {
  const _DayItems({
    required this.ledger,
    required this.day,
    required this.items,
    required this.onBook,
    required this.onEdit,
    required this.onOpen,
    required this.onAdd,
  });

  final Ledger ledger;
  final DateTime day;
  final List<Due> items;
  final ValueChanged<Recurring> onBook;
  final ValueChanged<Recurring> onEdit;
  final ValueChanged<Entry> onOpen;
  final VoidCallback onAdd;

  @override
  State<_DayItems> createState() => _DayItemsState();
}

class _DayItemsState extends State<_DayItems> {
  var _page = 0;

  @override
  void didUpdateWidget(_DayItems old) {
    super.didUpdateWidget(old);
    if (old.day != widget.day) _page = 0;
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final today = ledger.today;
    final todayDay = DateTime.utc(today.year, today.month, today.day);
    final day = widget.day;
    final items = widget.items;
    final away = day.difference(todayDay).inDays;
    final allBooked = items.isNotEmpty && items.every((x) => x.booked != null);
    final overdue = items.any((x) => x.booked == null) && away < 0;
    final total = items.fold(
      0,
      (sum, x) => sum + ledger.recurringWorth(x.item),
    );
    final when = away == 0
        ? '今天'
        : away > 0
        ? '$away 天後'
        : '過了 ${-away} 天';
    final right = items.isEmpty
        ? (away > 0 ? '$away 天後' : '')
        : allBooked
        ? '已入帳'
        : overdue
        ? when
        : items.length > 1
        ? '$when · 合計 ${ledger.orDots(groupDigits(total))}'
        : when;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                '${day.month}/${day.day} 週${weekdayNames[day.weekday - 1]}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                right,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: overdue ? Hue.negative : Hue.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text('這天沒有固定交易', style: TextStyle(color: Hue.muted)),
              ),
              const Spacer(),
              TextButton(
                onPressed: widget.onAdd,
                style: TextButton.styleFrom(
                  foregroundColor: Hue.accent,
                  minimumSize: const Size(0, 48),
                ),
                child: const Text(
                  '＋ 新增',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          )
        else if (items.length == 1)
          _itemCard(items.first, todayDay)
        else ...[
          SizedBox(
            height:
                120 *
                (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1, 1.6),
            child: PageView(
              controller: PageController(viewportFraction: 0.86),
              padEnds: false,
              onPageChanged: (p) => setState(() => _page = p),
              children: [
                for (final (i, x) in items.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: i == _page ? 1 : 0.55,
                      child: _itemCard(x, todayDay),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (i, x) in items.indexed)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _page ? _mark(ledger, x.item).$2 : Hue.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _itemCard(Due x, DateTime todayDay) {
    final ledger = widget.ledger;
    final item = x.item;
    final booked = x.booked;
    final (glyph, markColor) = _mark(ledger, item);
    final color = booked == null ? markColor : Hue.faint;
    final due = booked == null && !x.day.isAfter(todayDay);
    final away = x.day.difference(todayDay).inDays;
    final account = ledger.account(item.account).name;
    final line = booked != null
        ? '已入帳 · ${booked.date.month}/${booked.date.day}'
        : due
        ? '$account · 到期'
        : '$account · ${away == 0 ? '今天' : '$away 天後'}';
    return ColorCard(
      color: color,
      onTap: () => booked == null ? widget.onEdit(item) : widget.onOpen(booked),
      label: '${item.name}，${line.replaceAll(' · ', '，')}',
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        children: [
          booked == null
              ? SquareIcon(glyph, color, size: 58)
              : Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Hue.white,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  alignment: Alignment.center,
                  child: GlyphIcon(glyph, size: 28, color: Hue.muted),
                ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: deepOf(color),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${item.income ? '+' : ''}'
                    '${ledger.orDots(recurringAmount(ledger, item))}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: item.income && booked == null
                          ? Hue.positive
                          : Hue.ink,
                    ),
                  ),
                ),
                Text(
                  line,
                  style: TextStyle(
                    fontSize: 13,
                    color: due ? Hue.negative : deepOf(color),
                    fontWeight: due ? FontWeight.w800 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (due)
            FilledButton(
              onPressed: () => widget.onBook(item),
              style: FilledButton.styleFrom(
                backgroundColor: markColor,
                foregroundColor: const Color(0xFFFFFFFF),
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '入帳',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          else if (booked != null)
            const GlyphIcon(Glyph.check, size: 22, color: Hue.muted),
        ],
      ),
    );
  }
}

/// A small grey cell along the bottom: a label over a figure.
class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ColorCard(
      color: Hue.faint,
      amount: 0.22,
      radius: 16,
      onTap: onTap,
      label: '$label $value',
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// An item as a square card in its colour: mark, name, amount and how
/// often and from where.
class _ItemSquare extends StatelessWidget {
  const _ItemSquare({
    required this.ledger,
    required this.item,
    required this.onTap,
    this.grey = false,
    this.trailing,
    this.lines,
  });

  final Ledger ledger;
  final Recurring item;
  final VoidCallback onTap;
  final bool grey;
  final Widget? trailing;
  final List<String>? lines;

  @override
  Widget build(BuildContext context) {
    final (glyph, mark) = _mark(ledger, item);
    final color = grey ? Hue.faint : mark;
    return ColorCard(
      color: color,
      onTap: onTap,
      label: item.name,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              grey
                  ? Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Hue.white,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: GlyphIcon(glyph, size: 20, color: Hue.muted),
                    )
                  : SquareIcon(glyph, color, size: 42),
              const Spacer(),
              trailing ??
                  const GlyphIcon(Glyph.next, size: 14, color: Hue.muted),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: deepOf(color),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${item.income ? '+' : ''}'
              '${ledger.orDots(recurringAmount(ledger, item))}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: item.income && !grey ? Hue.positive : Hue.ink,
              ),
            ),
          ),
          for (final line
              in lines ??
                  ['${item.rhythm} · ${ledger.account(item.account).name}'])
            Text(line, style: TextStyle(fontSize: 12, color: deepOf(color))),
        ],
      ),
    );
  }
}

/// A sub-page's frame: its header and what is under it.
class _SubPage extends StatelessWidget {
  const _SubPage({
    required this.title,
    required this.children,
    this.actions = const [],
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
    children: [
      CenterHeader(
        title,
        onBack: () => Navigator.of(context).pop(),
        actions: actions,
      ),
      ...children,
    ],
  );
}

/// 管理固定項目: every active item as a square, 支出 then 收入, each
/// side with how many and what they come to a month.
class _Manage extends StatelessWidget {
  const _Manage({required this.ledger, required this.onEdit});

  final Ledger ledger;
  final Future<void> Function({Recurring? item, DateTime? on}) onEdit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final today = ledger.today;
        List<Widget> side(bool income) {
          final items = [
            for (final r in ledger.recurring)
              if (r.active && r.income == income) r,
          ];
          if (items.isEmpty) return const [];
          var monthly = 0;
          for (final r in items) {
            monthly +=
                ledger.recurringWorth(r) *
                r.datesIn(today.year, today.month).length;
          }
          return [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
              child: Row(
                children: [
                  Text(
                    income ? '收入' : '支出',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${items.length} 項 · 每月 ${ledger.orDots(groupDigits(monthly))}',
                    style: mutedSmall,
                  ),
                ],
              ),
            ),
            CardGrid(gap: 10, [
              for (final r in items)
                _ItemSquare(
                  ledger: ledger,
                  item: r,
                  onTap: () => onEdit(item: r),
                ),
            ]),
          ];
        }

        return _SubPage(
          title: '管理固定項目',
          actions: [HeaderButton(glyph: Glyph.add, label: '新增', onTap: onEdit)],
          children: [...side(false), ...side(true)],
        );
      },
    );
  }
}

/// 訂閱與固定支出: what the fixed spending comes to a year and a month,
/// a bar of each item's share, and each item's year, month and share,
/// the dearest first.
class _Subscriptions extends StatelessWidget {
  const _Subscriptions({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final rows = yearlyCosts(ledger);
    final total = rows.fold(0, (sum, row) => sum + row.$2);
    return _SubPage(
      title: '訂閱與固定支出',
      children: [
        if (rows.isEmpty)
          const EmptyState(
            glyph: Glyph.subscription,
            color: _recurringHue,
            message: '還沒有固定支出',
          )
        else ...[
          const Text(
            '一年下來',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          Text(
            ledger.orDots(groupDigits(total)),
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
          ),
          Text(
            '平均每月 ${ledger.orDots(groupDigits(total ~/ 12))}',
            style: mutedSmall,
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final (i, (item, yearly)) in rows.indexed) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: (yearly * 1000 ~/ total).clamp(1, 1000),
                      child: ColoredBox(
                        color: _mark(ledger, item).$2,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 18, 4, 10),
            child: Row(
              children: [
                Text(
                  '每一項一年多少',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                Spacer(),
                Text('依金額', style: mutedSmall),
              ],
            ),
          ),
          CardGrid(gap: 10, [
            for (final (item, yearly) in rows)
              _ItemSquare(
                ledger: ledger,
                item: item,
                onTap: () {},
                trailing: const SizedBox(),
                lines: [
                  '一年 ${ledger.orDots(groupDigits(yearly))}',
                  '每月 ${ledger.orDots(groupDigits(yearly ~/ 12))} · '
                      '佔 ${yearly * 100 ~/ total}%',
                ],
              ),
          ]),
        ],
      ],
    );
  }
}

/// 已暫停: what pausing means, then each paused item in grey with 恢復.
class _Paused extends StatelessWidget {
  const _Paused({required this.ledger, required this.onEdit});

  final Ledger ledger;
  final Future<void> Function({Recurring? item, DateTime? on}) onEdit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final paused = [
          for (final r in ledger.recurring)
            if (!r.active) r,
        ];
        return _SubPage(
          title: '已暫停',
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: Text('暫停的項目不會出現在月曆上，也不算進每月固定支出。', style: mutedSmall),
            ),
            if (paused.isEmpty)
              const EmptyState(
                glyph: Glyph.cycleCalendar,
                color: _recurringHue,
                message: '沒有暫停的項目',
              )
            else
              CardGrid(gap: 10, [
                for (final r in paused)
                  _ItemSquare(
                    ledger: ledger,
                    item: r,
                    grey: true,
                    onTap: () => onEdit(item: r),
                    trailing: FilledButton(
                      onPressed: () =>
                          ledger.saveRecurring(r.copyWith(active: true)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Hue.white,
                        foregroundColor: Hue.accent,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '恢復',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ]),
          ],
        );
      },
    );
  }
}
