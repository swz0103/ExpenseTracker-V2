/// How many seeds each seeded fuzz test runs: a bounded few by default,
/// more with `--dart-define=FUZZ_SEEDS=200` (each seed is one test, so a
/// failure names the seed to replay).
const fuzzSeeds = int.fromEnvironment('FUZZ_SEEDS', defaultValue: 10);
