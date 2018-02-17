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

import system, macros, arraymancer
import ../am # Cyclic reference by design
import ../../spaceconf

template call_permute_left(dat: untyped, arity: int): untyped =
  when compileOption("boundChecks"):
    assert(0 < arity and arity <= 7)
  case arity
  of 1: dat
  of 2: dat.permute(1, 0)
  of 3: dat.permute(1, 2, 0)
  of 4: dat.permute(1, 2, 3, 0)
  of 5: dat.permute(1, 2, 3, 4, 0)
  of 6: dat.permute(1, 2, 3, 4, 5, 0)
  of 7: dat.permute(1, 2, 3, 4, 5, 6, 0)
  else: dat

template call_permute_right(dat: untyped, arity: int): untyped =
  when compileOption("boundChecks"):
    assert(0 < arity and arity <= 7)
  case arity
  of 1: dat
  of 2: dat.permute(1, 0)
  of 3: dat.permute(2, 0, 1)
  of 4: dat.permute(3, 0, 1, 2)
  of 5: dat.permute(4, 0, 1, 2, 3)
  of 6: dat.permute(5, 0, 1, 2, 3, 4)
  of 7: dat.permute(6, 0, 1, 2, 3, 4, 5)
  else: dat

template do_permute(pmut: untyped; b: typed): untyped =
  let d = b.backend_data
  b.backend_data(pmut(d, d.shape.len))
  b

proc backend_rotate_planar*[B](b: var B): var B {.discardable.} =
  do_permute(call_permute_right, b)
  
proc backend_rotate_planar*[B](b: B): B =
  result = b
  result = do_permute(call_permute_right, result)

proc backend_rotate_interleaved*[B](b: var B): var B {.discardable.} =
  do_permute(call_permute_left, b)

proc backend_rotate_interleaved*[B](b: B): B =
  result = b
  result = do_permute(call_permute_left, result)

proc backend_rotate*[B](b: var B, order: DataOrder): var B {.inline, discardable.} =
  case order:
  of DataPlanar:
    result = backend_rotate_planar(b)
  of DataInterleaved:
    result = backend_rotate_interleaved(b)

proc backend_rotate*[B](b: B, order: DataOrder): B {.inline.} =
  case order:
  of DataPlanar:
    result = backend_rotate_planar(b)
  of DataInterleaved:
    result = backend_rotate_interleaved(b)

