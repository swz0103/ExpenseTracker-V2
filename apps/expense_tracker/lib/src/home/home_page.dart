import 'package:flutter/material.dart';

import 'category_section.dart';
import 'day_section.dart';
import 'holdings_section.dart';
import 'home_data.dart';
import 'month_section.dart';

/// The first screen, one quiet page: this month, where it went,
/// investments and the day's entries. Each part shows little and opens
/// up when tapped.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    const rule = Divider(indent: 24, endIndent: 24);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MonthSection(data: data),
                CategorySection(data: data),
                rule,
                HoldingsSection(data: data),
                rule,
                DaySection(data: data),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
