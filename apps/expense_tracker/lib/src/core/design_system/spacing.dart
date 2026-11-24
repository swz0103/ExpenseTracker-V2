/// The gaps and padding the app lays things out with: a 4 dp grid, as
/// Material 3 lays out, with 2 dp kept for hairline gaps. Named by how
/// many 4 dp steps they are, as Tailwind's spacing scale is (s4 is 16 dp).
/// Pages pick a step, never a number.
abstract final class Space {
  static const half = 2.0;
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s10 = 40.0;
  static const s12 = 48.0;
  static const s14 = 56.0;
  static const s16 = 64.0;
  static const s18 = 72.0;
  static const s20 = 80.0;
  static const s24 = 96.0;

  /// The least a thing to tap is, high and wide (Android's 48 dp). The one
  /// place the number is written; controls take it from here.
  static const target = 48.0;
}
