import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/charts/treemap.dart';
import '../../../../core/look/figures.dart';
import '../../../../core/look/icons.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/ledger/ledger.dart';

/// 財務分布: where the assets are as a map of tiles, largest first. A tap
/// picks a tile; a second opens a group of accounts or the holdings.
class AssetsSection extends StatefulWidget {
  const AssetsSection({super.key, required this.ledger});

  final Ledger ledger;

  @override
  State<AssetsSection> createState() => _AssetsSectionState();
}

class _AssetsSectionState extends State<AssetsSection> {
  int? _tile;

  /// The opened part: null for all assets, else 'investment' or an
  /// account kind's name.
  String? _assetGroup;

  /// Colours for the second level, in v114's order.
  static const _shades = Hue.shades;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ledger,
      builder: (context, _) {
        final parts = _assets();
        if (parts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: parts,
        );
      },
    );
  }

  /// The tiles at the current level, largest first, each with the key it
  /// opens to.
  List<(String, String, int, Color)> _assetParts() {
    final ledger = widget.ledger;
    final group = _assetGroup;
    List<(String, String, int, Color)> shaded(List<(String, String, int)> l) {
      l.sort((a, b) => b.$3.compareTo(a.$3));
      return [
        for (final (i, (key, name, value)) in l.indexed)
          (key, name, value, _shades[i % _shades.length]),
      ];
    }

    if (group == 'investment') {
      return shaded([
        for (final h in ledger.holdings)
          if (h.value > 0) (h.code, h.code, h.value),
      ]);
    }
    if (group != null) {
      return shaded([
        for (final a in ledger.accounts)
          if (a.kind.name == group && _counted(a) && ledger.worthOf(a) > 0)
            (a.id, a.name, ledger.worthOf(a)),
      ]);
    }
    int sumOf(AccountKind kind) {
      var total = 0;
      for (final a in ledger.accounts) {
        if (a.kind == kind && _counted(a)) {
          total += max(0, ledger.worthOf(a));
        }
      }
      return total;
    }

    final parts = [
      ('investment', '投資', ledger.investValue, Hue.holdings),
      for (final kind in const [
        AccountKind.bank,
        AccountKind.cash,
        AccountKind.wallet,
        AccountKind.receivable,
      ])
        (kind.name, groupName(kind), sumOf(kind), accountColor(kind)),
    ]..sort((a, b) => b.$3.compareTo(a.$3));
    return [
      for (final p in parts)
        if (p.$3 > 0) p,
    ];
  }

  /// Whether [a] counts: in net worth and still open.
  static bool _counted(Account a) => a.inNetWorth && !a.archived;

  void _openAssets(String? group) {
    setState(() {
      _assetGroup = group;
      _tile = null;
    });
  }

  List<Widget> _assets() {
    final ledger = widget.ledger;
    final parts = _assetParts();
    final group = _assetGroup;
    final tile = _tile == null || _tile! >= parts.length ? null : _tile;
    final total = parts.fold<int>(0, (sum, p) => sum + p.$3);
    if (total == 0 && group == null) return const [];
    final scope = switch (group) {
      null => '資產',
      'investment' => '資產 › 投資',
      _ => '資產 › ${groupName(AccountKind.values.byName(group))}',
    };
    final allName = switch (group) {
      null => '全部資產',
      'investment' => '全部持股',
      _ => '全部帳戶',
    };
    final shownName = tile == null ? allName : parts[tile].$2;
    final shownAmount = tile == null ? total : parts[tile].$3;
    final share = tile == null || total == 0
        ? ''
        : '　${(shownAmount * 100 / total).round()}%';
    return [
      SectionHead(
        '財務分布',
        trailing: Text(
          ledger.money(shownAmount),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      // One height whether or not the links show, so a tap on the map
      // does not push the page down.
      SizedBox(
        height: 36,
        child: Row(
          children: [
            Text(scope, style: mutedSmall),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$shownName$share',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            if (tile != null)
              SmallLink('全部', () => setState(() => _tile = null)),
            if (group != null) SmallLink('返回資產', () => _openAssets(null)),
          ],
        ),
      ),
      const SizedBox(height: 4),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: Semantics(
          key: ValueKey(group),
          container: true,
          label:
              '$allName：'
              '${[for (final p in parts) '${p.$2} ${ledger.money(p.$3)}'].join('、')}',
          child: Treemap(
            tiles: [for (final p in parts) (p.$2, p.$3, p.$4)],
            selected: tile,
            onSelect: (index) => setState(() => _tile = index),
            onOpen: (index) =>
                _openAssets(group == null ? parts[index].$1 : null),
          ),
        ),
      ),
    ];
  }
}
