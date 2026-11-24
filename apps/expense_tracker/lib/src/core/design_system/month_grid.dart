import 'package:flutter/material.dart';

import 'spacing.dart';
import 'theme.dart';
import '../../../design_system/display/date.dart';

import 'package:core/time/utc_days.dart';

/// A month as the app's calendars draw it: the days of the week across,
/// from Sunday, then a row a week. Every calendar of the app is one, so
/// they read alike: the days of the months before and after are left
/// blank, and [day] draws only the month's own, numbered from 1.
///
/// [sixWeeks] keeps six rows whatever the month, as a panel does, so its
/// height does not jump from month to month; a page draws only the weeks
/// the month has.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.year,
    required this.month,
    required this.day,
    this.sixWeeks = true,
    this.weekdayStyle = mutedSmall,
    this.top = false,
    this.blank = 0,
    this.gap = Space.s1,
  });

  final int year;

  /// From 1, as [DateTime] counts them.
  final int month;
  final Widget Function(int day) day;
  final bool sixWeeks;
  final TextStyle weekdayStyle;

  /// Lines a week's days up at the top, for days of different heights
  /// (such as 到期 under a day due); centred otherwise.
  final bool top;

  /// How tall a blank day is: as tall as a day, where a whole week may be
  /// blank (the sixth row of a short month).
  final double blank;

  /// Between the days of the week and the first week.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final lead = weekdayIndex(DateTime.utc(year, month));
    final days = monthEnd(year, month).day;
    final weeks = sixWeeks ? 6 : ((lead + days) / 7).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final name in weekdayNames)
              Expanded(
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: weekdayStyle,
                ),
              ),
          ],
        ),
        SizedBox(height: gap),
        for (var week = 0; week < weeks; week++)
          Row(
            crossAxisAlignment: top
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              for (var d = 0; d < 7; d++)
                Expanded(
                  child: switch (week * 7 + d - lead + 1) {
                    final n when n >= 1 && n <= days => day(n),
                    _ => SizedBox(height: blank),
                  },
                ),
            ],
          ),
      ],
    );
  }
}
