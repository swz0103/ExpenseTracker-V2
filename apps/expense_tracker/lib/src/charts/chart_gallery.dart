import 'package:flutter/material.dart';

import 'bars_chart.dart';
import 'calendar_chart.dart';
import 'chart_data.dart';
import 'donut_chart.dart';
import 'treemap_chart.dart';
import 'trend_chart.dart';

/// The five chart options side by side, to pick from in the preview.
class ChartGallery extends StatelessWidget {
  const ChartGallery({super.key, required this.data});

  final ChartData data;

  @override
  Widget build(BuildContext context) {
    final options = [
      ('A 長條', '點長條或左右拖曳，看當月收支與前五大分類。', BarsChart(data: data)),
      ('B 趨勢', '切換收支或淨資產、3／6／12 個月；按住拖曳讀數值。', TrendChart(data: data)),
      ('C 圓環', '點扇形或下方分類，凸出顯示金額與占比。', DonutChart(data: data)),
      ('D 日曆', '顏色越深花越多；點日期看當天，左右滑換月。', CalendarChart(data: data)),
      ('E 方塊', '面積代表金額；點分類看子分類，再點一次回上層。', TreemapChart(data: data)),
    ];
    return DefaultTabController(
      length: options.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('圖表方案（示範資料）'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final (name, _, _) in options) Tab(text: name)],
          ),
        ),
        body: TabBarView(
          // Charts take sideways drags themselves.
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final (_, hint, chart) in options)
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            hint,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Card.outlined(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: RepaintBoundary(child: chart),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
