import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/look/glyphs.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';

/// The gold of the recovery code, on 安全 and wherever a new one is shown.
const recoveryHue = Shade(0xFFC9A34A, 0xFFDDBE73);

/// Shows a new recovery code once, in large groups of four with 複製
/// beside 存好了; it is the only way in without the password.
Future<void> showRecoveryCode(
  BuildContext context,
  String code, {
  String why = '忘記密碼時，只有它能打開帳本',
}) {
  return showPanel<void>(
    context,
    (_) => _RecoveryPanel(code: code, why: why),
    dismissible: false,
  );
}

class _RecoveryPanel extends StatefulWidget {
  const _RecoveryPanel({required this.code, required this.why});

  final String code;
  final String why;

  @override
  State<_RecoveryPanel> createState() => _RecoveryPanelState();
}

class _RecoveryPanelState extends State<_RecoveryPanel> {
  var _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.code.split('-');
    const color = recoveryHue;
    return CenterPanel(
      glyph: Glyph.lifebuoy,
      color: color,
      title: '新的救援碼',
      detail: widget.why,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: '救援碼 ${widget.code}',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: tintOf(color, 0.22),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 18,
                runSpacing: 6,
                children: [
                  for (final group in groups)
                    Text(
                      group,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: deepOf(color),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('抄下來或複製存好，只會顯示這一次。', style: mutedSmall),
        ],
      ),
      actions: [
        PanelButton(_copied ? '✓ 已複製' : '複製', onTap: _copy),
        PanelButton(
          '存好了',
          color: color,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
