/// What a refresh of closes and rates says when it did not take all of
/// them: the stocks [missed], with no close found, and the stocks and
/// currencies [doubted], fetched too far from the figure kept (D95),
/// which stays. Null when nothing is to be said.
String? marketProblem({
  required List<String> missed,
  required List<String> doubted,
}) {
  final said = [
    if (missed.isNotEmpty) '${missed.join('、')} 抓不到收盤價',
    if (doubted.isNotEmpty) '${doubted.join('、')} 的行情與前次相差太大，先沿用前次的數字',
  ];
  return said.isEmpty ? null : said.join('；');
}
