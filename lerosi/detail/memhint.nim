# MIT License
# 
# Copyright (c) 2018 WINDGO, Inc.
# Low Energy Retrieval of Source Information
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# All code below except for modifications by WINDGO, Inc. is copyright
# the Arraymancer contributors under the Apache 2.0 License.

# There are plans to expand upon this for the Raspberrry Pi 3 and Zero models
# and share the RPi version back to arraymancer.

template use_mem_hints*(): untyped =
  when not defined(js):
    {.pragma: align64, codegenDecl: "$# $# __attribute__((aligned(64)))".}
    {.pragma: restrict, codegenDecl: "$# __restrict__ $#".}
  else:
    {.pragma: align64.}
    {.pragma: restrict.}

when not defined(js):
  proc builtin_assume_aligned[T](data: ptr T, n: csize): ptr T
    {.importc: "__builtin_assume_aligned",noDecl.}

when defined(cpp):
  proc static_cast[T](input: T): T
    {.importcpp: "static_cast<'0>(@)".}

# Because of the use with arraymancer's own templates, this must not be renamed
# for the forseeable future.
template assume_aligned*[T](data: ptr T, n: csize): ptr T =
  when defined(cpp): # builtin_assume_aligned returns void pointers, this does not compile in C++, they must all be typed
    static_cast builtin_assume_aligned(data, n)
  elif defined(js):
    data
  else:
    builtin_assume_aligned(data, n)


