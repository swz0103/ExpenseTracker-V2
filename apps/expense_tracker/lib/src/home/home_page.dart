import 'package:flutter/material.dart';

import 'category_card.dart';
import 'day_card.dart';
import 'holdings_card.dart';
import 'home_data.dart';
import 'month_card.dart';

/// The first screen: this month, investments and the day's entries. Each
/// card shows a little and opens up when tapped.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MonthCard(data: data),
                const SizedBox(height: 12),
                CategoryCard(data: data),
                const SizedBox(height: 12),
                HoldingsCard(data: data),
                const SizedBox(height: 12),
                DayCard(data: data),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
