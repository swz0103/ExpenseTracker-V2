import 'package:flutter/material.dart';

import 'theme.dart';

/// A field for a password, a recovery code or a backup's path: no
/// autocorrect and no suggestions, so the keyboard neither changes what
/// is typed nor learns it. The words are hidden unless [hidden] is off,
/// as for a recovery code, which is read off paper.
class PasswordField extends StatelessWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.hint,
    this.hidden = true,
    this.onSubmitted,
    this.boxed = false,
    this.plain = false,
  });

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
  Widget build(BuildContext context) {
    final submit = onSubmitted;
    return TextField(
      controller: controller,
      obscureText: hidden,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: submit == null ? null : (_) => submit(),
      style: plain ? const TextStyle(fontSize: 18, letterSpacing: 2) : null,
      decoration: plain
          ? InputDecoration.collapsed(hintText: hint).copyWith(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              isDense: true,
            )
          : boxed
          ? InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: Hue.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            )
          : InputDecoration(hintText: hint),
    );
  }
}
