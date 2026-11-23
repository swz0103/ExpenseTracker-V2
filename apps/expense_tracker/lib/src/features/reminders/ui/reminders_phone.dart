part of 'reminders_section.dart';

/// The strip under the cards: green with 試一則 when the phone allows
/// everything asked of it, gold naming what is still off with 去開.
class _PhoneStrip extends StatelessWidget {
  const _PhoneStrip({
    required this.status,
    required this.exact,
    required this.onTest,
    required this.onNotifications,
    required this.onExact,
    required this.onBattery,
  });

  final ReminderStatus status;
  final bool exact;
  final VoidCallback onTest;
  final VoidCallback onNotifications;
  final VoidCallback onExact;
  final VoidCallback onBattery;

  @override
  Widget build(BuildContext context) {
    final (String? missing, VoidCallback? fix) = !status.notifications
        ? ('通知權限沒開', onNotifications)
        : exact && !status.exact
        ? ('鬧鐘與提醒沒開', onExact)
        : !status.battery
        ? ('電池最佳化可能延後提醒', onBattery)
        : (null, null);
    final good = missing == null;
    final color = good ? AppColors.positive : SettingsColors.warning;
    return ColorCard(
      color: color,
      amount: 0.16,
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s2,
        Space.s2,
        Space.s2,
      ),
      child: Row(
        children: [
          GlyphIcon(
            good ? Glyph.check : Glyph.info,
            size: 20,
            color: deepOf(color),
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: OneLine(
              missing ?? '手機設定都好了',
              style: TextStyle(
                fontSize: TextSize.body,
                fontWeight: FontWeight.w700,
                color: deepOf(color),
              ),
            ),
          ),
          FilledButton(
            onPressed: good ? onTest : fix,
            style: solidButton(
              deepOf(color),
              minimumSize: Size(0, 48),
              radius: Radii.large,
            ),
            child: Text(
              good ? '試一則' : '去開',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small label over what it names, inside a panel.
class _Labelled extends StatelessWidget {
  const _Labelled(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: TextSize.body,
          fontWeight: FontWeight.w700,
          color: AppColors.muted,
        ),
      ),
      const SizedBox(height: Space.s2),
      child,
    ],
  );
}

/// A tinted block with a small line over a bold one: 11/15 over 健身房
/// 1,680.
class _Chip extends StatelessWidget {
  const _Chip({required this.color, required this.top, required this.bottom});

  final Color color;
  final String top;
  final String bottom;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s3, Space.s3),
    decoration: BoxDecoration(
      color: tintOf(color, 0.16),
      borderRadius: BorderRadius.circular(Radii.large),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OneLine(
          top,
          style: TextStyle(
            fontSize: TextSize.small,
            fontWeight: FontWeight.w700,
            color: deepOf(color),
          ),
        ),
        OneLine(
          bottom,
          style: TextStyle(
            fontSize: TextSize.body,
            fontWeight: FontWeight.w800,
            color: deepOf(color),
          ),
        ),
      ],
    ),
  );
}

/// A row with a name and a line under it on the left and a [TickSwitch]
/// on the right; a tinted block of its own unless [flat].
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.color,
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
    this.flat = false,
  });

  final Color color;
  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: EdgeInsets.symmetric(
        vertical: Space.s2,
        horizontal: flat ? 0 : Space.s4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: TextSize.body,
                    fontWeight: FontWeight.w700,
                    color: deepOf(color),
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: TextSize.small,
                    color: deepOf(color),
                  ),
                ),
              ],
            ),
          ),
          TickSwitch(
            value: value,
            color: color,
            label: title,
            onChanged: onChanged,
          ),
        ],
      ),
    );
    final whole = ToggleRow(
      value: value,
      onChanged: onChanged,
      label: title,
      radius: flat ? 0 : 18,
      child: row,
    );
    if (flat) return whole;
    return Container(
      decoration: BoxDecoration(
        color: tintOf(color, 0.16),
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      child: whole,
    );
  }
}

/// The Google 日曆 card's actions: linking a calendar, its details,
/// changing it and stopping the sync.
mixin _CalendarActions on State<RemindersSection> {
  /// What falls due in the ledger shown, read afresh each time.
  ReminderBook get _book;

  /// Links a calendar for the due dates, or changes it.
  Future<void> _linkCalendar(CalendarSync calendar) async {
    try {
      if (!await calendar.port.access()) {
        if (mounted) showNote(context, ReminderMessages.calendarNoAccess);
        return;
      }
      final choices = await calendar.port.calendars();
      if (!mounted) return;
      if (choices.isEmpty) {
        showNote(context, ReminderMessages.calendarNone);
        return;
      }
      final chosen = calendar.chosen?.$1;
      final picked = await showPanel<int>(
        context,
        (context) => CenterPanel(
          glyph: Glyph.calendar,
          color: SettingsColors.calendar,
          title: ReminderMessages.calendarPick,
          body: Column(
            children: [
              for (final c in choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s2),
                  child: ColorCard(
                    color: SettingsColors.calendar,
                    amount: c.id == chosen ? 0.32 : 0.14,
                    radius: Radii.large,
                    label: c.name,
                    onTap: () => Navigator.of(context).pop(c.id),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (c.account.isNotEmpty)
                                Text(c.account, style: mutedSmall),
                            ],
                          ),
                        ),
                        if (c.id == chosen)
                          const GlyphIcon(
                            Glyph.check,
                            size: 20,
                            color: SettingsColors.calendar,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            PanelButton(Words.cancel, onTap: () => Navigator.of(context).pop()),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      await calendar.choose(choices.firstWhere((c) => c.id == picked), _book);
      final written = await calendar.sync(_book);
      if (!mounted) return;
      setState(() {});
      showNote(
        context,
        written == null
            ? ReminderMessages.calendarNotSynced
            : ReminderMessages.calendarWritten(written),
      );
    } on Object catch (error) {
      ErrorLog.instance.record(ErrorSteps.calendarSync, error);
      if (mounted) {
        showNote(
          context,
          ReminderMessages.calendarUnreachable(describeProblem(error)),
        );
      }
    }
  }

  Future<void> _forgetCalendar(CalendarSync calendar) async {
    final cleared = await calendar.forget(_book);
    if (mounted) {
      showNote(
        context,
        cleared
            ? ReminderMessages.calendarCleared
            : ReminderMessages.calendarLeft,
      );
    }
    if (mounted) setState(() {});
  }

  void _calendarDetails(CalendarSync calendar) {
    const color = SettingsColors.calendar;
    showCenterPanel(
      context,
      glyph: Glyph.calendar,
      color: color,
      title: ReminderMessages.calendarTitle,
      detail: switch (calendar.chosen) {
        (_, final name)? => ReminderMessages.calendarSyncedTo(name),
        null => ReminderMessages.calendarAbout,
      },
      body: (context) => StatefulBuilder(
        builder: (context, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColorCard(
              color: color,
              amount: 0.16,
              radius: Radii.large,
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
              child: Column(
                children: [
                  _ToggleRow(
                    color: color,
                    flat: true,
                    title: ReminderMessages.calendarAmounts,
                    detail: calendar.amounts
                        ? ReminderMessages.calendarAmountsOn
                        : ReminderMessages.calendarAmountsOff,
                    value: calendar.amounts,
                    onChanged: (on) async {
                      await calendar.setAmounts(on, _book);
                      setState(() {});
                    },
                  ),
                  const Divider(height: 1),
                  _changeCalendar(context, calendar),
                ],
              ),
            ),
            const SizedBox(height: Space.s2),
            _stopSync(context, calendar),
          ],
        ),
      ),
    );
  }

  /// 換日曆 with the calendar now chosen: closes the [panel] and asks
  /// for another.
  Widget _changeCalendar(BuildContext panel, CalendarSync calendar) {
    const color = SettingsColors.calendar;
    return InkWell(
      onTap: () async {
        Navigator.of(panel).pop();
        await _linkCalendar(calendar);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            Text(
              ReminderMessages.calendarChange,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: deepOf(color),
              ),
            ),
            const Spacer(),
            Text(
              '${calendar.chosen?.$2 ?? ''} ›',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: deepOf(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 不再同步: closes the [panel] and stops writing to the calendar.
  Widget _stopSync(BuildContext panel, CalendarSync calendar) => TextButton(
    style: wordButton(AppColors.danger, minimumSize: Size(0, 48)),
    onPressed: () {
      Navigator.of(panel).pop();
      _forgetCalendar(calendar);
    },
    child: const Text(
      ReminderMessages.calendarStop,
      style: TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}
