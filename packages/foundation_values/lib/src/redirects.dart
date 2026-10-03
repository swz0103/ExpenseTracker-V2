import 'identity.dart';

/// Follows every redirect to the entry it ends at, for catalogs whose
/// merged entries point at their replacement (health check G1-12).
///
/// [replacements] maps each id to the id that replaced it, or to null for
/// a live entry; every target must be a key. Runs in O(n) even for a long,
/// untrusted history. Returns null when the redirects form a cycle.
Map<PublicId, PublicId>? resolveRedirects(
  Map<PublicId, PublicId?> replacements,
) {
  final canonical = <PublicId, PublicId>{};
  for (final id in replacements.keys) {
    if (canonical.containsKey(id)) continue;
    final path = <PublicId>{};
    var cursor = id;
    while (!canonical.containsKey(cursor)) {
      if (!path.add(cursor)) return null;
      final next = replacements[cursor];
      if (next == null) {
        canonical[cursor] = cursor;
        break;
      }
      cursor = next;
    }
    final resolved = canonical[cursor]!;
    for (final member in path) {
      canonical[member] = resolved;
    }
  }
  return canonical;
}
