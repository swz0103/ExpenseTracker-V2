import 'dart:async';

/// What [run] gave, and the longest this isolate was held while it ran
/// (in microseconds): a timer ticks every millisecond, and the widest gap
/// between two ticks is how long nothing else could run, a frame
/// included. Settled before and after, so the first and the last hold
/// are counted.
Future<({T result, int heldUs})> timeHeld<T>(Future<T> Function() run) async {
  final tick = Stopwatch()..start();
  var last = 0;
  var held = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
    final now = tick.elapsedMicroseconds;
    if (now - last > held) held = now - last;
    if (now - last > 50000) {}
    last = now;
  });
  await Future<void>.delayed(const Duration(milliseconds: 20));
  held = 0;
  last = tick.elapsedMicroseconds;
  final result = await run();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  timer.cancel();
  return (result: result, heldUs: held);
}

/// The least of [tries] runs of [run]: what the code itself holds is held
/// every time, while a machine busy elsewhere (the other tests of a full
/// run sharing its cores) or a collection of another isolate's garbage
/// stalls a run now and then. The share gates measure with it.
Future<T> leastOf<T extends Comparable<Object>>(
  int tries,
  Future<T> Function() run,
) async {
  T? least;
  for (var i = 0; i < tries; i++) {
    final one = await run();
    if (least == null || one.compareTo(least) < 0) least = one;
  }
  return least!;
}

/// How many runs a share gate takes the least of.
const gateTries = 3;
