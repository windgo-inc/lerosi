import system, macros, arraymancer
import ../am
import ../../spaceconf

type
  AmSlice*[Storage] = object
    d: Storage

  AmSliceCpu*[T]  = AmSlice[Tensor[T]]
  AmSliceCuda*[T] = AmSlice[CudaTensor[T]]
  #AmSliceCL*[T]   = AmSlice[ClTensor[T]]

proc `==`*[Storage](a, b: AmSlice[Storage]): bool {.inline.} =
  a.d == b.d

template slicer_interleaved_impl(n, d: typed): untyped =
  case n
  of 2: d[_, i].squeeze(1)
  of 3: d[_, _, i].squeeze(2)
  of 4: d[_, _, _, i].squeeze(3)
  of 5: d[_, _, _, _, i].squeeze(4)
  of 6: d[_, _, _, _, _, i].squeeze(5)
  of 7: d[_, _, _, _, _, _, i].squeeze(6)
  else: d

template mslicer_interleaved_impl(n, d, x: typed): untyped =
  case n
  of 2: d[_, i] = x.unsqueeze(1)
  of 3: d[_, _, i] = x.unsqueeze(2)
  of 4: d[_, _, _, i] = x.unsqueeze(3)
  of 5: d[_, _, _, _, i] = x.unsqueeze(4)
  of 6: d[_, _, _, _, _, i] = x.unsqueeze(5)
  of 7: d[_, _, _, _, _, _, i] = x.unsqueeze(6)
  else: discard

proc `==`*[B: AmSlice](a, b: B): bool =
  a.d == b.d

proc slice_channel_planar*[B](b: B, i: int):
    AmSlice[B.Storage] {.inline.} =

  when compileOption("boundChecks"):
    assert(0 <= i and i < 7)

  let d = b.backend_data
  result.d = d[i, _].squeeze(0)

proc slice_channel_interleaved*[B](b: B, i: int):
    AmSlice[B.Storage] {.inline.} =

  when compileOption("boundChecks"):
    assert(0 <= i and i < 7)

  let d = b.backend_data
  result.d = slicer_interleaved_impl(d.shape.len, d)

proc mslice_channel_planar*[B](b: var B,
    i: int, x: AmSlice[B.Storage]):
    var B {.discardable, inline.} =

  when compileOption("boundChecks"):
    assert(0 <= i and i < 7)

  let d = b.backend_data
  d[i, _] = x.d.unsqueeze(0)
  result = b

proc mslice_channel_interleaved*[B](b: var B,
    i: int, x: AmSlice[B.Storage]):
    var B {.discardable, inline.} =

  when compileOption("boundChecks"):
    assert(0 <= i and i < 7)

  let d = b.backend_data
  mslicer_interleaved_impl(d.shape.len, d, x)
  result = b
  
template slice_channel*[B](b: B,
    order: DataOrder, i: int): AmSlice[B.Storage] =

  (case order
  of DataPlanar: slice_channel_planar(b, i)
  of DataInterleaved: slice_channel_interleaved(b, i))

template mslice_channel*[B](b: var B,
    order: DataOrder, i: int, x: AmSlice[B.Storage]): untyped =

  (case order
  of DataPlanar: mslice_channel_planar(b, i, x)
  of DataInterleaved: mslice_channel_interleaved(b, i, x))

proc slice_shape*[Storage](x: AmSlice[Storage]): AmShape {.inline.} =
  x.d.shape

proc slice_reshaped*[Storage](x: AmSlice[Storage], s: AmShape):
    AmSlice[Storage] {.inline.} =

  result.d = x.d.reshape(s)

proc slice_data*[Storage](x: AmSlice[Storage]): Storage {.inline.} =
  result = x.d

