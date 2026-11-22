import 'dart:convert';

import '../record_version.dart';

/// Rows' bodies as JSON, one by one: a body that is not JSON is noted by
/// its place, not thrown, so the others are still read.
final class DecodedRows {
  DecodedRows._();

  /// Each body's JSON, by place; null for one that is not JSON.
  final values = <Object?>[];

  /// Why each body that is not JSON is not, by place.
  final failures = <int, String>{};

  /// Notes that the body at [index] is not JSON, for [error].
  void record(int index, FormatException error) =>
      failures[index] = error.message;
}

/// Each of [bodies] decoded as JSON ([DecodedRows]).
DecodedRows decodeBodies(List<String> bodies) {
  final decoded = DecodedRows._();
  for (final (i, body) in bodies.indexed) {
    try {
      decoded.values.add(jsonDecode(body));
    } on FormatException catch (error) {
      decoded.values.add(null);
      decoded.record(i, error);
    }
  }
  return decoded;
}

/// The record [body] holds, when this version can read it as one: null
/// for a body that is not a JSON object, or that a later version wrote.
Map<String, Object?>? readableRecord(String body) {
  final json = decodeBodies([body]).values.single;
  if (json is! Map<String, Object?>) return null;
  final version = versionOf(json);
  return version == null || version > recordVersion ? null : json;
}
