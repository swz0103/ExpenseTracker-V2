/// Why removing an account also empties [count] entries of the trash that
/// still name it (D78); null when none do.
String? trashedNamingNote(int count) =>
    count == 0 ? null : '「最近刪除」裡還有 $count 筆用到它的紀錄，會一併永久清除，無法再放回。';
