import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';

Future<void> main(List<String> args) async {
  if (args.length != 4 || !['password', 'recovery'].contains(args[0]))
    throw ArgumentError('Expected mode and three fixture file paths.');
  final envelope = await File(args[1]).readAsString();
  final credential = await File(args[2]).readAsString();
  final codec = EnvelopeCodec();
  final bytes = args[0] == 'password'
      ? await codec.openWithPassword(envelope, credential)
      : await codec.openWithRecovery(envelope, credential);
  // Test fixture destination only. Production restoration needs a validated staged swap.
  await File(args[3]).writeAsBytes(bytes, flush: true);
}
