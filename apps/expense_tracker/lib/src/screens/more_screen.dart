import 'package:flutter/material.dart';

import '../ui/kit.dart';

/// Everything that is not on the bottom bar.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.reports});

  /// The report screen, opened from here.
  final Widget reports;

  static const _items = [
    (Icons.insights_outlined, '報表'),
    (Icons.show_chart, '投資'),
    (Icons.pie_chart_outline, '預算'),
    (Icons.event_repeat_outlined, '定期交易'),
    (Icons.category_outlined, '分類'),
    (Icons.sell_outlined, '標籤'),
    (Icons.currency_exchange, '匯率'),
    (Icons.search, '搜尋'),
    (Icons.cloud_upload_outlined, '備份匯出'),
    (Icons.settings_outlined, '設定'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const ScreenHeader(title: '更多'),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          childAspectRatio: 0.9,
          children: [
            for (final (icon, name) in _items)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (name == '報表') {
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => reports));
                  } else {
                    comingSoon(context, name);
                  }
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconTile(icon, size: 36),
                    const SizedBox(height: 4),
                    Text(name, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
