import 'package:expense_tracker/src/features/reminders/model/reminder_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one table of the reminders' kinds, channels and times.
void main() {
  test('each kind has its channel and grace window', () {
    expect(
      [
        for (final k in ReminderKind.values)
          (k.name, k.channel.name, k.grace, k.lateWhenPlanned),
      ],
      [
        ('due', 'due', const Duration(days: 7), true),
        ('dueAhead', 'due', const Duration(hours: 12), false),
        ('nudge', 'nudge', const Duration(hours: 3), false),
        ('budget', 'budget', Duration.zero, false),
        ('test', 'due', Duration.zero, false),
      ],
    );
  });

  test('AND-11: a channel for each kind the person may silence alone, by '
      'the names the phone\'s settings show', () {
    expect(
      [for (final c in ReminderChannel.values) (c.name, c.title, c.about)],
      [
        ('due', '到期提醒', '定期扣款、卡費到期'),
        ('nudge', '每日記帳提醒', '當天還沒記帳時提醒'),
        ('budget', '預算提醒', '預算用到警示比例或超支時'),
      ],
    );
    expect(ReminderChannel.retired, ['reminders']);
  });

  test('the times', () {
    expect(ReminderTiming.horizonDays, 62);
    expect(ReminderTiming.most, 160);
    expect(ReminderTiming.dueHour, 9);
    expect(ReminderTiming.cardWarnDays, 2);
    expect(ReminderTiming.inexactLateness, const Duration(hours: 1));
  });
}
