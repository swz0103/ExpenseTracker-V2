import 'package:flutter/material.dart';

import '../../look/app_mark.dart';
import '../../look/theme.dart';
import 'lock_parts.dart';

/// The first screen of a new ledger when it did not start by itself: one
/// tap starts it without a password, or a password is set first, or a
/// backup is restored.
class WelcomeView extends StatelessWidget {
  const WelcomeView({
    super.key,
    required this.busy,
    required this.onStart,
    required this.onWithPassword,
    required this.onRestore,
    this.problem,
  });

  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onWithPassword;
  final VoidCallback onRestore;

  /// Why the ledger did not start; empty when the person came back here.
  final String? problem;

  @override
  Widget build(BuildContext context) {
    return LockPage(
      children: [
        const Center(child: AppMark(size: 96)),
        const SizedBox(height: 20),
        const Text(
          '歡迎使用記帳本',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          '帳本只存在這台手機，並且加密保存。\n不用註冊，現在就能開始記帳。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Hue.muted, height: 1.5),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: busy ? null : onStart,
          style: FilledButton.styleFrom(
            backgroundColor: Hue.accent,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: busy
              ? const BusyMark()
              : const Text(
                  '開始記帳',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
        ),
        ProblemLine(problem),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: busy ? null : onWithPassword,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text('先設定密碼'),
        ),
        LockLink('從備份還原', onRestore, busy: busy),
        const SizedBox(height: 8),
        const Text(
          '之後可以在「設定」加上密碼或指紋解鎖。',
          textAlign: TextAlign.center,
          style: mutedSmall,
        ),
      ],
    );
  }
}
