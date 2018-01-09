import system, sequtils, strutils, math, algorithm
import haas, arraymancer, arraymancer_vision

export haas, arraymancer

# Fill this out with your own bootstrapping hooks. staticExec may be used
# to conditionally run blocking scripts at compile time to prepare the source
# tree before all sources are read by the compiler.
#when defined(haas_bootstrap):
#  static:
#    # Ensure that all included files from detail/ag exist in the tree.
#    # This executes a script which touches all such include files.
#    #echo(staticExec "cd haas/ag && sh ensure.sh")

proc load_image*(filename: string, channels: int = 0): Tensor[uint8] =
  load(filename, channels) # Simple forwarding at this point.

proc load_image*(data: openarray[uint8], channels: int = 0): Tensor[uint8] =
  loadFromMemory(filename, channels) # Simple forwarding at this point.

