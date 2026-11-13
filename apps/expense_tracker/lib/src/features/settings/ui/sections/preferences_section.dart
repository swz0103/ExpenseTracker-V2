import 'package:flutter/material.dart';

import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../overview/ui/overview_editor.dart';
import '../../../overview/ui/widget_face.dart';
import '../../../../core/preferences.dart';
import '../settings_hue.dart';

/// 外觀與操作: four cards: light or dark, the small vibrations, what the
/// home-screen widget shows, and the overview's blocks.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key, required this.preferences});

  final Preferences preferences;

  /// Light, dark, or as the phone is, each as a small picture of a page.
  void _pickAppearance(BuildContext context) {
    showCenterPanel(
      context,
      glyph: Glyph.moon,
      color: SettingsHue.appearance,
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
              if (i > 0) const SizedBox(width: 10),
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

  /// What the home-screen widget 本月概況 shows, each choice as it looks.
  void _pickWidget(BuildContext context) {
    showCenterPanel(
      context,
      glyph: Glyph.overview,
      color: SettingsHue.widget,
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
        color: SettingsHue.appearance,
        title: '外觀',
        detail: preferences.appearance.label,
        onTap: () => _pickAppearance(context),
      ),
      SettingCard(
        glyph: Glyph.vibrate,
        color: SettingsHue.haptics,
        title: '震動',
        detail: '按下去會輕震',
        value: preferences.haptics,
        onChanged: (on) => preferences.update(haptics: on),
        onTap: () => preferences.update(haptics: !preferences.haptics),
      ),
      SettingCard(
        glyph: Glyph.overview,
        color: SettingsHue.widget,
        title: '桌面小工具',
        detail: preferences.widgetFigures.label,
        onTap: () => _pickWidget(context),
      ),
      SettingCard(
        glyph: Glyph.list,
        color: SettingsHue.sections,
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

  @override
  Widget build(BuildContext context) {
    const light = (Color(0xFFF3F4F1), Color(0xFFDDE3E2), Color(0xFFC9D0CE));
    const dark = (Color(0xFF2A3237), Color(0xFF3E4A50), Color(0xFF55636A));
    Widget page((Color, Color, Color) c) => Container(
      color: c.$1,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 14,
            decoration: BoxDecoration(
              color: c.$2,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(height: 8),
          FractionallySizedBox(
            widthFactor: 0.55,
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: c.$3,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
    final picture = switch (look) {
      Appearance.light => page(light),
      Appearance.dark => page(dark),
      Appearance.system => Row(
        children: [
          Expanded(child: page(light)),
          Expanded(child: page(dark)),
        ],
      ),
    };
    const color = SettingsHue.appearance;
    return Semantics(
      button: true,
      selected: chosen,
      label: look.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 0.9,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: chosen ? color : Hue.line,
                    width: chosen ? 3 : 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    picture,
                    if (chosen)
                      const Positioned(
                        right: 6,
                        bottom: 6,
                        child: IgnorePointer(
                          child: TickSwitch(
                            value: true,
                            color: color,
                            label: '',
                            onChanged: null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              look.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: chosen ? deepOf(color) : Hue.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
          const SizedBox(height: 10),
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
    const color = SettingsHue.widget;
    return Semantics(
      button: true,
      selected: chosen,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: tintOf(color, chosen ? 0.2 : 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: chosen ? color : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      IgnorePointer(child: child),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
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
