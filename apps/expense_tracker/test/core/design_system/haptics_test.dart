import 'package:expense_tracker/src/core/design_system/haptics.dart';
import 'package:flutter_test/flutter_test.dart';

/// 輕 plays each tap a step lighter than 標準; 關 plays none.
void main() {
  late List<HapticKind> played;

  setUp(() {
    played = [];
    Haptics.perform = played.add;
  });
  tearDown(() {
    Haptics.on = true;
    Haptics.strong = true;
  });

  void all() {
    Haptics.selection();
    Haptics.light();
    Haptics.medium();
  }

  test('標準', () {
    all();
    expect(played, [HapticKind.click, HapticKind.click, HapticKind.heavy]);
  });

  test('輕', () {
    Haptics.strong = false;
    all();
    expect(played, [HapticKind.tick, HapticKind.tick, HapticKind.click]);
  });

  test('關', () {
    Haptics.on = false;
    all();
    expect(played, isEmpty);
  });
}
