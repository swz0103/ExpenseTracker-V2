import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/design_system/dialogs.dart';
import '../../../../core/messages/key_failures.dart';
import '../../../../core/messages/key_messages.dart';
import '../../../../core/platform/startup_state.dart';

/// The ledgers kept on this phone before an earlier restore, each named
/// by when its backup was taken; null when none is chosen.
Future<File?> chooseKeptLedger(
  BuildContext context,
  List<(File, BackupFacts?)> kept,
) async {
  final chosen = await chooseOne(
    context,
    kept,
    title: KeyWords.keptLedgers,
    label: (k) => keptLabel(
      k.$2,
      broughtBack: k.$1.uri.pathSegments.last.startsWith('brought-back'),
    ),
  );
  return chosen?.$1;
}
