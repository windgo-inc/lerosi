import system, sequtils, strutils, math, algorithm

# Fill this out with your own bootstrapping hooks. staticExec may be used
# to conditionally run blocking scripts at compile time to prepare the source
# tree before all sources are read by the compiler.
when defined(haas_bootstrap):
  static:
    # Ensure that all included files from detail/ag exist in the tree.
    # This executes a script which touches all such include files.
    #echo(staticExec "cd haas/ag && sh ensure.sh")

