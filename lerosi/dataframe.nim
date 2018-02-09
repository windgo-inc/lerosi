import macros, sequtils, strutils, tables, future
import system

import ./macroutil
import ./fixedseq
import ./img_permute
import ./img_conf

export img_conf

type
  RWFrameObject*[Backend] = object
    ## Readable and writable concrete frame object,
    ## intended for inplace manipulation
    dat: Backend
    ordr: DataOrder

  ROFrameObject*[Backend] = object
    ## Read only concrete frame object, intended
    ## for streaming input interfaces.
    dat: Backend
    ordr: DataOrder

  WOFrameObject*[Backend] = object
    ## Write only concrete frame object, intended
    ## for streaming output interfaces.
    dat: Backend
    ordr: DataOrder


proc frame_data*[U: ROFrameObject|RWFrameObject](frame: U): U.Backend =
  ## Frame data accessor for readable data frame objects.
  frame.dat

proc frame_data*[U: RWFrameObject](frame: var U): var U.Backend =
  ## Frame data mutable accessor for read-write data frame objects.
  frame.dat

proc frame_order*[U: RWFrameObject|ROFrameObject|WOFrameObject](frame: U):
    DataOrder =
  ## Get the ordering of any frame object, including write only frame objects.
  ## This is neccesary to determine what the ordering of the data to write must
  ## be.
  frame.ordr

proc `frame_data=`*[U: RWFrameObject|WOFrameObject](frame: var U,
    data: U.Backend) =
  ## Frame data setter for writable data frames.
  frame.dat = data

proc `frame_order=`*[U: RWFrameObject|WOFrameObject](
    frame: U; order: DataOrder) =
  ## Set the ordering of a writable frame object. Note that this will not
  ## rotate the storage order for any data written; it is the responsibility
  ## of the caller to ensure that the written data are in the right order.
  frame.ordr = order


type
  ReadDataFrame*[Backend] = concept frame
    ## A readable DataFrame, having a frame_data getter yielding a Backend
    frame.frame_data is Backend

  WriteDataFrame*[Backend] = concept frame
    ## A writable DataFrame, having a frame_data setter accepting a Backend
    frame.frame_data = Backend
    
  DataFrame*[Backend] = concept frame
    ## A readable or writable DataFrame
    frame is ReadDataFrame[Backend] or frame is WriteDataFrame[Backend]

  ReadOnlyDataFrame*[Backend] = concept frame
    ## A readable data frame which is not writable.
    frame is ReadDataFrame[Backend]
    not (frame is WriteDataFrame[Backend])

  WriteOnlyDataFrame*[Backend] = concept frame
    ## A writable data frame which is not readable.
    frame is WriteDataFrame[Backend]
    not (frame is ReadDataFrame[Backend])



when isMainModule:
  import arraymancer # Needed for atypical access to internals for testing.
  import ./backend/am # Temporary, not needed from here.

  template checkFrameConcepts(frame: untyped): untyped =
    trace_result(frame is DataFrame)
    trace_result(frame is ReadDataFrame)
    trace_result(frame is WriteDataFrame)
    trace_result(frame is ReadOnlyDataFrame)
    trace_result(frame is WriteOnlyDataFrame)

    var backend: AMBackendCpu[int]
    trace_result(compiles((frame.data)))
    trace_result(compiles((frame.data = backend)))

  var myFrame: RWFrameObject[AmBackendCpu[int]]
  var myReadOnly: ROFrameObject[AmBackendCpu[int]]
  var myWriteOnly: WOFrameObject[AmBackendCpu[int]]

  checkFrameConcepts(myFrame)
  checkFrameConcepts(myReadOnly)
  checkFrameConcepts(myWriteOnly)
  
  var myCpuData: AmBackendCpu[int]
  var planarSlices: array[0..2, AmSliceCpu[int]]
  var interleavedSlices: array[0..2, AmSliceCpu[int]]

  let testSlice = [
    [1, 2, 3, 4, 5],
    [6, 7, 8, 9, 10],
    [11, 12, 13, 14, 15],
    [16, 17, 18, 19, 20],
    [21, 22, 23, 24, 25]
  ].toTensor().reshape(1, 5, 5)

  myCpuData.backend_data(
    concat(testSlice, testSlice .+ 25, testSlice .+ 50, axis = 0))

  echo "Checking planar channel slices:"
  for i in 0..2:
    planarSlices[i] = myCpuData.slice_channel(DataPlanar, i)
    echo "[SLICE ", i, " ", planarSlices[i].slice_shape, "] ",
      planarSlices[i].slice_data

  echo "Rotating to interleaved."
  echo "myCpuData.backend_rotate DataInterleaved"
  myCpuData.backend_rotate DataInterleaved

  echo "Checking interleaved channel slices:"
  for i in 0..2:
    interleavedSlices[i] = myCpuData.slice_channel(DataInterleaved, i)
    echo "[SLICE ", i, " ", interleavedSlices[i].slice_shape, "] ",
      interleavedSlices[i].slice_data

  echo "Checking equality..."
  for i in 0..2:
    let slice1 = planarSlices[i].slice_data
    let slice2 = interleavedSlices[i].slice_data
    echo((if slice1 == slice2: "[OK " else: "[FAIL "), i, "]")

  echo "Rotating to planar."
  echo "myCpuData.backend_rotate DataPlanar"
  myCpuData.backend_rotate DataPlanar

  echo "Checking restored planar channel slice consistency:"
  for i in 0..2:
    let isgood =
      myCpuData.slice_channel(DataPlanar, i) == interleavedSlices[i]
    echo((if isgood: "[OK " else: "[FAIL "), i, "]")


