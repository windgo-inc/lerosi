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

import system, macros, arraymancer, future
import ../spaceconf

type
  #AmBackend*[T] = object
  #  is_init: bool
  #  d: Storage

  AmBackendCpu*[T] = object
    is_init: bool
    d: Tensor[T]
  # Waiting for opencl, cuda, cpu conversion procs.
  #AmBackendCuda*[T] = AmBackend[CudaTensor[T]]
  #AmBackendCL*[T] = AmBackend[ClTensor[T]]

  AmShape* = MetadataArray


proc `==`*[T](a, b: AmBackendCpu[T]): bool {.inline.} =
  a.is_init and b.is_init and (a.d == b.d)


proc backend_initialized*[T](b: AmBackendCpu[T]):
    bool {.inline, noSideEffect, raises: [].} =
  
  b.is_init

template asis(d, s: untyped): untyped = d
template ascpu[T](d: seq[T], s: untyped): Tensor[T] = d.toTensor().reshape(s)

# Waiting for opencl, cuda, cpu conversion procs.
#template ascuda[T](d: seq[T], s: AmShape): CudaTensor[T] = d.as_cpu_data(s).cuda
#template asocl[T](d: seq[T], s: AmShape): ClTensor[T] = d.as_cpu_data(s).opencl
#
template initraw(fn, b, d, s: untyped): untyped =
  b.d = fn(d, s)
  b.is_init = true
  b

proc backend_data_noinit*[T](b: var AmBackendCpu[T], s: AmShape):
    var AmBackendCpu[T] {.discardable, inline.} =
  let d = newTensorUninit[T](s)
  initraw(asis, b, d, "")

proc backend_data_noinit*[T](b: var AmBackendCpu[T], s: varargs[int]):
    var AmBackendCpu[T] {.discardable, inline.} =
  let d = newTensorUninit[T](s)
  initraw(asis, b, d, "")

proc backend_data*[T](b: var AmBackendCpu[T], d: Tensor[T]):
    var AmBackendCpu[T] {.discardable, inline, noSideEffect, raises: [].} =
  initraw(asis, b, d, "")

proc backend_data_raw*[T](b: var AmBackendCpu[T], d: seq[T], s: AmShape):
    var AmBackendCpu[T] {.discardable, inline.} = initraw(ascpu, b, d, s)

proc backend_data_raw*[T](b: var AmBackendCpu[T], d: seq[T], s: varargs[int]):
    var AmBackendCpu[T] {.discardable, inline.} =
  initraw(ascpu, b, d, s)


# Waiting for opencl, cuda, cpu conversion procs.
#proc backend_data_raw*[T](b: var AmBackendCuda[T], d: seq[T], s: AmShape):
#    var AmBackendCuda[T] {.discardable, inline.} = initraw(ascuda, b, d, s)

#proc backend_data_raw*[T](b: var AmBackendCL[T], d: seq[T], s: AmShape):
#    var AmBackendCL[T] {.inline.} = initraw(asocl, b, d, s)

template backend_data_check(b: untyped): untyped =
  when compileOption("boundChecks"):
    if not b.is_init:
      raise newException(ValueError,
        "LERoSI/backend/am - backend data access; data are uninitialized.")

proc backend_data*[T](b: AmBackendCpu[T]): Tensor[T] {.inline.} =
  backend_data_check(b)
  result = b.d

proc backend_data*[T](b: var AmBackendCpu[T]): var Tensor[T] {.inline.} =
  backend_data_check(b)
  result = b.d

proc backend_data_raw*[T](b: AmBackendCpu[T]): seq[T] {.inline.} =
  backend_data_check(b)
  result = b.d.data

proc backend_data_raw*[T](b: var AmBackendCpu[T]): var seq[T] {.inline.} =

  backend_data_check(b)
  result = b.d.data

proc backend_data_shape*[T](b: var AmBackendCpu[T], s: AmShape):
    var AmBackendCpu[T] {.discardable, inline.} =

  backend_data_check(b)
  b.d = b.d.reshape(s)

proc backend_data_shape*[T](b: AmBackendCpu[T]):
    AmShape {.inline.} =

  backend_data_check(b)
  result = b.d.shape

proc backend_cmp*[A, B](a: AmBackendCpu[A], b: AmBackendCpu[B]): bool {.inline.} =
  when (A is B) and (B is A):
    result = (a.d.shape == b.d.shape) and (a.d == b.d)
  else:
    result = false

# Deferred import resolves a cyclic import. With this, the storageorder
# and slicing submodules can safely import ../amcpu, and have access to the
# above.
export arraymancer
import ./am/am_storageorder
import ./am/am_slicing

export am_storageorder, am_slicing

proc backend_channel_count*[T](b: var AmBackendCpu[T];
    order: DataOrder): int {.inline.} =

  backend_data_check(b)
  case order
  of DataPlanar: result = b.d.shape[0]
  of DataInterleaved: result = b.d.shape[b.d.shape.len - 1]

proc backend_image_shape*[T](b: var AmBackendCpu[T];
    order: DataOrder): int {.inline.} =

  backend_data_check(b)
  case order
  of DataPlanar: result = b.d.shape[1..b.d.shape.len - 1]
  of DataInterleaved: result = b.d.shape[0..b.d.shape.len - 2]


proc backend_image_cmp*[A, B](a: AmBackendCpu[A];
    b: AmBackendCpu[B]; aOrder, bOrder: DataOrder): bool =

  result = (backend_image_shape(a, aOrder) == backend_image_shape(b, bOrder)) and
           (backend_channel_count(a, aOrder) == backend_channel_count(b, bOrder))

  block CHECK_IMAGE_EQ:
    if result:
      for i in 0..<backend_channel_count(a, aOrder):
        result = slice_channel(a, aOrder) == slice_channel(b, bOrder)
        if not result:
          break CHECK_IMAGE_EQ

import ./am/am_accessors
export am_accessors

type
  AmBackendGeneral*[T] = concept backend
    backend is AmBackendCpu[T] #or
    #  backend is AmBackendCuda[T]

  AmBackendNotCpu*[T] = concept backend
    backend is AmBackendGeneral[T]
    not (backend is AmBackendCpu[T])

  #AmBackendNotCuda*[T] = concept backend
  #  backend is AmBackendGeneral[T]
  #  not (backend is AmBackendCuda[T])

  #AmBackendNotCL*[T] = concept backend
  #  backend is AmBackend
  #  #not (backend is AmBackendCL)


proc backend_local_source[T; U](
    dest: var AmBackendCpu[T];
    src: AmBackendCpu[U]) {.inline.} =
  backend_data_check(src)
  when (T is U) and (U is T):
    dest.d = src.d
  else:
    dest.d = src.d.asType(T)
  dest.is_init = true

# map_inline requires things from arraymancer, and for some reason wrapping
# it in an inline procedure does not shield the user of lerosi/backend/am
# from requiring arraymancer.
proc backend_local_source_impl[T; U](
    dest: var AmBackendCpu[T];
    src: AmBackendCpu[U];
    fmap: proc (x: U): T) {.inline.} =

  backend_data_check(src)
  dest.d = newTensorUninit[T](src.backend_data_shape)
  #for i in 0..<src.d.shape.product:
  #  dest.d.data[i] = fmap(src.d.data[i])

  apply2_inline(dest.d, src.d):
    fmap(y)
  dest.is_init = true

proc backend_local_source*[T; U](
    dest: var AmBackendCpu[T];
    src: AmBackendCpu[U];
    fmap: proc (x: U): T) =

  proc fmap_wrapper(x: U): T = fmap(x)
  backend_local_source_impl(dest, src, fmap_wrapper)

# TODO: Is there a more efficient way (in arraymancer) than to concatinate?
proc backend_slices_source_impl[T; U](
    dest: var AmBackendCpu[T];
    order: DataOrder;
    slices: openarray[AmSliceCpu[U]]) =

  when compileOption("boundChecks"):
    assert 1 <= slices.len,
      "Bound check failed, must specify at least one slice as a source."

  let sh = slices[0].slice_data.shape

  when compileOption("boundChecks"):
    for i in 1..<slices.len:
      assert sh == slices[0].slice_data.shape

  var tacc = slices[0].slice_data.squeeze.unsqueeze(0)
  for i in 1..<slices.len:
    let nextslice = slices[i].slice_data.squeeze.unsqueeze(0)
    tacc = concat(tacc, nextslice, axis = 0)

  if order == DataPlanar:
    discard dest.backend_data(tacc.asContiguous)
  else:
    # asContiguous not needed, invoked by backend_rotate
    discard dest.backend_data(tacc).backend_rotate(DataInterleaved)


proc backend_slices_source*[T; U](
    dest: var AmBackendCpu[T];
    order: DataOrder;
    slices: varargs[AmSliceCpu[U]]) {.inline.} =

  backend_slices_source_impl(dest, order, slices)


proc backend_slices_source*[T; U](
    dest: var AmBackendCpu[T];
    order: DataOrder;
    slices: seq[AmSliceCpu[U]]) {.inline.} =

  backend_slices_source_impl(dest, order, slices)


macro implement_backend_source(kind, notkind, conv: untyped): untyped =
  result = quote do:
    proc backend_source*[T; U](
        dest: var `kind`[T];
        src: `kind`[U]) {.inline.} =
      backend_local_source(dest, src)
    proc backend_source*[T; U](
        dest: var `kind`[T];
        src: `kind`[U]; fmap: proc (x: U): T) {.inline.} =
      backend_local_source(dest, src, fmap)
    #proc backend_source*[T; U](
    #    dest: var `kind`[T];
    #    src: `notkind`[U]) =
    #  backend_data_check(src)
    #  dest.d = `conv`(src.d).reshape(src.d.data.shape).asType(T)
    #  dest.is_init = true
    #proc backend_source*[T; U](
    #    dest: var `kind`[T];
    #    src: `notkind`[U]; fmap: proc (x: U): T) {.inline.} =
    #  backend_data_check(src)
    #  dest.d = `conv`(src.d).reshape(src.d.data.shape).asType(T)
    #  dest.is_init = true

proc to_storage_cpu_detail[T](ct: CudaTensor[T]): Tensor[T] {.inline.} =
  ct.data.toTensor()
  

#implement_backend_source(AmBackendCpu, AmBackendNotCpu, cpu)
implement_backend_source(AmBackendCpu, AmBackendNotCpu, to_storage_cpu_detail)
#implement_backend_source(AmBackendCuda, AmBackendNotCuda, cuda)
#implement_backend_source(AmBackendCL, AmBackendNotCL, opencl)



