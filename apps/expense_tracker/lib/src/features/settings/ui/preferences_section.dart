import 'package:flutter/material.dart';

import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../overview/forms/overview_editor.dart';
import '../../overview/forms/widget_face.dart';
import '../../../core/platform/preferences.dart';
import '../../../core/design_system/settings_colors.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';

/// 外觀與操作: four cards: light or dark, the small vibrations (關, 輕 or
/// 標準), what the
/// home-screen widget shows, and the overview's blocks.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key, required this.preferences});

  final Preferences preferences;

  /// Light, dark, or as the phone is, each as a small picture of a page.
  void _pickAppearance(BuildContext context) {
    showCenterPanel(
      context,
      glyph: Glyph.moon,
      color: SettingsColors.appearance,
      title: '外觀',
      body: (context) => ListenableBuilder(
        listenable: preferences,
        builder: (context, _) => Row(
          children: [
            for (final (i, a) in const [
              Appearance.light,
              Appearance.dark,
              Appearance.system,
            ].indexed) ...[
              if (i > 0) const SizedBox(width: Space.s2),
              Expanded(
                child: _LookChoice(
                  look: a,
                  chosen: a == preferences.appearance,
                  onTap: () => preferences.update(appearance: a),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 關, 輕 or 標準: how heavy the taps felt in the hand are.
  void _pickVibration(BuildContext context) {
    showCenterPanel(
      context,
      glyph: Glyph.vibrate,
      color: SettingsColors.haptics,
      title: '震動',
      detail: '標準比輕重一級',
      body: (context) => ListenableBuilder(
        listenable: preferences,
        builder: (context, _) => Segments(
          labels: [for (final v in Vibration.values) v.label],
          selected: preferences.vibration.index,
          selectedColor: SettingsColors.haptics,
          onChanged: (i) => preferences.update(vibration: Vibration.values[i]),
        ),
      ),
    );
  }

  /// What the home-screen widget 本月概況 shows, each choice as it looks.
  void _pickWidget(BuildContext context) {
    showCenterPanel(
      context,
      glyph: Glyph.overview,
      color: SettingsColors.widget,
      title: '桌面小工具',
      detail: '桌面上任何人都看得到',
      body: (context) => ListenableBuilder(
        listenable: preferences,
        builder: (context, _) => _WidgetChoices(
          current: preferences.widgetFigures,
          onPick: (f) => preferences.update(widgetFigures: f),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CardGrid([
      SettingCard(
        glyph: Glyph.moon,
        color: SettingsColors.appearance,
        title: '外觀',
        detail: preferences.appearance.label,
        onTap: () => _pickAppearance(context),
      ),
      SettingCard(
        glyph: Glyph.vibrate,
        color: SettingsColors.haptics,
        title: '震動',
        detail: preferences.vibration.label,
        value: preferences.vibration != Vibration.off,
        // The tick turns it off, or back on as 標準; the card offers all
        // three.
        onChanged: (on) => preferences.update(
          vibration: on ? Vibration.standard : Vibration.off,
        ),
        onTap: () => _pickVibration(context),
      ),
      SettingCard(
        glyph: Glyph.overview,
        color: SettingsColors.widget,
        title: '桌面小工具',
        detail: preferences.widgetFigures.label,
        onTap: () => _pickWidget(context),
      ),
      SettingCard(
        glyph: Glyph.list,
        color: SettingsColors.sections,
        title: '總覽區塊',
        detail: '排序、隱藏',
        onTap: () => editOverview(context, preferences),
      ),
    ]);
  }
}

/// One of 淺色, 深色, 跟著手機 as a small page drawn in its colours, the
/// chosen one framed and ticked.
class _LookChoice extends StatelessWidget {
  const _LookChoice({
    required this.look,
    required this.chosen,
    required this.onTap,
  });

  final Appearance look;
  final bool chosen;
  final VoidCallback onTap;

  static const _color = SettingsColors.appearance;

  @override
  Widget build(BuildContext context) {
    return ReadAsButton(
      selected: chosen,
      label: look.label,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            AspectRatio(aspectRatio: 0.9, child: _frame(_picture())),
            const SizedBox(height: Space.s2),
            OneLine(
              look.label,
              alignment: Alignment.center,
              style: TextStyle(
                fontSize: TextSize.body,
                fontWeight: FontWeight.w700,
                color: chosen ? deepOf(_color) : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [picture] in a rounded frame, thick and ticked when chosen, faded
  /// when not.
  Widget _frame(Widget picture) {
    // The frame is drawn over the picture: under it, the picture's
    // corners covered the frame's.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.large),
        border: Border.all(
          color: chosen ? _color : AppColors.line,
          width: chosen ? 3 : 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The ones not chosen are faded, so the chosen one stands out.
          Opacity(opacity: chosen ? 1 : 0.5, child: picture),
          if (chosen)
            const Positioned(
              right: 6,
              bottom: 6,
              child: IgnorePointer(
                child: TickSwitch(
                  value: true,
                  color: _color,
                  label: '',
                  onChanged: null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The look as a small page in its theme's colours; 跟著手機 as both
  /// side by side.
  Widget _picture() {
    // Each theme's own paper, surface and line, whichever is showing.
    final light = (
      Color(AppColors.paper.light),
      Color(AppColors.surface.light),
      Color(AppColors.faint.light),
    );
    final dark = (
      Color(AppColors.paper.darkValue),
      Color(AppColors.surface.darkValue),
      Color(AppColors.line.darkValue),
    );
    return switch (look) {
      Appearance.light => _page(light),
      Appearance.dark => _page(dark),
      Appearance.system => Row(
        children: [
          Expanded(child: _page(light)),
          Expanded(child: _page(dark)),
        ],
      ),
    };
  }

  /// A small page in [c]'s paper, surface and line: a bar and a short
  /// line under it.
  static Widget _page((Color, Color, Color) c) => Container(
    color: c.$1,
    padding: const EdgeInsets.all(Space.s2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 14,
          decoration: BoxDecoration(
            color: c.$2,
            borderRadius: BorderRadius.circular(Radii.extraSmall),
          ),
        ),
        const SizedBox(height: Space.s2),
        FractionallySizedBox(
          widthFactor: 0.55,
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: c.$3,
              borderRadius: BorderRadius.circular(Radii.extraSmall),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The three choices for 本月概況, each drawn one row high with made-up
/// figures, the chosen one framed and ticked.
class _WidgetChoices extends StatelessWidget {
  const _WidgetChoices({required this.current, required this.onPick});

  final WidgetFigures current;
  final ValueChanged<WidgetFigures> onPick;

  static const _samples = <WidgetFigures, Map<String, Object?>?>{
    WidgetFigures.amounts: {
      'shortLabel': '10 月預算剩',
      'shortFigure': '7,660',
      'progress': 62,
      'pace': 77,
    },
    WidgetFigures.percent: {
      'shortLabel': '10 月預算',
      'shortFigure': '已用 62%',
      'progress': 62,
      'pace': 77,
    },
    WidgetFigures.off: null,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in _samples.keys) ...[
          _WidgetChoice(
            label: f.label,
            chosen: f == current,
            onTap: () => onPick(f),
            child: WidgetRow(snapshot: _samples[f]),
          ),
          const SizedBox(height: Space.s2),
        ],
      ],
    );
  }
}

class _WidgetChoice extends StatelessWidget {
  const _WidgetChoice({
    required this.label,
    required this.chosen,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool chosen;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const color = SettingsColors.widget;
    return ReadAsButton(
      selected: chosen,
      label: label,
      onTap: onTap,
      child: Material(
        color: tintOf(color, chosen ? 0.2 : 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.large),
          side: BorderSide(
            color: chosen ? color : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s4,
              Space.s2,
              Space.s2,
              Space.s3,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: TextSize.body,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: Space.s2),
                      IgnorePointer(child: child),
                    ],
                  ),
                ),
                const SizedBox(width: Space.s2),
                IgnorePointer(
                  child: TickSwitch(
                    value: chosen,
                    color: color,
                    label: label,
                    onChanged: null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
