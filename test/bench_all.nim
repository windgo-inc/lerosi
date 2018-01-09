import nimbones

bench(speedTestSomething, m):
  var x = 0
  for i in 0..m:
    inc x

  doNotOptimizeAway(x)


runBenchmarks()

