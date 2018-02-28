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

import system, macros, arraymancer, future, math
import arraymancer

import ./am_slicing
import ./am_storageorder
import ../am # Cyclic reference by design
import ../../spaceconf

type
  AmDirectNDSampler[T] = object
    msource: ptr AmBackendCpu[T]


proc initAmDirectNDSampler*[T](b: var AmBackendCpu[T]): AmDirectNDSampler[T] =
  result.msource = b.addr


# We have to take this implementation of atIndex from the private internals
# of Tensor to at least eliminate the terribly inefficient flattening of an
# ND index.
proc tensorIndex[T](t: Tensor[T]; ind: openarray[int]): int =
  ## Convert [i, j, k, l ...] to the proper index.
  when compileOption("boundChecks"):
    assert ind.len <= t.rank

  result = t.offset
  for i in 0..<ind.len:
    result += t.strides[i]*ind[i]


proc tensorAt[T](t: Tensor[T]; ind: openarray[int]): T =
  result = t.data[t.tensorIndex(ind)]


proc tensorAt[T](t: var Tensor[T]; ind: openarray[int]): var T =
  result = t.data[t.tensorIndex(ind)]


# Super inefficient temporary implementation, using atIndex. Proof of concept. Where do we go from here?
proc msampleND*[T: SomeNumber](samp: AmDirectNDSampler[T]; ind: varargs[int]): var T =
  samp.msource[].backend_data.tensorAt(ind)


proc sampleND*[T: SomeNumber](samp: AmDirectNDSampler[T]; ind: varargs[int]): T =
  samp.msource[].backend_data.tensorAt(ind)


#iterator slice_values*[T](slc: var AmSliceCpu[T]): var T {.closure.} =
#  for x in mitems(backend_data(slc)):
#    yield x
#
#iterator backend_slice_values*[T](im: var AmBackendCpu[T]; idx: varargs[int]): var T {.closure.} =
#  var sliceseq = newSeq[iterator(): var T]()
#  for ch in idx:
#    sliceseq.add slice_values(ch)
#  block ZIP_ITERATION:
#    while true:
#      for it in mitems(sliceseq):
#        var v = it()
#        if finished(it):
#          break ZIP_ITERATION
#        yield v
#
#export slice_values
#export backend_slice_values

# All code below except for modifications by WINDGO, Inc. is copyright
# the Arraymancer contributors under the Apache 2.0 License.

## Iterators
type
  IterKind* = enum
    Values, Iter_Values, Offset_Values

template initStridedIteration*(coord, backstrides, iter_pos: untyped, t, iter_offset, iter_size: typed): untyped =
  ## Iterator init
  var iter_pos = 0
  withMemoryOptimHints() # MAXRANK = 8, 8 ints = 64 Bytes, cache line = 64 Bytes --> profit !
  var coord {.align64, noInit.}: array[MAXRANK, int]
  var backstrides {.align64, noInit.}: array[MAXRANK, int]
  for i in 0..<t.rank:
    backstrides[i] = t.strides[i]*(t.shape[i]-1)
    coord[i] = 0

  # Calculate initial coords and iter_pos from iteration offset
  if iter_offset != 0:
    var z = 1
    for i in countdown(t.rank - 1,0):
      coord[i] = (iter_offset div z) mod t.shape[i]
      iter_pos += coord[i]*t.strides[i]
      z *= t.shape[i]

template advanceStridedIteration*(coord, backstrides, iter_pos, t, iter_offset, iter_size: typed): untyped =
  ## Computing the next position
  for k in countdown(t.rank - 1,0):
    if coord[k] < t.shape[k]-1:
      coord[k] += 1
      iter_pos += t.strides[k]
      break
    else:
      coord[k] = 0
      iter_pos -= backstrides[k]

template stridedIterationYield*(strider: IterKind, data, i, iter_pos: typed) =
  ## Iterator the return value
  when strider == IterKind.Values: yield data[iter_pos]
  elif strider == IterKind.Iter_Values: yield (i, data[iter_pos])
  elif strider == IterKind.Offset_Values: yield (iter_pos, data[iter_pos]) ## TODO: remove workaround for C++ backend

template stridedIteration*(strider: IterKind, t, iter_offset, iter_size: typed): untyped =
  ## Iterate over a Tensor, displaying data as in C order, whatever the strides.

  # Get tensor data address with offset builtin
  withMemoryOptimHints()
  let data{.restrict.} = t.dataArray # Warning ⚠: data pointed may be mutated

  # Optimize for loops in contiguous cases
  if t.is_C_Contiguous:
    for i in iter_offset..<(iter_offset+iter_size):
      stridedIterationYield(strider, data, i, i)
  else:
    initStridedIteration(coord, backstrides, iter_pos, t, iter_offset, iter_size)
    for i in iter_offset..<(iter_offset+iter_size):
      stridedIterationYield(strider, data, i, iter_pos)
      advanceStridedIteration(coord, backstrides, iter_pos, t, iter_offset, iter_size)

template stridedCoordsIteration*(t, iter_offset, iter_size: typed): untyped =
  ## Iterate over a Tensor, displaying data as in C order, whatever the strides. (coords)

  # Get tensor data address with offset builtin
  withMemoryOptimHints()
  let data{.restrict.} = t.dataArray # Warning ⚠: data pointed may be mutated
  let rank = t.rank

  initStridedIteration(coord, backstrides, iter_pos, t, iter_offset, iter_size)
  for i in iter_offset..<(iter_offset+iter_size):
    yield (coord[0..<rank], data[iter_pos])
    advanceStridedIteration(coord, backstrides, iter_pos, t, iter_offset, iter_size)

