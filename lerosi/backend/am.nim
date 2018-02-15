import system, macros, arraymancer, future


type
  AmBackend*[Storage] = object
    is_init: bool
    d: Storage

  AmBackendCpu*[T] = AmBackend[Tensor[T]]
  # Waiting for opencl, cuda, cpu conversion procs.
  #AmBackendCuda*[T] = AmBackend[CudaTensor[T]]
  #AmBackendCL*[T] = AmBackend[ClTensor[T]]

  AmShape* = MetadataArray


proc `==`*[Storage](a, b: AmBackend[Storage]): bool {.inline.} =
  a.is_init and b.is_init and (a.d == b.d)


proc backend_initialized*[Storage](b: AmBackend[Storage]):
    bool {.inline, noSideEffect, raises: [].} =
  
  b.is_init

template asis(d, s: untyped): untyped = d
template ascpu[T](d: seq[T], s: AmShape): Tensor[T] = d.toTensor().reshape(s)

# Waiting for opencl, cuda, cpu conversion procs.
#template ascuda[T](d: seq[T], s: AmShape): CudaTensor[T] = d.as_cpu_data(s).cuda
#template asocl[T](d: seq[T], s: AmShape): ClTensor[T] = d.as_cpu_data(s).opencl
#
template initraw(fn, b, d, s: untyped): untyped =
  b.d = fn(d, s)
  b.is_init = true
  b

proc backend_data*[Storage](b: var AmBackend[Storage], d: Storage):
    var AmBackend[Storage] {.discardable, inline, noSideEffect, raises: [].} =
  initraw(asis, b, d, "")

proc backend_data_raw*[T](b: var AmBackendCpu[T], d: seq[T], s: AmShape):
    var AmBackendCpu[T] {.discardable, inline.} = initraw(ascpu, b, d, s)

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

proc backend_data*[Storage](b: AmBackend[Storage]): Storage {.inline.} =
  backend_data_check(b)
  result = b.d

proc backend_data*[Storage](b: var AmBackend[Storage]): var Storage {.inline.} =
  backend_data_check(b)
  result = b.d

proc backend_data_raw*[Storage](b: AmBackend[Storage]): seq[Storage.T] {.inline.} =
  backend_data_check(b)
  result = b.d.data

proc backend_data_raw*[Storage](b: var AmBackend[Storage]):
    var seq[Storage.T] {.inline.} =

  backend_data_check(b)
  result = b.d.data

proc backend_data_shape*[Storage](b: var AmBackend[Storage], s: AmShape):
    var AmBackend[Storage] {.discardable, inline.} =

  backend_data_check(b)
  b.d = b.d.reshape(s)

proc backend_data_shape*[Storage](b: AmBackend[Storage]):
    AmShape {.inline.} =

  backend_data_check(b)
  result = b.d.shape

proc backend_cmp*[AS, BS](a: AmBackend[AS], b: AmBackend[BS]): bool {.inline.} =
  when (AS is BS) and (BS is AS):
    result = (a.d.shape == b.d.shape) and (a.d == b.d)
  else:
    result = false

# Deferred import resolves a cyclic import. With this, the storageorder
# and slicing submodules can safely import ../amcpu, and have access to the
# above.
import ./am/am_storageorder
import ./am/am_slicing

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

#template backend_local_source(dest, src, fmap: untyped): untyped =
#  backend_data_check(src)
#  when dest.d is CudaTensor:
#    # As of 0.3.0, CudaTensor does not support inlined mapping.
#    dest.d = src.d.map(fmap)
#  else:
#    dest.d = map_inline(src.d):
#      fmap(x)
#  dest.is_init = true

# map_inline requires things from arraymancer, and for some reason wrapping
# it in an inline procedure does not shield the user of lerosi/backend/am
# from requiring arraymancer. Compiler bug?
proc backend_local_source_impl[T; U](
    dest: var AmBackendCpu[T];
    src: AmBackendCpu[U];
    fmap: proc (x: U): T) {.inline.} =

  backend_data_check(src)
  dest.d = newTensorUninit[T](src.backend_data_shape)
  for i in 0..<src.d.shape.product:
    dest.d.data[i] = fmap(src.d.data[i])

  #apply2_inline(dest.d, src.d):
  #  fmap(y)
  dest.is_init = true

proc backend_local_source*[T; U](
    dest: var AmBackendCpu[T];
    src: AmBackendCpu[U];
    fmap: proc (x: U): T) =

  proc fmap_wrapper(x: U): T = fmap(x)
  backend_local_source_impl(dest, src, fmap_wrapper)

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

export am_storageorder, am_slicing
export arraymancer


