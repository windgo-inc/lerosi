import system, macros, arraymancer


type
  AmBackend*[Storage] = object
    is_init: bool
    d: Storage

  AmBackendCpu*[T] = AmBackend[Tensor[T]]
  AmBackendCuda*[T] = AmBackend[CudaTensor[T]]
  # Not ready yet
  #AmBackendCL*[T] = AmBackend[ClTensor[T]]

  AmShape* = MetadataArray


proc backend_initialized*[Storage](b: AmBackend[Storage]):
    bool {.inline, noSideEffect, raises: [].} =
  
  b.is_init

template asis(d, s: untyped): untyped = d
template ascpu[T](d: seq[T], s: AmShape): Tensor[T] = d.toTensor().reshape(s)
template ascuda[T](d: seq[T], s: AmShape): CudaTensor[T] = d.as_cpu_data(s).cuda
#template asocl[T](d: seq[T], s: AmShape): ClTensor[T] = d.as_cpu_data(s).opencl
template initraw(fn, b, d, s: untyped): untyped =
  b.d = fn(d, s)
  b.is_init = true
  b

proc backend_data*[Storage](b: var AmBackend[Storage], d: Storage):
    var AmBackend[Storage] {.discardable, inline, noSideEffect, raises: [].} =
  initraw(asis, b, d, "")

proc backend_data_raw*[T](b: var AmBackendCpu[T], d: seq[T], s: AmShape):
    var AmBackendCpu[T] {.discardable, inline.} = initraw(ascpu, b, d, s)

proc backend_data_raw*[T](b: var AmBackendCuda[T], d: seq[T], s: AmShape):
    var AmBackendCuda[T] {.discardable, inline.} = initraw(ascuda, b, d, s)

#proc backend_data_raw*[T](b: var AmBackendCL[T], d: seq[T], s: AmShape):
#    var AmBackendCpu[T] {.inline.} = initraw(asocl, b, d, s)

template backend_data_check(b: untyped): untyped =
  when compileOption("boundChecks"):
    if not b.is_init:
      raise newException(ValueError,
        "LERoSI/backend/am - backend data access; data are uninitialized.")

proc backend_data*[Storage](b: AmBackend[Storage]): Storage {.inline.} =
  b.backend_data_check
  result = b.d

proc backend_data*[Storage](b: var AmBackend[Storage]): var Storage {.inline.} =
  b.backend_data_check
  result = b.d

proc backend_data_raw*[Storage](b: AmBackend[Storage]): seq[Storage.T] {.inline.} =
  b.backend_data_check
  result = b.d.data

proc backend_data_raw*[Storage](b: var AmBackend[Storage]):
    var seq[Storage.T] {.inline.} =

  b.backend_data_check
  result = b.d.data

proc backend_data_shape*[Storage](b: var AmBackend[Storage], s: AmShape):
    var AmBackend[Storage] {.discardable, inline.} =

  b.backend_data_check
  b.d = b.d.reshape(s)

proc backend_data_shape*[Storage](b: var AmBackend[Storage]): AmShape =
  b.backend_data_check
  result = b.d.shape

# Deferred import resolves a cyclic import. With this, the storageorder
# and slicing submodules can safely import ../amcpu, and have access to the
# above.
import ./am/am_storageorder
import ./am/am_slicing

export am_storageorder, am_slicing

