import system, macros, arraymancer
import ../am
import ../../img_conf

type
  AmSlice*[Storage] = AmBackend[Storage]

template slicer_interleaved_impl(n, d: typed): untyped =
  case n
  of 2: d[_, i]
  of 3: d[_, _, i]
  of 4: d[_, _, _, i]
  of 5: d[_, _, _, _, i]
  of 6: d[_, _, _, _, _, i]
  of 7: d[_, _, _, _, _, _, i]
  else: d

template mslicer_interleaved_impl(n, d, x: typed): untyped =
  case n
  of 2: d[_, i] = x
  of 3: d[_, _, i] = x
  of 4: d[_, _, _, i] = x
  of 5: d[_, _, _, _, i] = x
  of 6: d[_, _, _, _, _, i] = x
  of 7: d[_, _, _, _, _, _, i] = x
  else: discard

proc slice_channel_planar*[B](b: B, i: int):
    AmSlice[B.Storage] {.inline.} =

  when compileoption("boundchecks"):
    assert(0 <= i and i < 7)

  let d = b.backend_data
  result.backend_data(d[i, _])

proc slice_channel_interleaved*[B](b: B, i: int):
    AmSlice[B.Storage] {.inline.} =

  when compileoption("boundchecks"):
    assert(0 <= i and i < 7)

  let d = b.backend_data
  result.backend_data(slicer_interleaved_impl(d.shape.len, d))

proc mslice_channel_planar*[B](b: var B,
    i: int, x: AmSlice[B.Storage]):
    var B {.discardable, inline.} =

  when compileoption("boundchecks"):
    assert(0 <= i and i < 7)

  let d = b.backend_data
  d[i, _] = x
  result = b

proc mslice_channel_interleaved*[B](b: var B,
    i: int, x: AmSlice[B.Storage]):
    var B {.discardable, inline.} =

  when compileoption("boundchecks"):
    assert(0 <= i and i < 7)

  let d = b.backend_data
  mslicer_interleaved_impl(d.shape.len, d, x)
  result = b
  
template slice_channel*[B](b: B,
    order: DataOrder, i: int): AmSlice[B.Storage] =

  case order
  of DataPlanar: slice_channel_planar(b, i)
  of DataInterleaved: slice_channel_interleaved(b, i)

template mslice_channel*[B](b: var B,
    order: DataOrder, i: int, x: AmSlice[B.Storage]): untyped =

  case order
  of DataPlanar: mslice_channel_planar(b, i)
  of DataInterleaved: mslice_channel_interleaved(b, i)


