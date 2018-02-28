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
import ../am
import ../../spaceconf


type
  #AmSlice*[Storage] = object
  #  d: Storage

  AmSliceCpu*[T] = object
    d: Tensor[T]

  #AmSliceCuda*[T] = AmSlice[CudaTensor[T]]
  #AmSliceCL*[T]   = AmSlice[ClTensor[T]]


proc `==`*[T](a, b: AmSliceCpu[T]): bool {.inline.} =
  a.d == b.d


proc slice_copy*[T](b: AmSliceCpu[T]): AmSliceCpu[T] {.inline.} =
  result.d = zeros_like(b.d).asContiguous
  deepCopy result.d.data, b.d.asContiguous.data


template slicer_interleaved_impl(n, d, i: typed): untyped =
  block:
    when compileOption("boundChecks"):
      assert(2 <= n and n <= 7)

    d.atAxisIndex(n-1, i).squeeze(n-1)


template slicer_interleaved_mut_impl(n, d, i: typed): untyped =
  block:
    when compileOption("boundChecks"):
      assert(2 <= n and n <= 7)

    var r = d.atAxisIndex(n-1, i).squeeze(n-1)
    r

template mslicer_interleaved_impl(n, d, i, x: typed): untyped =
  case n
  of 2: d[_, i] = x.unsqueeze(1)
  of 3: d[_, _, i] = x.unsqueeze(2)
  of 4: d[_, _, _, i] = x.unsqueeze(3)
  of 5: d[_, _, _, _, i] = x.unsqueeze(4)
  of 6: d[_, _, _, _, _, i] = x.unsqueeze(5)
  of 7: d[_, _, _, _, _, _, i] = x.unsqueeze(6)
  else: discard


proc slice_channel_planar*[T](b: AmBackendCpu[T], i: int):
    AmSliceCpu[T] {.inline.} =

  when compileOption("boundChecks"):
    assert(0 <= i and i < MAX_IMAGE_CHANNELS)

  let d = b.backend_data
  result.d = d[i, _].squeeze(0)


proc slice_channel_planar*[T](b: var AmBackendCpu[T], i: int):
    var AmSliceCpu[T] {.inline.} =

  when compileOption("boundChecks"):
    assert(0 <= i and i < MAX_IMAGE_CHANNELS)

  var d = b.backend_data
  result.d = d[i, _].squeeze(0)


proc slice_channel_interleaved*[T](b: AmBackendCpu[T], i: int):
    AmSliceCpu[T] {.inline.} =

  when compileOption("boundChecks"):
    assert(0 <= i and i < MAX_IMAGE_CHANNELS)

  let d = b.backend_data
  result.d = slicer_interleaved_impl(d.shape.len, d, i)


proc slice_channel_interleaved*[T](b: var AmBackendCpu[T], i: int):
    var AmSliceCpu[T] {.inline.} =

  when compileOption("boundChecks"):
    assert(0 <= i and i < MAX_IMAGE_CHANNELS)

  var d = b.backend_data
  result.d = slicer_interleaved_mut_impl(d.shape.len, d, i)


proc slice_channel_planar_zero*[T](b: AmBackendCpu[T]):
    AmSliceCpu[T] {.inline.} =

  let d = b.backend_data
  result.d = d[0, _].zeros_like.squeeze(0)


proc slice_channel_interleaved_zero*[T](b: AmBackendCpu[T]):
    AmSliceCpu[T] {.inline.} =

  let d = b.backend_data
  result.d = slicer_interleaved_impl(d.shape.len, d, 0).zeros_like


proc slice_channel_planar_one*[T](b: AmBackendCpu[T]):
    AmSliceCpu[T] {.inline.} =

  let d = b.backend_data
  result.d = d[0, _].ones_like.squeeze(0)


proc slice_channel_interleaved_one*[T](b: AmBackendCpu[T]):
    AmSliceCpu[T] {.inline.} =

  let d = b.backend_data
  result.d = slicer_interleaved_impl(d.shape.len, d, 0).ones_like


proc mslice_channel_planar*[T](b: var AmBackendCpu[T],
    i: int, x: AmSliceCpu[T]):
    var AmBackendCpu[T] {.discardable, inline.} =

  when compileOption("boundChecks"):
    assert(0 <= i and i < MAX_IMAGE_CHANNELS)

  var d = b.backend_data
  let slc = x.slice_data.asContiguous
  d[i, _] = slc.unsqueeze(0)
  result = b


proc mslice_channel_interleaved*[T](b: var AmBackendCpu[T],
    i: int, x: AmSliceCpu[T]):
    var AmBackendCpu[T] {.discardable, inline.} =

  when compileOption("boundChecks"):
    assert(0 <= i and i < MAX_IMAGE_CHANNELS)

  var d = b.backend_data
  mslicer_interleaved_impl(d.shape.len, d, i, x.slice_data.asContiguous)
  result = b
  

template slice_channel*[T](b: AmBackendCpu[T], order: DataOrder, i: int): AmSliceCpu[T] =
  case order
  of DataPlanar: slice_channel_planar(b, i)
  of DataInterleaved: slice_channel_interleaved(b, i)


#template slice_channel*[T](b: var AmBackendCpu[T], order: DataOrder, i: int): var AmSliceCpu[T] =
#  block:
#    var 
#      r = (case order
#        of DataPlanar: slice_channel_planar(b, i)
#        of DataInterleaved: slice_channel_interleaved(b, i))
#    r


template slice_channel_zero*[T](b: AmBackendCpu[T], order: DataOrder): AmSliceCpu[T] =
  case order
  of DataPlanar: slice_channel_planar_zero(b)
  of DataInterleaved: slice_channel_interleaved_zero(b)


template slice_channel_one*[T](b: AmBackendCpu[T], order: DataOrder): AmSliceCpu[T] =
  case order
  of DataPlanar: slice_channel_planar_one(b)
  of DataInterleaved: slice_channel_interleaved_one(b)


template mslice_channel*[B](b: var B,
    order: DataOrder, i: int, x: AmSliceCpu[B.T]): untyped =

  block:
    var r: B
    case order
    of DataPlanar: r = mslice_channel_planar(b, i, x)
    of DataInterleaved: r = mslice_channel_interleaved(b, i, x)
    r


#proc slice_channel_combine*[B](b: var B,
#    order: DataOrder, i: int, x: openarray[AmSliceCpu[B.T]]): AmBackendCpu[B =
#  # TODO: Move this from initFrame


#template slice_transform_space*[B](be_in: B; order: DataOrder; channel_user: untyped): untyped =
#  var chans: FixedSeq[AmSliceCpu[B.T], MAX_IMAGE_CHANNELS]
#  chans.setLen be_in.
  


proc slice_shape*[T](x: AmSliceCpu[T]): AmShape {.inline.} =
  ## Get the shape of the slice.
  x.d.shape


proc slice_reshaped*[T](x: AmSliceCpu[T], s: AmShape):
    AmSliceCpu[T] {.inline.} =
  ## Reshape the slice, returning a new slice.

  result.d = x.d.reshape(s)


proc slice_data*[T](x: AmSliceCpu[T]): Tensor[T] {.inline.} =
  ## Get the immutable slice backend representation data
  result = x.d


proc slice_data*[T](x: var AmSliceCpu[T]): var Tensor[T] {.inline.} =
  ## Get the mutable slice backend representation data
  result = x.d


