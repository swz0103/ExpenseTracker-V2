import 'package:flutter/material.dart';

import 'controls.dart';
import 'glyphs.dart';
import 'theme.dart';
import 'shape.dart';
import 'spacing.dart';

/// How the keyboard treats a secret typed into any field: no
/// autocorrect, no suggestions, nothing learned into its personal
/// dictionary (which some keyboards sync to the cloud), and the password
/// layout. The one place these are set: [PasswordField] and the lock
/// screen's field both take them.
abstract final class SecretKeyboard {
  static const type = TextInputType.visiblePassword;
  static const autocorrect = false;
  static const suggestions = false;
  static const personalizedLearning = false;
}

/// A field for a password, a recovery code, a backup passphrase or a
/// backup's path, set up as [SecretKeyboard] says, so the keyboard neither
/// changes what is typed nor learns it. The words are hidden unless
/// [hidden] is off, as for a file path; hidden words have an eye at the
/// right to show them while typing, and to hide them again.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.hint,
    this.hidden = true,
    this.onSubmitted,
    this.boxed = false,
    this.plain = false,
    this.enabled = true,
  });

  /// Whether it can be typed into; not while the lock screen makes the
  /// person wait.
  final bool enabled;

  final TextEditingController controller;
  final String hint;
  final bool hidden;

  /// What the keyboard's done key does; none leaves it to move on.
  final VoidCallback? onSubmitted;

  /// A white rounded box, as on the lock screen's tinted block; otherwise
  /// the plain underlined field of a dialog.
  final bool boxed;

  /// No line and no box: the field sits in a tinted block of its own,
  /// as in the middle-of-the-screen panels.
  final bool plain;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  /// Shown by the eye, until it is pressed again.
  var _shown = false;

  @override
  Widget build(BuildContext context) {
    final hidden = widget.hidden;
    final plain = widget.plain;
    final boxed = widget.boxed;
    final hint = widget.hint;
    final submit = widget.onSubmitted;
    final field = TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: hidden && !_shown,
      autocorrect: SecretKeyboard.autocorrect,
      enableSuggestions: SecretKeyboard.suggestions,
      enableIMEPersonalizedLearning: SecretKeyboard.personalizedLearning,
      keyboardType: SecretKeyboard.type,
      onSubmitted: submit == null ? null : (_) => submit(),
      style: plain
          ? const TextStyle(fontSize: TextSize.heading, letterSpacing: 2)
          : null,
      decoration: plain
          ? InputDecoration.collapsed(hintText: hint).copyWith(
              contentPadding: const EdgeInsets.symmetric(vertical: Space.s2),
              isDense: true,
            )
          : boxed
          ? InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: AppColors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.medium),
                borderSide: BorderSide.none,
              ),
            )
          : InputDecoration(hintText: hint),
    );
    if (!hidden) return field;
    return Row(
      children: [
        Expanded(child: field),
        TapArea(
          label: _shown ? '隱藏密碼' : '顯示密碼',
          selected: _shown,
          onTap: () => setState(() => _shown = !_shown),
          child: SizedBox.square(
            dimension: 48,
            child: GlyphIcon(
              _shown ? Glyph.eyeOff : Glyph.eye,
              color: _shown ? AppColors.accent : AppColors.muted,
            ),
          ),
        ),
      ],
    );
  }
}
