import 'dart:convert';

/// A JSON object from outside the app, such as a settings file, Google
/// Drive's answer or the phone's, read field by field as the type each
/// should be. Two ways to read: [flag], [whole], [text] and the like
/// give null for a field missing or of another type, so one bad field
/// costs only itself; [need] refuses it with a [FormatException] that
/// names the field, for what cannot be read without it.
extension type const JsonFields(Map<String, Object?> json) {
  /// [text] as a JSON object; a [FormatException] when it is not one.
  static JsonFields decode(String text) => of(jsonDecode(text));

  /// A map the phone handed over, its keys words.
  static JsonFields from(Map<Object?, Object?> map) => JsonFields({
    for (final MapEntry(:key, :value) in map.entries)
      if (key case final String name) name: value,
  });

  /// [value] as a JSON object; a [FormatException] when it is not one.
  static JsonFields of(Object? value) => switch (value) {
    final Map<String, Object?> map => JsonFields(map),
    _ => throw FormatException('Expected an object, not $value'),
  };

  bool? flag(String key) => switch (json[key]) {
    final bool value => value,
    _ => null,
  };

  /// A whole number; JSON may write one as `3.0`.
  int? whole(String key) => switch (json[key]) {
    final int value => value,
    final double value when value == value.roundToDouble() => value.toInt(),
    _ => null,
  };

  /// The whole numbers of a list, leaving out what is not one.
  List<int>? wholes(String key) => switch (json[key]) {
    final List<Object?> list => [
      for (final item in list)
        if (item is int) item,
    ],
    _ => null,
  };

  String? text(String key) => switch (json[key]) {
    final String value => value,
    _ => null,
  };

  /// The words of a list, leaving out what is not words.
  List<String>? texts(String key) => switch (json[key]) {
    final List<Object?> list => [
      for (final item in list)
        if (item is String) item,
    ],
    _ => null,
  };

  JsonFields? object(String key) => switch (json[key]) {
    final Map<String, Object?> map => JsonFields(map),
    _ => null,
  };

  /// The objects of a list, leaving out what is not one.
  List<JsonFields>? objects(String key) => switch (json[key]) {
    final List<Object?> list => [
      for (final item in list)
        if (item is Map<String, Object?>) JsonFields(item),
    ],
    _ => null,
  };

  /// Field [key] as a [T], or null when it is not there; a
  /// [FormatException] naming it when it is of another type. For a record
  /// that must not lose a field quietly.
  T? optional<T extends Object>(String key) => switch (json[key]) {
    null => null,
    final T value => value,
    final other => throw FormatException(
      '$key: expected $T, found ${other.runtimeType}',
    ),
  };

  /// Field [key] as a [T]; a [FormatException] naming it when it is
  /// missing or of another type.
  T need<T extends Object>(String key) => switch (json[key]) {
    final T value => value,
    final other => throw FormatException(
      '$key: expected $T, found ${other?.runtimeType ?? 'nothing'}',
    ),
  };
}
