import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/messages/key_failures.dart';
import '../../../../core/messages/key_messages.dart';
import '../../../../core/platform/startup.dart' show BackupFacts;

/// A sheet of [items] to choose one from, each named by [label] (and
/// [detail] under it), below [heading] when given; null when none is
/// chosen.
Future<T?> chooseOne<T>(
  BuildContext context,
  List<T> items, {
  required String Function(T item) label,
  String Function(T item)? detail,
  String? heading,
}) => showModalBottomSheet<T>(
  context: context,
  builder: (context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      children: [
        if (heading != null) ListTile(title: Text(heading)),
        for (final item in items)
          ListTile(
            title: Text(label(item)),
            subtitle: detail == null ? null : Text(detail(item)),
            onTap: () => Navigator.of(context).pop(item),
          ),
      ],
    ),
  ),
);

/// The ledgers kept on this phone before an earlier restore, each named
/// by when its backup was taken; null when none is chosen.
Future<File?> chooseKeptLedger(
  BuildContext context,
  List<(File, BackupFacts?)> kept,
) async {
  final chosen = await chooseOne(
    context,
    kept,
    heading: KeyWords.keptLedgers,
    label: (k) => keptLabel(
      k.$2,
      broughtBack: k.$1.uri.pathSegments.last.startsWith('brought-back'),
    ),
  );
  return chosen?.$1;
}
