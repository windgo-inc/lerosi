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
  exec "cd test && nim c --stackTrace:on --threads:on -d:lerosiUnitTests=true test_all"
  exec "mkdir -p test/results"
  # Pass the results through tty tee and then a color codes stripper that goes to the file.
  # Added utf-8 to ISO-8859-1 conversion for compatibility with enscript
  exec "test/test_all | tee /dev/tty | sed -r \"s/\\x1B\\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g\" | iconv -c -f utf-8 -t ISO-8859-1 > `cat tmp_filename` || echo 'Test(s) failed, see results!'"
  exec "echo 'Tests complete, see '`cat tmp_filename`' for full results. Generating PDF...'"
  exec "wgmkpdf 'LERoSI Module Unit Tests' \"`cat tmp_filename`\"  \"`cat tmp_filename`.pdf\" || echo 'Failed to generate PDF from test results!'"
  echo "done."
  # Open the results.
  exec "xdg-open \"`cat tmp_filename`.pdf\""
  exec "rm tmp_filename"

task bench, "Running benchmarks":
  exec "echo 'test/results/'`date +%Y%m%d-%H.%M.%S`'.benchmark.txt' > tmp_filename"
  exec "nim c -d:release --threads:on test/bench_all"
  exec "mkdir -p test/results"
  # Pass the results through tty tee and then a color codes stripper that goes to the file.
  # Added utf-8 to ISO-8859-1 conversion for compatibility with enscript
  exec "test/bench_all | tee /dev/tty | sed -r \"s/\\x1B\\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g\" | iconv -c -f utf-8 -t ISO-8859-1 > `cat tmp_filename`"
  echo "Benchmark Results:"
  echo "============================================================"
  exec "cat `cat tmp_filename`"
  echo ""
  echo "Generating PDF..."
  exec "wgmkpdf 'LERoSI Module Benchmark Results' \"`cat tmp_filename`\"  \"`cat tmp_filename`.pdf\" || echo 'Failed to generate PDF from benchmark results!'"
  echo "done."
  # Open the results.
  exec "xdg-open \"`cat tmp_filename`.pdf\""
  exec "rm tmp_filename"

before install:
  echo "Nothing to do before install, proceeding."

