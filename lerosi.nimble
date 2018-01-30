# Package

version       = "0.1.0"
author        = "William Whitacre"
description   = "Low Energy Reconstruction of Source Information"
license       = "MIT"

# Dependencies

requires "nim >= 0.17.2"
requires "arraymancer >= 0.2.90"
requires "imghdr >= 1.0"
requires "nimpng >= 0.2.0"

skipDirs = @["test"]

task tests, "Running all tests":
  exec "echo 'test/results/'`date +%Y%m%d-%H.%M.%S`'.test.txt' > tmp_filename"
  exec "cd test && nim c --stackTrace:on test_all"
  exec "mkdir -p test/results"
  exec "test/test_all > `cat tmp_filename` || echo 'Test(s) failed, see results!'"
  exec "echo 'Tests complete, see '`cat tmp_filename`' for full results. Generating PDF...'"
  exec "wgmkpdf 'LERoSI Module Unit Tests' \"`cat tmp_filename`\"  \"`cat tmp_filename`.pdf\" || echo 'Failed to generate PDF from test results!'"
  echo "done."
  exec "xdg-open \"`cat tmp_filename`.pdf\""
  exec "rm tmp_filename"

task bench, "Running benchmarks":
  exec "echo 'test/results/'`date +%Y%m%d-%H.%M.%S`'.benchmark.txt' > tmp_filename"
  exec "nim c -d:release test/bench_all"
  exec "mkdir -p test/results"
  exec "test/bench_all > `cat tmp_filename`"
  echo "Benchmark Results:"
  echo "============================================================"
  exec "cat `cat tmp_filename`"
  echo ""
  echo "Generating PDF..."
  exec "wgmkpdf 'LERoSI Module Benchmark Results' \"`cat tmp_filename`\"  \"`cat tmp_filename`.pdf\" || echo 'Failed to generate PDF from benchmark results!'"
  echo "done."
  exec "xdg-open \"`cat tmp_filename`.pdf\""
  exec "rm tmp_filename"

before install:
  echo "Nothing to do before install, proceeding."

